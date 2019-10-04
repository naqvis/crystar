module Crystar
  extend self

  # Format represents the tar archive format.
  #
  # The original tar format was introduced in Unix V7.
  # Since then, there have been multiple competing formats attempting to
  # standardize or extend the V7 format to overcome its limitations.
  # The most common formats are the USTAR, PAX, and GNU formats,
  # each with their own advantages and limitations.
  #
  # The following table captures the capabilities of each format:
  #
  #	                  |  USTAR |       PAX |       GNU
  #	------------------+--------+-----------+----------
  #	Name              |   256B | unlimited | unlimited
  #	Linkname          |   100B | unlimited | unlimited
  #	Size              | uint33 | unlimited |    uint89
  #	Mode              | uint21 |    uint21 |    uint57
  #	Uid/Gid           | uint21 | unlimited |    uint57
  #	Uname/Gname       |    32B | unlimited |       32B
  #	ModTime           | uint33 | unlimited |     int89
  #	AccessTime        |    n/a | unlimited |     int89
  #	ChangeTime        |    n/a | unlimited |     int89
  #	Devmajor/Devminor | uint21 |    uint21 |    uint57
  #	------------------+--------+-----------+----------
  #	string encoding   |  ASCII |     UTF-8 |    binary
  #	sub-second times  |     no |       yes |        no
  #	sparse files      |     no |       yes |       yes
  #
  # The table's upper portion shows the Header fields, where each format reports
  # the maximum number of bytes allowed for each string field and
  # the integer type used to store each numeric field
  # (where timestamps are stored as the number of seconds since the Unix epoch).
  #
  # The table's lower portion shows specialized features of each format,
  # such as supported string encodings, support for sub-second timestamps,
  # or support for sparse files.
  #
  # The Writer currently provides no support for sparse files.

  # Various Crystar formats
  @[Flags]
  enum Format
    # The format of the original Unix V7 tar tool prior to standardization.
    V7
    # USTAR represents the USTAR header format defined in POSIX.1-1988.
    #
    # While this format is compatible with most tar readers,
    # the format has several limitations making it unsuitable for some usages.
    # Most notably, it cannot support sparse files, files larger than 8GiB,
    # filenames larger than 256 characters, and non-ASCII filenames.
    #
    # Reference:
    #	http:#pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_06
    USTAR
    # PAX represents the PAX header format defined in POSIX.1-2001.
    #
    # PAX extends USTAR by writing a special file with Typeflag TypeXHeader
    # preceding the original header. This file contains a set of key-value
    # records, which are used to overcome USTAR's shortcomings, in addition to
    # providing the ability to have sub-second resolution for timestamps.
    #
    # Some newer formats add their own extensions to PAX by defining their
    # own keys and assigning certain semantic meaning to the associated values.
    # For example, sparse file support in PAX is implemented using keys
    # defined by the GNU manual (e.g., "GNU.sparse.map").
    #
    # Reference:
    #	http:#pubs.opengroup.org/onlinepubs/009695399/utilities/pax.html
    PAX
    # GNU represents the GNU header format.
    #
    # The GNU header format is older than the USTAR and PAX standards and
    # is not compatible with them. The GNU format supports
    # arbitrary file sizes, filenames of arbitrary encoding and length,
    # sparse files, and other features.
    #
    # It is recommended that PAX be chosen over GNU unless the target
    # application can only parse GNU formatted archives.
    #
    # Reference:
    #	https:#www.gnu.org/softwarecrystar/manual/html_node/Standard.html
    GNU
    # Schily's tar format, which is incompatible with USTAR.
    # This does not cover STAR extensions to the PAX format; these fall under
    # the PAX format.
    STAR

    def has(f2 : self)
      includes? f2
    end

    def maybe(f2 : self)
      self.| f2
    end

    def may_only_be(f2)
      self.& f2
    end

    def must_not_be(f2)
      self.& ~f2
    end
  end

  # Magics used to identify various formats.
  MAGIC_GNU     = "ustar "
  VERSION_GNU   = " \x00"
  MAGIC_USTAR   = "ustar\x00"
  VERSION_USTAR = "00"
  TRAILER_STAR  = "tar\x00"

  BLOCK_SIZE  = 512 # Size of each block in a tar stream
  NAME_SIZE   = 100 # Max length of the name in USTAR format
  PREFIX_SIZE = 155 # Max length of the prefix field in USTAR format

  # block_padding computes the number of bytes needed to pad offset up to the
  # nearest block edge where 0 <= n < blockSize.
  def block_padding(offset : Int)
    -offset.to_i64 & (BLOCK_SIZE - 1)
  end

  private class Block
    @@zero_block : self = self.new
    forward_missing_to @block

    def initialize
      @block = Bytes.new(BLOCK_SIZE)
    end

    def initialize(@block : Bytes)
    end

    def to_bytes
      @block
    end

    def self.zero_block
      @@zero_block
    end

    def v7
      HeaderV7.new(@block)
    end

    def gnu
      HeaderGNU.new(@block)
    end

    def star
      HeaderSTAR.new(@block)
    end

    def ustar
      HeaderUSTAR.new(@block)
    end

    def sparse
      SparseArray.new(@block[...])
    end

    # get_format checks that the block is a valid tar header based on the checksum.
    # It then attempts to guess the specific format based on magic values.
    # If the checksum fails, then Format::None is returned.
    def get_format
      # Verify checksum
      p = Parser.new
      value = p.parse_octal(v7.chksum)
      chksum1, chksum2 = compute_checksum
      return Format::None if value != chksum1 && value != chksum2

      # Guess the magic values.
      magic = String.new(ustar.magic)
      version = String.new(ustar.version)
      trailer = String.new(star.trailer)
      case
      when magic == MAGIC_USTAR && trailer == TRAILER_STAR
        Format::STAR
      when magic == MAGIC_USTAR
        Format::USTAR | Format::PAX
      when magic == MAGIC_GNU && version == VERSION_GNU
        Format::GNU
      else
        Format::V7
      end
    end

    # set_format writes the magic values necessary for specified format
    # and then updates the checksum accordingly.

    def set_format(format : Format) : Nil
      # Set the magic values
      case
      when format.has(Format::V7)
        # Do nothing
      when format.has(Format::GNU)
        gnu.magic = MAGIC_GNU
        gnu.version = VERSION_GNU
      when format.has(Format::STAR)
        star.magic = MAGIC_USTAR
        star.version = VERSION_USTAR
        star.trailer = TRAILER_STAR
      when format.has(Format::USTAR | Format::PAX)
        ustar.magic = MAGIC_USTAR
        ustar.version = VERSION_USTAR
      else
        raise Error.new("invalid format")
      end

      # Update checksum
      # This field is special in that it is terminated by a NULL then space.

      f = Formatter.new
      field = v7.chksum
      chksum, _ = compute_checksum # Possible values are 256..128776
      f.format_octal(field[...7], chksum)
      field[7] = ' '.ord.to_u8
    end

    # compute_checksum computes the checksum for the header block.
    # POSIX specifies a sum of the unsigned byte values, but the Sun tar used
    # signed byte values.
    # We compute and return both.
    def compute_checksum
      u = s = 0_i64
      @block.each_with_index do |c, i|
        if 148 <= i && i < 156
          c = ' '.ord
        end
        u += c.to_i64
        s += c.to_i64
      end
      {u, s}
    end

    # reset clears the block with all zeros
    def reset
      p = @block.to_unsafe
      p.clear
      @block = p.to_slice(@block.size)
    end
  end

  private class HeaderV7
    def initialize(@h : Bytes)
    end

    def name
      @h[0..][...100]
    end

    def mode
      @h[100..][...8]
    end

    def uid
      @h[108..][...8]
    end

    def gid
      @h[116..][...8]
    end

    def size
      @h[124..][...12]
    end

    def mod_time
      @h[136..][...12]
    end

    def chksum
      @h[148..][...8]
    end

    def flag
      @h[156..][...1]
    end

    def link_name
      @h[157..][...100]
    end
  end

  private class HeaderGNU
    def initialize(@h : Bytes)
    end

    def v7
      HeaderV7.new(@h)
    end

    def magic
      @h[257..][...6]
    end

    def magic=(s : String)
      set(magic, s)
    end

    def version
      @h[263..][...2]
    end

    def version=(s : String)
      set(version, s)
    end

    def user_name
      @h[265..][...32]
    end

    def group_name
      @h[297..][...32]
    end

    def dev_major
      @h[329..][...8]
    end

    def dev_minor
      @h[337..][...8]
    end

    def access_time
      @h[345..][...12]
    end

    def change_time
      @h[357..][...12]
    end

    def sparse
      SparseArray.new @h[386..][...24*4 + 1]
    end

    def real_size
      @h[483..][...12]
    end

    private def set(h : Bytes, s : String)
      h.copy_from(s.to_slice.to_unsafe, h.size)
    end
  end

  private class HeaderSTAR
    def initialize(@h : Bytes)
    end

    def v7
      HeaderV7.new(@h)
    end

    def magic
      @h[257..][...6]
    end

    def magic=(s : String)
      set(magic, s)
    end

    def version
      @h[263..][...2]
    end

    def version=(s : String)
      set(version, s)
    end

    def user_name
      @h[265..][...32]
    end

    def group_name
      @h[297..][...32]
    end

    def dev_major
      @h[329..][...8]
    end

    def dev_minor
      @h[337..][...8]
    end

    def prefix
      @h[345..][...131]
    end

    def access_time
      @h[476..][...12]
    end

    def change_time
      @h[488..][...12]
    end

    def trailer
      @h[508..][...4]
    end

    def trailer=(s : String)
      set(trailer, s)
    end

    private def set(h : Bytes, s : String)
      h.copy_from(s.to_slice.to_unsafe, h.size)
    end
  end

  private class HeaderUSTAR
    def initialize(@h : Bytes)
    end

    def v7
      HeaderV7.new(@h)
    end

    def magic
      @h[257..][...6]
    end

    def magic=(s : String)
      set(magic, s)
    end

    def version
      @h[263..][...2]
    end

    def version=(s : String)
      set(version, s)
    end

    def user_name
      @h[265..][...32]
    end

    def group_name
      @h[297..][...32]
    end

    def dev_major
      @h[329..][...8]
    end

    def dev_minor
      @h[337..][...8]
    end

    def prefix
      @h[345..][...155]
    end

    private def set(h : Bytes, s : String)
      h.copy_from(s.to_slice.to_unsafe, h.size)
    end
  end

  private class SparseArray
    def initialize(@s : Bytes)
    end

    def entry(i : Int32)
      SparseElem.new(@s[i*24..])
    end

    def is_extended
      @s[24*max_entries..][...1]
    end

    def max_entries
      @s.size // 24
    end
  end

  private class SparseElem
    def initialize(@s : Bytes)
    end

    def offset
      @s[0..][...12]
    end

    def length
      @s[12..][...12]
    end
  end
end
