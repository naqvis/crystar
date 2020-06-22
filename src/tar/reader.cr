require "math"
require "./header"

module Crystar
  # Reads tar file entries sequentially from an `IO`.
  #
  # ### Example
  #
  # ```
  # require "tar"
  #
  # File.open("./file.tar") do |file|
  #   Crystar::Reader.open(file) do |tar|
  #     tar.each_entry do |entry|
  #       p entry.name
  #       p entry.file?
  #       p entry.dir?
  #       p entry.io.gets_to_end
  #     end
  #   end
  # end
  # ```
  class Reader
    # Whether to close the enclosed `IO` when closing this reader.
    property? sync_close = false

    # Returns `true` if this reader is closed.
    getter? closed = false

    @pad = 0_i64 # Amount of padding (ignored) after current file entry
    @curr : FileReader
    @block : Block # Buffer to use as temporary local storage

    # Creates a new reader from the given *io*.
    def initialize(@io : IO, @sync_close = false)
      @block = Block.new
      @curr = RegFileReader.new(@io, 0_i64)
    end

    # Creates a new reader from the given *filename*.
    def self.new(filename : String)
      new(::File.new(filename), sync_close: true)
    end

    # Creates a new reader from the given *io*, yields it to the given block,
    # and closes it at the end.
    def self.open(io : IO, sync_close = false)
      reader = new(io, sync_close: sync_close)
      yield reader ensure reader.close
    end

    # Creates a new reader from the given *filename*, yields it to the given block,
    # and closes it at the end.
    def self.open(filename : String)
      reader = new(filename)
      yield reader ensure reader.close
    end

    # Yields each entry in the tar to the given block.
    def each_entry
      while entry = next_entry
        yield entry
      end
    end

    # Closes Crystar reader
    def close
      return if @closed
      @closed = true
      @io.close if @sync_close
    end

    # next_entry advances to the next entry in the tar archive.
    # The Header#size determines how many bytes can be read for the next file.
    # Any remaining data in the current file is automatically discarded.
    #
    # EOF is returned at the end of the input.
    def next_entry : Header?
      pax_hdrs = {} of String => String
      gnu_long_name = gnu_long_link = ""

      # Externally, Next iterates through the tar archive as if it is a series of
      # files. Internally, the tar format often uses fake "files" to add meta
      # data that describes the next file. These meta data "files" should not
      # normally be visible to the outside. As such, this loop iterates through
      # one or more "header files" until it finds a "normal file".
      format = Format.flags(USTAR, PAX, GNU)
      loop do
        # discard the remainder of the file and any padding
        @io.skip(@curr.physical_remaining)
        @io.read_fully?(@block[...@pad])
        @pad = 0

        hdr, raw_hdr, err = read_header

        return nil if err == 0 || hdr.nil?
        return nil if raw_hdr.nil?

        handle_regular_file(hdr)

        format = format.may_only_be(hdr.format)

        # Check for PAX/GNU special headers and files
        case hdr.flag.chr
        when XHEADER, XGLOBAL_HEADER
          format = format.may_only_be(Format::PAX)

          pax_hdrs = Crystar.parse_pax(@curr)
          if hdr.flag.chr == XGLOBAL_HEADER
            Crystar.merge_pax(hdr, pax_hdrs)
            return Header.new(name: hdr.name, flag: hdr.flag, xattr: hdr.xattr,
              pax_records: hdr.pax_records, format: format, io: @curr)
          end
          next # This is a meta header affecting the next header
        when GNU_LONGNAME, GNU_LONGLINK
          format = format.may_only_be(Format::GNU)
          realname = @curr.gets_to_end.to_slice
          p = Parser.new
          case hdr.flag.chr
          when GNU_LONGNAME
            gnu_long_name = p.parse_string(realname)
          when GNU_LONGLINK
            gnu_long_link = p.parse_string(realname)
          else
            #
          end
          next # This is meta header affecting the next header
        else
          # The old GNU sparse format is handled here since it is technically
          # just a regular file with additional attributes
          Crystar.merge_pax(hdr, pax_hdrs)
          hdr.name = gnu_long_name if !gnu_long_name.blank?
          hdr.link_name = gnu_long_link if !gnu_long_link.blank?

          if hdr.flag == REG
            if hdr.name.ends_with?("/")
              hdr.flag = DIR.ord
            else
              hdr.flag = REG.ord
            end
          end

          # The extended headers may have updated the size.
          # Thus, setup the RegFileReader again after merging
          handle_regular_file(hdr)

          # Sparse formats rely on being able to read from the logical data
          # section; there must be a preceding call to handle_regular_file.
          handle_sparse_file(hdr, raw_hdr)

          # Set the final guess at the format
          if format.ustar? && format.pax?
            format = format.may_only_be(Format::USTAR)
          end
          hdr.format = format
          hdr.io = @curr
          return hdr # This is a file, so stop
        end
      end
    end

    # read_header reads the next block header and assumes that the underlying reader
    # is already aligned to a block boundary. It returns the raw block of the
    # header in case further processing is required.
    #
    # The err will be set to io.EOF only when one of the following occurs:
    #	* Exactly 0 bytes are read and EOF is hit.
    #	* Exactly 1 block of zeros is read and EOF is hit.
    #	* At least 2 blocks of zeros are read.
    private def read_header
      # Two blocks of zero bytes marks the end of the archive.
      begin
        @io.read_fully(@block.to_bytes)
      rescue IO::EOFError
        return {nil, nil, 0} # EOF is okay here; exactly 0 bytes read
      end

      if @block == Block.zero_block
        @io.read_fully(@block.to_bytes)
        return {nil, nil, 0} if @block == Block.zero_block # normal EOF; exactly 2 block of zeros read
        raise Error.new("invalid tar header")              # Zero block and then non-zero block
      end

      # Verify the header matches a known format.
      format = @block.get_format
      # raise Error.new("invalid tar header") if format.none?
      return {nil, nil, 0} if format.none?

      p = Parser.new
      hdr = Header.new

      # Unpack the V7 header
      v7 = @block.v7
      hdr.flag = v7.flag[0]
      hdr.name = p.parse_string(v7.name)
      hdr.link_name = p.parse_string(v7.link_name)
      hdr.size = p.parse_numeric(v7.size)
      hdr.mode = p.parse_numeric(v7.mode)
      hdr.uid = p.parse_numeric(v7.uid)
      hdr.gid = p.parse_numeric(v7.gid)
      hdr.mod_time = Crystar.unix_time(p.parse_numeric(v7.mod_time), 0)

      # Unpack format specific fields.
      if format > Format::V7
        ustar = @block.ustar
        hdr.uname = p.parse_string(ustar.user_name)
        hdr.gname = p.parse_string(ustar.group_name)
        hdr.dev_major = p.parse_numeric(ustar.dev_major)
        hdr.dev_minor = p.parse_numeric(ustar.dev_minor)

        prefix = ""
        case format
        when .ustar?, .pax?
          hdr.format = format
          ustar = @block.ustar
          prefix = p.parse_string(ustar.prefix)
          # For Format detection, check if block is properly formatted since
          # the parser is more liberal than what USTAR actually permits.
          not_ascii = @block.any?(0x80)
          hdr.format = Format::None if not_ascii # Non-ASCII characters in block

          nul = ->(b : Bytes) { b[b.size - 1] == 0 }
          if !(nul.call(v7.size) && nul.call(v7.mode) && nul.call(v7.uid) && nul.call(v7.gid) &&
             nul.call(v7.mod_time) && nul.call(ustar.dev_major) && nul.call(ustar.dev_minor))
            hdr.format = Format::None # Numeric fields must end in NUL
          end
        when .star?
          star = @block.star
          prefix = p.parse_string(star.prefix)
          hdr.access_time = Crystar.unix_time(p.parse_numeric(star.access_time), 0)
          hdr.change_time = Crystar.unix_time(p.parse_numeric(star.change_time), 0)
        when .gnu?
          hdr.format = format
          p2 = Parser.new
          gnu = @block.gnu
          begin
            if (b = gnu.access_time) && (b[0] != 0)
              hdr.access_time = Crystar.unix_time(p2.parse_numeric(b), 0)
            end
            if (b = gnu.change_time) && (b[0] != 0)
              hdr.change_time = Crystar.unix_time(p2.parse_numeric(b), 0)
            end
          rescue ex
            ustar = @block.ustar
            if (s = p.parse_string(ustar.prefix)) && s.ascii_only?
              prefix = s
            end
            hdr.format = Format::None # Bugyy file is not GNU
          end
        else
          # We don't need to do anything
        end
        hdr.name = "#{prefix}/#{hdr.name}" if prefix.size > 0
      end
      {hdr, @block, 1}
    end

    # read_old_gnu_sparse_map reads the sparse map from the old GNU sparse format.
    # The sparse map is stored in the tar header if it's small enough.
    # If it's larger than four entries, then one or more extension headers are used
    # to store the rest of the sparse map.
    #
    # The Header#size does not reflect the size of any extended headers used.
    # Thus, this method will read from the raw IO to fetch extra headers.
    # This method mutates blk in the process.
    private def read_old_gnu_sparse_map(hdr : Header, blk : Block)
      # Make sure that the input format is GNU.
      # Unfortunately, the STAR format also has a sparse header format that uses
      # the same type flag but has a completely different layout.
      raise "invalid header" if !blk.get_format.gnu?
      hdr.format = hdr.format.may_only_be(Format::GNU)
      p = Parser.new
      hdr.size = p.parse_numeric(blk.gnu.real_size)
      s = blk.gnu.sparse
      spd = SparseDatas.new(s.max_entries)
      loop do
        0.upto(s.max_entries - 1) do |i|
          # This termination condition is identical to GNU and BSD tar
          break if s.entry(i).offset[0] == 0x00 # Dont return, need to process extended headers (even if empty)

          offset = p.parse_numeric(s.entry(i).offset)
          length = p.parse_numeric(s.entry(i).length)
          spd << SparseEntry.new(offset: offset, length: length)
        end

        if s.is_extended[0] > 0
          # There are more entries. Read an extension header and parse its entries.
          @io.read_fully(blk.to_bytes)
          s = blk.sparse
          next
        end
        return spd # Done
      end
    end

    # handle_regular_file sets up the current file reader and padding such that it
    # can only read the following logical data section. It will properly handle
    # special headers that contain no data section
    private def handle_regular_file(hdr : Header)
      nb = hdr.size
      nb = 0 if Crystar.header_only_type?(hdr.flag)
      raise "invalid header" if nb < 0
      @pad = Crystar.block_padding(nb)
      @curr = RegFileReader.new(@io, nb)
    end

    # handle_sparse_file checks if the current file is a sparse format of any type
    # and sets the curr reader appropriately.
    private def handle_sparse_file(hdr : Header, raw_hdr : Block)
      spd = if hdr.flag.chr == GNU_SPARSE
              read_old_gnu_sparse_map(hdr, raw_hdr)
            else
              read_gnu_sparse_pax_headers(hdr)
            end
      if !spd.nil?
        if Crystar.header_only_type?(hdr.flag) || !Crystar.validate_sparse_entries(spd, hdr.size)
          raise "invalid header"
        end
        sph = Crystar.invert_sparse_entries(spd, hdr.size)
        @curr = SparseFileReader.new(@curr, sph, 0)
      end
    end

    # read_gnu_sparse_pax_headers checks the PAX headers for GNU sparse headers.
    # If they are found, then this function reads the sparse map and returns it.
    # This assumes that 0.0 headers have already been converted to 0.1 headers
    # by the PAX header parsing logic.
    private def read_gnu_sparse_pax_headers(hdr : Header)
      # identify the version of GNU headers
      is1x0 = false
      major, minor = hdr.pax_records.fetch(PAX_GNU_SPARSE_MAJOR, ""), hdr.pax_records.fetch(PAX_GNU_SPARSE_MINOR, "")
      if major == "0" && (minor == "0" || minor == "1")
        is1x0 = false
      elsif major == "1" && minor == "0"
        is1x0 = true
      elsif !major.blank? || !minor.blank?
        return nil # Unknown GNU sparse PAX version
      elsif hdr.pax_records.fetch(PAX_GNU_SPARSE_MAP, "") != ""
        is1x0 = false # 0.0 and 0.1 did not have explicit version records, so guess
      else
        return nil
      end
      hdr.format = hdr.format.may_only_be(Format::PAX)

      # Update hdr from GNU sparse PAX headers
      if (name = hdr.pax_records[PAX_GNU_SPARSE_NAME]?) && !name.blank?
        hdr.name = name
      end
      size = hdr.pax_records.fetch(PAX_GNU_SPARSE_SIZE, "")
      if size.blank?
        size = hdr.pax_records.fetch(PAX_GNU_SPARSE_REALSIZE, "")
      end
      if !size.blank?
        hdr.size = size.to_i64
      end

      # Read the sparse map according to the appropriate format.
      return Crystar.read_gnu_sparse_map1x0(@curr) if is1x0
      Crystar.read_gnu_sparse_map0x1(hdr.pax_records)
    end

    abstract class FileReader < IO
      include FileState
      getter io : IO

      def initialize(@io)
      end

      abstract def read(b : Bytes) : Int
      abstract def write_to(w : IO) : Int

      def write(b : Bytes) : Nil
        raise Error.new "Crystar Reader: Can't write"
      end

      forward_missing_to @io
    end

    private class RegFileReader < FileReader
      @nb = 0_i64 # Number of remaining bytes to read

      def initialize(@io, nb : Int)
        @nb = nb.to_i64
        super(@io)
      end

      def read(b : Bytes) : Int32
        b = b[...@nb] if b.size > @nb
        n = 0
        eof = false
        if b.size > 0
          begin
            n = @io.read(b)
          rescue IO::EOFError
            eof = true
          end
          @nb -= n
        end
        raise Error.new("Unexpected EOF") if eof && @nb > 0
        n
      end

      def write_to(w : IO) : Int
        IO.copy self, w
      end

      def logical_remaining : Int64
        @nb
      end

      def physical_remaining : Int64
        @nb
      end
    end

    private class SparseFileReader < FileReader
      def initialize(@fr : FileReader, @sp : SparseHoles, @pos : Int64)
        super(@fr)
      end

      def read(b : Bytes) : Int32
        finished = b.size >= logical_remaining
        b = b[...logical_remaining] if finished

        b0 = b
        end_pos = @pos + b.size
        eof = false
        while end_pos > @pos && !eof
          nf = 0 # Bytes read in fragment
          hole_start, hole_end = @sp[0].offset, @sp[0].end_of_offset
          if @pos < hole_start # In a data fragment
            bf = b[...Math.min(b.size, hole_start - @pos)]
            begin
              nf = @fr.read_fully(bf)
            rescue IO::EOFError
              eof = true
            end
          else # In a hole fragment
            bf = b[...Math.min(b.size, hole_end - @pos)]
            tmp = Bytes.new(bf.size)
            bf.copy_from(tmp.to_unsafe, bf.size)
            nf = bf.size
          end
          b = b[nf..]
          @pos += nf
          if @pos >= hole_end && @sp.size > 1
            @sp = @sp[1..] # Ensure last fragment always remains
          end
        end

        n = b0.size - b.size
        raise Error.new("sparse file references non-existent data") if eof
        if logical_remaining == 0 && physical_remaining > 0
          raise Error.new("sparse file contains unreferenced data")
        end
        # raise IO::EOFError.new if finished
        n
      end

      def write_to(w : IO) : Int
        begin
          w.seek(0, IO::Seek::Current)
        rescue ex
          # not all IO can really seek
          return IO.copy self, w
        end
        write_last_byte = false
        eof = false
        pos0 = @pos
        while logical_remaining > 0 && !write_last_byte # && !eof
          nf = 0                                        # size of fragment
          hole_start, hole_end = @sp[0].offset, @sp[0].end_of_offset
          if @pos < hole_start # In a data fragment
            nf = hole_start - @pos
            begin
              tmp = IO.copy @fr, w, nf
              eof = tmp != nf
              nf = tmp
            rescue IO::EOFError
              eof = true
            end
          else
            nf = hole_end - @pos
            if physical_remaining == 0
              write_last_byte = true
              nf -= 1
            end
            w.seek(nf, IO::Seek::Current)
          end
          @pos += nf
          if @pos >= hole_end && @sp.size > 1
            @sp = @sp[1..] # Ensure last fragment always remains
          end
        end

        # If the last fragment is a hole, then seek to 1-byte before EOF, and
        # write a single byte to ensure the file is the right size.
        if write_last_byte
          w.write(Bytes.new(1))
          @pos += 1
        end

        n = @pos - pos0
        # Less data in dense file than sparse file
        raise Error.new("sparse file references non-existent data") if eof
        if logical_remaining == 0 && physical_remaining > 0
          # More data in dense file file than sparse file
          raise Error.new("sparse file contains unreferenced data")
        end
        n
      end

      def logical_remaining : Int64
        @sp[@sp.size - 1].end_of_offset - @pos
      end

      def physical_remaining : Int64
        @fr.physical_remaining
      end
    end
  end

  # merg_pax merges pax_hdrs into hdr for all relevant fields of Header.
  def merge_pax(hdr : Header, pax_hdrs : Hash(String, String))
    pax_hdrs.each do |k, v|
      next if v.blank? # Keep the original USTAR value
      case k
      when PAX_PATH
        hdr.name = v
      when PAX_LINK_PATH
        hdr.link_name = v
      when PAX_UNAME
        hdr.uname = v
      when PAX_GNAME
        hdr.gname = v
      when PAX_UID
        hdr.uid = v.to_i64
      when PAX_GID
        hdr.gid = v.to_i64
      when PAX_ATIME
        hdr.access_time = parse_pax_time(v)
      when PAX_MTIME
        hdr.mod_time = parse_pax_time(v)
      when PAX_CTIME
        hdr.change_time = parse_pax_time(v)
      when PAX_SIZE
        hdr.size = v.to_i64
      else
        if k.starts_with?(PAX_SCHILY_XATTR)
          hdr.xattr[k[PAX_SCHILY_XATTR.size..]] = v
        end
      end
    end
    hdr.pax_records = pax_hdrs
  end

  # parse_pax parses PAX headers
  # If an extended header (type 'x') is invalid, exception is raised
  def self.parse_pax(r : IO) : Hash(String, String)
    sbuf = r.gets_to_end

    # For GNU PAX sparse format 0.0 support.
    # This function transforms the sparse format 0.0 headers into format 0.1
    # headers since 0.0 headers were not PAX compliant
    sparse_map = [] of String
    pax_hdrs = {} of String => String

    while sbuf.size > 0
      key, val, residual = parse_pax_record(sbuf)
      sbuf = residual

      case key
      when PAX_GNU_SPARSE_OFFSET, PAX_GNU_SPARSE_NUMBYTES
        # Validate sparse header order and value
        if (sparse_map.size % 2 == 0 && key != PAX_GNU_SPARSE_OFFSET) ||
           (sparse_map.size % 2 == 1 && key != PAX_GNU_SPARSE_NUMBYTES) ||
           val.includes?(",")
          raise "invalid header"
        end
        sparse_map << val
      else
        pax_hdrs[key] = val
      end
    end

    pax_hdrs[PAX_GNU_SPARSE_MAP] = sparse_map.join(",") if sparse_map.size > 0
    pax_hdrs
  end

  # read_gnu_sparse_map1x0 reads the sparse map as stored in GNU's PAX sparse format
  # version 1.0. The format of the sparse map consists of a series of
  # newline-terminated numeric fields. The first field is the number of entries
  # and is always present. Following this are the entries, consisting of two
  # fields (offset, length). This function must stop reading at the end
  # boundary of the block containing the last newline.
  #
  # Note that the GNU manual says that numeric values should be encoded in octal
  # format. However, the GNU tar utility itself outputs these values in decimal.
  # As such, this library treats values as being encoded in decimal.
  def self.read_gnu_sparse_map1x0(r : IO)
    cnt_new_line = 0
    buf = IO::Memory.new
    blk = Block.new
    read_pos = 0 # Use to store reading offset

    # feed_tokens copies data in blocks from r into buf until there are
    # at least cnt newlines in buf. It will not read more than needed.
    feed_tokens = ->(n : Int32) {
      while cnt_new_line < n
        r.read(blk.to_bytes[..])
        buf.seek(0, IO::Seek::End) # get to end, to append data
        buf.write(blk.to_bytes)
        blk.to_bytes.each do |b|
          cnt_new_line += 1 if b == '\n'.ord
        end
      end
    }

    # next_token gets the next token delimited by a newline. This assumes that
    # at least one newline exists in the buffer.
    next_token = ->{
      buf.pos = read_pos # get back to previous reading position
      cnt_new_line -= 1
      tok = buf.gets(chomp: true)
      read_pos = buf.pos # update reading position, so that we can get back to it
      tok.nil? ? "0" : tok
    }

    # Parse for the number of entries.
    # Use integer overflow resistant math to check this.
    feed_tokens.call(1)
    num_entries = next_token.call.to_i { 0 }

    raise Error.new("Invalid header") if num_entries < 0 || (2*num_entries) < num_entries

    # Parse for all member entries.
    # num_entries is trusted after this since a potential attacker must have
    # committed resources proportional to what this library used.
    feed_tokens.call(2 * num_entries)

    spd = SparseDatas.new(num_entries)
    0.upto(num_entries - 1) do |_|
      offset = next_token.call.to_i64
      length = next_token.call.to_i64
      spd << SparseEntry.new offset, length
    end
    spd
  end

  # read_gnu_sparse_map0x1 reads the sparse map as stored in GNU's PAX sparse format
  # version 0.1. The sparse map is stored in the PAX headers.
  def self.read_gnu_sparse_map0x1(pax_hdrs : Hash(String, String))
    # Get number of entries.
    # Use integer overflow resistant math to check this.
    num_entries_str = pax_hdrs[PAX_GNU_SPARSE_NUMBLOCKS]
    begin
      num_entries = num_entries_str.to_i
    rescue ex
      num_entries = 0
    end
    raise Error.new("Invalid header") if num_entries < 0 || (2*num_entries) < num_entries

    # There should be two numbers in sparse_map for each entry.
    sparse_map = pax_hdrs[PAX_GNU_SPARSE_MAP].split(",")
    if sparse_map.size == 1 && sparse_map[0].blank?
      sparse_map = sparse_map[..0]
    end
    raise "invalid header" if sparse_map.size != 2*num_entries

    # Loop through the entries in the sparse map.
    # num_entries is trusted now
    spd = SparseDatas.new(num_entries)
    while sparse_map.size >= 2
      offset = sparse_map[0].to_i64
      length = sparse_map[1].to_i64
      spd << SparseEntry.new offset, length
      sparse_map = sparse_map[2..]
    end
    spd
  end

  # is like read_fully except it returns
  # EOF when it is hit before b.size bytes are read
  def self.try_read_full(r : IO, b : Bytes)
    n = 0
    eof = false
    while b.size > n && !eof
      nn = r.read(b[n..])
      eof = nn == 0
      n += nn
    end
    n
  end
end
