require "math"

module Crystar
  # Writer provides sequential writing of a tar archive.
  # Writer#write_header begins a new file with the provided Header,
  # and then Writer can be treated as an io.Writer to supply that file's data via invoking Writer#write method .
  #
  # ### Example
  # ```
  # require "tar"
  #
  # File.open("./file.tar", "w") do |file|
  #   Crystar::Writer.open(file) do |tar|
  #     # add file to archive
  #     tar.add File.open("./some_file.txt")
  #     # Manually create the Header with info per your choice
  #     hdr = Header.new(
  #       name: "Your file Name",
  #       size: 100_i64,  # Contents size
  #       mode: 0o644_i64 # Permission and mode bits
  #     # ..... Look into `Crystar::Header`
  #     )
  #     tar.write_header hdr
  #     tar.write "your file contents".to_slice
  #
  #     # Create header from File you have already opened.
  #     hdr = file_info_header(file, file.path)
  #     tar.write_header hdr
  #     tar.write file.gets_to_end.to_slice
  #   end
  # end
  # ```
  class Writer
    # Whether to close the enclosed `IO` when closing this writer.
    property? sync_close = false

    # Returns `true` if this writer is closed.
    getter? closed = false
    # Amount of padding to write after current file entry
    @pad = 0_i64
    # Writer for current file entry
    @curr : FileWriter
    # Copy of Header that is safe for mutations
    setter hdr : Header
    # Buffer to use as temporary local storage
    @block : Block

    # Creates a new writer to the given *io*.
    def initialize(@io : IO, @sync_close = false)
      @block = Block.new
      @curr = RegFileWriter.new(@io, 0_i64)
      @hdr = Header.new
    end

    # Creates a new writer to the given *filename*.
    def self.new(filename : String)
      new(::File.new(filename, "w"), sync_close: true)
    end

    # Creates a new writer to the given *io*, yields it to the given block,
    # and closes it at the end.
    def self.open(io : IO, sync_close = false)
      writer = new(io, sync_close: sync_close)
      yield writer ensure writer.close
    end

    # Creates a new writer to the given *filename*, yields it to the given block,
    # and closes it at the end.
    def self.open(filename : String)
      writer = new(filename)
      yield writer ensure writer.close
    end

    # Adds an entry that will have its data copied from the given *file*.
    # file is automatically closed after data is copied from it.
    def add(file : File)
      hdr = Crystar.file_info_header(file, file.path)
      write_header hdr
      IO.copy(file, @curr)
      file.close
    end

    # Close closes the tar archive by flushing the padding, and writing the footer.
    # If the current file (from a prior call to WriteHeader) is not fully written,
    # then this returns an error.
    def close
      return if @closed
      # Trailer: two zero blocks.
      flush()
      0.upto(1) do |_|
        @io.write(Block.zero_block.to_bytes[..])
      end
      @io.close if @sync_close
      @closed = true
    end

    # :nodoc:
    def flush
      raise Error.new("Can't write to closed writer") if @closed

      if (nb = @curr.logical_remaining) && nb > 0
        raise Error.new "tar: missed writing #{nb} bytes"
      end

      @io.write(Block.zero_block.to_bytes[...@pad])
      @pad = 0
      nil
    end

    # write writes to the current file in the tar archive.
    # write returns the error ErrWriteTooLong if more than
    # Header#size bytes are written after WriteHeader.
    #
    # Calling write on special types like LINK, SYMLINK, CHAR,
    # BLOCK, DIR, and FIFO returns (0, ErrWriteTooLong) regardless
    # of what the Header#size claims.
    def write(b : Bytes) : Nil
      raise Error.new("Can't write to closed writer") if @closed
      @curr.write(b)
    end

    # write_header writes hdr and prepares to accept the file's contents.
    # The Header#size determines how many bytes can be written for the next file.
    # If the current file is not fully written, then this returns an error.
    # This implicitly flushes any padding necessary before writing the header.
    def write_header(hdr : Header) : Nil
      flush()

      @hdr = hdr # Shallow copy of header

      # Avoid usage of the legacy REGA flag, and automatically promote
      # it to use REG or DIR
      if @hdr.flag == REGA
        if @hdr.name.ends_with?("/")
          @hdr.flag = DIR.ord.to_u8
        else
          @hdr.flag = REG.ord.to_u8
        end
      end

      # Round ModTime and ignore AccessTime and ChangeTime unless
      # the format is explicitly chosen.
      # This ensures nominal usage of WriteHeader (without specifying the format)
      # does not always result in the PAX format being chosen, which
      # causes a 1KiB increase to every header.

      if @hdr.format.none?
        # TO-DO
        # Add round time
        # hdr.mod_time = round_time(SECOND)
        @hdr.access_time = Crystar.unix_time(0, 0)
        @hdr.change_time = Crystar.unix_time(0, 0)
      end

      allowed_formats, pax_hdrs = @hdr.allowed_formats
      case
      when allowed_formats.has(Format::USTAR)
        write_ustar_header(@hdr)
      when allowed_formats.has(Format::PAX)
        write_pax_header(@hdr, pax_hdrs)
      when allowed_formats.has(Format::GNU)
        write_gnu_header(@hdr)
      end
    end

    # :nodoc:
    private def write_ustar_header(hdr : Header) : Nil
      # Check if we can use USTAR prefix/suffix splitting.
      name_prefix = ""
      prefix, suffix, ok = Crystar.split_ustar_path(hdr.name)
      if ok
        name_prefix, hdr.name = prefix, suffix
      end

      # Pack the main header.
      f = Formatter.new
      blk = template_v7_plus(hdr, ->f.format_string(Bytes, String), ->f.format_octal(Bytes, Int64))
      f.format_string(blk.ustar.prefix, name_prefix)
      blk.set_format(Format::USTAR)

      write_raw_header(blk, hdr.size, hdr.flag)
    end

    # :nodoc:
    private def write_pax_header(hdr : Header, pax_hdrs : Hash(String, String)) : Nil
      # real_name, real_size = hdr.name, hdr.size
      real_name, _ = hdr.name, hdr.size
      # TO-DO
      # Add sparse support

      # Write PAX records to the output.
      is_global = hdr.flag == XGLOBAL_HEADER
      if pax_hdrs.size > 0 || is_global
        # Sort keys for deterministic ordering.
        keys = pax_hdrs.keys.sort

        # Write each record to a buffer
        data = String.build do |buf|
          keys.each do |k|
            rec = Crystar.format_pax_record(k, pax_hdrs.fetch(k, ""))
            buf << rec
          end
        end

        # Write the extended header file.
        name = ""
        flag = 0_u8
        if is_global
          name = real_name.blank? ? "GlobalHead.0.0" : real_name
          flag = XGLOBAL_HEADER.ord.to_u8
        else
          p = Path[real_name]
          if p.dirname == "."
            name = Path.new("PaxHeaders.0", p.basename).to_s
          else
            name = Path.new(p.dirname, "PaxHeaders.0", p.basename).to_s
          end
          flag = XHEADER.ord.to_u8
        end
        write_raw_file(name, data, flag, Format::PAX)
      end

      # Pack the main header.
      f = Formatter.new(true) # Ignore errors since they are expected
      fmt_str = ->(b : Bytes, s : String) {
        f.format_string(b, Crystar.to_ascii(s))
      }
      blk = template_v7_plus(hdr, fmt_str, ->f.format_octal(Bytes, Int64))
      blk.set_format(Format::PAX)
      write_raw_header(blk, hdr.size, hdr.flag)

      # TO-DO
      # Add sparse support
    end

    # :nodoc:
    private def write_gnu_header(hdr : Header) : Nil
      if hdr.name.size > NAME_SIZE
        data = hdr.name + "\x00"
        write_raw_file(LONG_NAME, data, GNU_LONGNAME.ord.to_u8, Format::GNU)
      end
      if hdr.link_name.size > NAME_SIZE
        data = hdr.link_name + "\x00"
        write_raw_file(LONG_NAME, data, GNU_LONGLINK.ord.to_u8, Format::GNU)
      end

      # Pack the main header.
      f = Formatter.new(true) # Ignore errors since they are expected
      spd = SparseDatas.new
      spb = Bytes.new(0)
      blk = template_v7_plus(hdr, ->f.format_string(Bytes, String), ->f.format_numeric(Bytes, Int64))
      if hdr.access_time.to_unix != 0
        f.format_numeric(blk.gnu.access_time, hdr.access_time.to_unix)
      end
      if hdr.change_time.to_unix != 0
        f.format_numeric(blk.gnu.change_time, hdr.change_time.to_unix)
      end
      # TO-DO
      # Add Sparse support

      blk.set_format(Format::GNU)
      write_raw_header(blk, hdr.size, hdr.flag)

      # Write the extended sparse map and setup the sparse writer if necessary.
      if spd.size > 0
        # Use @io since the sparse map is not accounted for in hdr.size
        @io.write(spb)
        @curr = SparseFileWriter.new(@curr, spd, 0)
      end
    end

    # template_v7_plus fills out the V7 fields of a block using values from hdr.
    # It also fills out fields (uname, gname, devmajor, devminor) that are
    # shared in the USTAR, PAX, and GNU formats using the provided formatters.
    #
    # The block returned is only valid until the next call to
    # templateV7Plus or write_raw_file.
    private def template_v7_plus(hdr : Header, fmt_str : StringFormatter, fmt_num : NumberFormatter)
      @block.reset

      # mod_time = hdr.mod_time

      v7 = @block.v7
      v7.flag[0] = hdr.flag
      fmt_str.call(v7.name, hdr.name)
      fmt_str.call(v7.link_name, hdr.link_name)
      fmt_num.call(v7.mode, hdr.mode)
      fmt_num.call(v7.uid, hdr.uid.to_i64)
      fmt_num.call(v7.gid, hdr.gid.to_i64)
      fmt_num.call(v7.size, hdr.size)
      fmt_num.call(v7.mod_time, hdr.mod_time.to_unix)

      ustar = @block.ustar
      fmt_str.call(ustar.user_name, hdr.uname)
      fmt_str.call(ustar.group_name, hdr.gname)
      fmt_num.call(ustar.dev_major, hdr.dev_major)
      fmt_num.call(ustar.dev_minor, hdr.dev_minor)

      @block
    end

    # write_raw_file writes a minimal file with the given name and flag type.
    # It uses format to encode the header format and will write data as the body.
    # It uses default values for all of the other fields (as BSD and GNU tar does).
    private def write_raw_file(name : String, data : String, flag : UInt8, format : Format) : Nil
      @block.reset

      # Best effort for the filename
      name = Crystar.to_ascii(name)
      name = name[...NAME_SIZE] if name.size > NAME_SIZE
      name = name.rstrip("/")

      f = Formatter.new
      v7 = @block.v7
      v7.flag[0] = flag.to_u8
      f.format_string(v7.name, name)
      f.format_octal(v7.mode, 0)
      f.format_octal(v7.uid, 0)
      f.format_octal(v7.gid, 0)
      f.format_octal(v7.size, data.bytesize.to_i64) # Must be < 8GiB
      f.format_octal(v7.mod_time, 0)
      @block.set_format(format)

      # Write the header and data
      write_raw_header(@block, data.bytesize.to_i64, flag.to_u8)
      @curr.puts data
    end

    # write_raw_header writes the value of blk, regardless of its value.
    # It sets up the Writer such that it can accept a file of the given size.
    # If the flag is a special header-only flag, then the size is treated as zero.
    private def write_raw_header(blk : Block, size : Int, flag : UInt8) : Nil
      flush
      @io.write(blk.to_bytes[..])
      size = 0 if Crystar.header_only_type?(flag.to_u8)

      @curr = RegFileWriter.new(@io, size.to_i64)
      @pad = Crystar.block_padding(size.to_i64)
    end

    private abstract class FileWriter < IO
      include FileState
      getter io : IO

      def initialize(@io)
      end

      abstract def write(b : Bytes) : Nil
      abstract def read_from(r : IO) : Int

      def read(b : Bytes)
        raise Error.new "Crystar Writer: Can't read"
      end

      forward_missing_to @io
    end

    private class RegFileWriter < FileWriter
      @nb = 0_i64 # Number of remaining bytes to write

      def initialize(@io, nb : Int)
        @nb = nb.to_i64
        super(@io)
      end

      def write(b : Bytes) : Nil
        overwrite = b.size > @nb
        b = b[..@nb] if overwrite
        if b.size > 0
          @io.write(b)
          @nb -= b.size
        end
        raise ErrWriteTooLong.new "tar: write too long" if overwrite
      end

      def read_from(r : IO) : Int
        IO.copy r, self
      end

      def logical_remaining : Int64
        @nb
      end

      def physical_remaining : Int64
        @nb
      end
    end

    private class SparseFileWriter < FileWriter
      def initialize(@fw : FileWriter, @sp : SparseDatas, @pos : Int64)
        super(@fw)
      end

      def write(b : Bytes) : Nil
        overwrite = b.size > logical_remaining
        b = b[...logical_remaining] if overwrite
        end_pos = @pos + b.size
        too_long = false
        while end_pos > @pos && !too_long
          nf = 0 # Bytes written in fragment
          data_start, data_end = @sp[0].offset, @sp[0].end_of_offset
          if @pos < data_start # In a hole fragment
            bf = b[...Math.min(b.size, data_start - @pos)]
            tmp = Bytes.new(bf.size)
            bf.copy_from(tmp.to_unsafe, bf.size)
            nf = bf.size
          else # In a data fragment
            bf = b[...Math.min(b.size, data_end - @pos)]
            begin
              @fw.write(bf)
              nf = bf.size
            rescue Error
              too_long = true
            end
          end
          b = b[nf..]
          @pos += nf
          if @pos >= data_end && @sp.size > 1
            @sp = @sp[1..] # Ensure last fragment always remains
          end
        end

        # Not possible; implies bug in validation logic
        raise Error.new("sparse file references non-existent data") if too_long
        if logical_remaining == 0 && physical_remaining > 0
          # Not possible; implies bug in validation logic
          raise Error.new("sparse file contains unreferenced data")
        end
        raise IO::EOFError.new if overwrite
      end

      def read_from(r : IO) : Int
        begin
          r.seek(0, IO::Seek::Current)
        rescue ex
          # not all IO can really seek
          return IO.copy r, self
        end
        read_last_byte = false
        too_long = false
        eof = false
        pos0 = @pos
        while logical_remaining > 0 && !read_last_byte && !too_long
          nf = 0 # Size of fragment
          data_start, data_end = @sp[0].offset, @sp[0].end_of_offset
          if @pos < data_start # In a hole fragment
            nf = data_start - @pos
            if physical_remaining == 0
              read_last_byte = true
              nf -= 1
            end
            r.seek(nf, IO::Seek::Current)
          else # In a data fragment
            nf = data_end - @pos
            begin
              nf = IO.copy r, @fw, nf
            rescue Error
              too_long = true
            rescue IO::EOFError
              eof = true
            end
          end
          @pos += nf
          if @pos >= data_end && @sp.size > 1
            @sp = @sp[1..] # Ensure last fragment always remains
          end
        end

        # If the last fragment is a hole, then seek to 1-byte before EOF, and
        # read a single byte to ensure the file is the right size.
        if read_last_byte && !too_long
          r.read_full(Bytes.new(1))
          @pos += 1
        end

        n = @pos - pos0
        raise Error.new "unexpected EOF" if eof
        # Not possible; implies bug in validation logic
        raise Error.new("sparse file references non-existent data") if too_long
        if logical_remaining == 0 && physical_remaining > 0
          # Not possible; implies bug in validation logic
          raise Error.new("sparse file contains unreferenced data")
        end
        ensure_eof r
        n
      end

      def logical_remaining : Int64
        @sp[@sp.size - 1].end_of_offset - @pos
      end

      def physical_remaining : Int64
        @fw.physical_remaining
      end

      private def ensure_eof(r : IO)
        begin
          n = r.read_full(Bytes.new(1))
        rescue IO::EOFError
        end
        raise Error.new "tar: write too long" if n > 0
      end
    end

    # Use long-link files if Name or Linkname exceeds the field size.
    LONG_NAME = "././@LongLink"
  end

  private alias StringFormatter = Proc(Bytes, String, Nil)
  private alias NumberFormatter = Proc(Bytes, Int64, Nil)
end
