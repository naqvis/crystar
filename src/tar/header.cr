require "./format"
require "./helper"

module Crystar
  extend self

  # A Header represents a single header in a tar archive.
  # Some fields may not be populated.
  #
  # For forward compatibility, users that retrieve a Header from Reader#next_entry,
  # mutate it in some ways, and then pass it back to Writer#write_header
  # should do so by creating a new Header and copying the fields
  # that they are interested in preserving.

  class Header
    # Typeflag is the type of header entry.
    # The zero value is automatically promoted to either REG or DIR
    # depending on the presence of a trailing slash in Name.
    property flag : UInt8
    property name : String      # Name of file entry
    property link_name : String # Crystarget name of link (valid for LINK or SYMLINK)

    property size : Int64   # Logical file size in bytes
    property mode : Int64   # Permission and mode bits
    property uid : Int32    # User ID of owner
    property gid : Int32    # Group ID of owner
    property uname : String # User name of owner
    property gname : String # Group name of owner

    # If the Format is unspecified, then Writer#write_header rounds mod_time
    # to the nearest second and ignores the access_time and change_time fields.
    #
    # To use access_time or change_time, specify the Format as PAX or GNU.
    # To use sub-second resolution, specify the Format as PAX.
    property mod_time : Time    # Modification time
    property access_time : Time # Access time (requires either PAX or GNU support)
    property change_time : Time # Change Time (requires either PAX or GNU support)

    property dev_major : Int64 # Major device number (valid for CHAR or BLOCK)
    property dev_minor : Int64 # Minor device number (valid for CHAR or BLOCK)

    # xattr stores extended attributes as PAX records under the
    # "SCHILY.xattr." namespace.
    #
    # The following are semantically equivalent:
    #  h.Xattrs[key] = value
    #  h.PAXRecords["SCHILY.xattr."+key] = value
    #
    # When Writer#write_header is called, the contents of xattr will take
    # precedence over those in PAXRecords.
    #
    @[Deprecated("Use `pax_records` instead.")]
    property xattr : Hash(String, String)

    # pax_records is a map of PAX extended header records.
    #
    # User-defined records should have keys of the following form:
    #	VENDOR.keyword
    # Where VENDOR is some namespace in all uppercase, and keyword may
    # not contain the '=' character (e.g., "CRYSTAL.mod.version").
    # The key and value should be non-empty UTF-8 strings.
    #
    # When Writer#write_header is called, PAX records derived from the
    # other fields in Header take precedence over PAXRecords.
    property pax_records : Hash(String, String)

    # format specifies the format of the tar header.
    #
    # This is set by Reader#next_entry as a best-effort guess at the format.
    # Since the Reader liberally reads some non-compliant files,
    # it is possible for this to be Format::None.
    #
    # If the format is unspecified when Writer#write_header is called,
    # then it uses the first format (in the order of USTAR, PAX, GNU)
    # capable of encoding this Header (see Format).

    property format : Format

    getter io : IO

    def initialize(@flag = 0_u8, @name = "", @link_name = "", @size = 0_i64, @mode = 0_i64, @uid = 0, @gid = 0, @uname = "", @gname = "",
                   @mod_time = Crystar.unix_time(0, 0), @access_time = Crystar.unix_time(0, 0), @change_time = Crystar.unix_time(0, 0),
                   @dev_major = 0_i64, @dev_minor = 0_i64, @xattr = Hash(String, String).new,
                   @pax_records = Hash(String, String).new, @format = Format::None, @io = IO::Memory.new)
    end

    def_equals_and_hash @flag, @name, @link_name, @size, @mode, @gid, @uname, @gname, @mod_time, @access_time,
      @change_time, @dev_major, @dev_minor, @xattr, @pax_records, @format

    def size=(v : Int)
      @size = v.to_i64
    end

    def uid=(v : Int)
      @uid = v.to_i32
    end

    def gid=(v : Int)
      @gid = v.to_i32
    end

    def flag=(v : Int)
      @flag = v.to_u8
    end

    protected def io=(v : IO)
      @io = v
    end

    # allowed_formats determines which formats can be used.
    # The value returned is the logical OR of multiple possible formats.
    # If the value is Format::None, then the input Header cannot be encoded
    # and an error is returned explaining why.
    #
    # As a by-product of checking the fields, this function returns pax_hdrs, which
    # contain all fields that could not be directly encoded.
    # A value receiver ensures that this method does not mutate the source Header.
    protected def allowed_formats
      format = Format.flags(USTAR, PAX, GNU)
      pax_hdrs = {} of String => String

      why_no_ustar = why_no_pax = why_no_gnu = ""
      prefer_pax = false

      verify_string = ->(s : String, size : Int32, name : String, pax_key : String) {
        # NUL-terminator is optional for path and linkpath.
        # Technically, it is required for uname and gname,
        # but neither GNU nor BSD tar checks for it.
        too_long = s.bytesize > size
        allow_long_gnu = pax_key == PAX_PATH || pax_key == PAX_LINK_PATH
        if Crystar.has_nul(s) || (too_long && !allow_long_gnu)
          why_no_gnu = "GNU cannot encode #{name}=#{s}"
          format = format.must_not_be(Format::GNU)
        end
        if !s.ascii_only? || too_long
          can_split_ustar = pax_key == PAX_PATH
          _, _, ok = Crystar.split_ustar_path(s)
          if !can_split_ustar || !ok
            why_no_ustar = "USTAR cannot encode #{name}=#{s}"
            format = format.must_not_be(Format::USTAR)
          end
          if pax_key == PAX_NONE
            why_no_pax = "PAX cannot encode #{name}=#{s}"
            format = format.must_not_be(Format::PAX)
          else
            pax_hdrs[pax_key] = s
          end
        end
        if (v = pax_records[pax_key]?) && (v == s)
          pax_hdrs[pax_key] = v
        end
      }

      verify_numeric = ->(n : Int64, size : Int32, name : String, pax_key : String) {
        if !Crystar.fits_in_base256(size, n)
          why_no_gnu = "GNU cannot encode #{name}=#{n}"
          format = format.must_not_be(Format::GNU)
        end
        if !Crystar.fits_in_octal(size, n)
          why_no_ustar = "USTAR cannot encode #{name}=#{n}"
          format = format.must_not_be(Format::USTAR)
          if pax_key == PAX_NONE
            why_no_pax = "PAX cannot encode #{name}=#{n}"
            format = format.must_not_be(Format::PAX)
          else
            pax_hdrs[pax_key] = n.to_s
          end
        end
        if (v = pax_records[pax_key]?) && (v == n.to_s)
          pax_hdrs[pax_key] = v
        end
      }

      verify_time = ->(ts : Time, size : Int32, name : String, pax_key : String) {
        return if ts.second == 0 && ts.nanosecond == 0 # always okay
        if !Crystar.fits_in_base256(size, ts.to_unix)
          why_no_gnu = "GNU cannot encode #{name}=#{ts}"
          format = format.must_not_be(Format::GNU)
        end
        is_mtime = pax_key == PAX_MTIME
        fits_octal = Crystar.fits_in_octal(size, ts.to_unix)
        if (is_mtime && !fits_octal) || !is_mtime
          why_no_ustar = "USTAR cannot encode #{name}=#{ts}"
          format = format.must_not_be(Format::USTAR)
        end
        needs_nano = ts.nanosecond != 0
        if !is_mtime || !fits_octal || needs_nano
          prefer_pax = true # USTAR may truncate sub-second measurements
          if pax_key == PAX_NONE
            why_no_pax = "PAX cannot encode #{name}=#{ts}"
            format = format.must_not_be(Format::PAX)
          else
            pax_hdrs[pax_key] = Crystar.format_pax_time(ts)
          end
        end
        if (v = pax_records[pax_key]?) && (v == Crystar.format_pax_time(ts))
          pax_hdrs[pax_key] = v
        end
      }

      # check basic fields
      blk = Block.new
      v7 = blk.v7
      ustar = blk.ustar
      gnu = blk.gnu

      verify_string.call(@name, v7.name.size, "Name", PAX_PATH)
      verify_string.call(@link_name, v7.link_name.size, "Linkname", PAX_LINK_PATH)
      verify_string.call(@uname, ustar.user_name.size, "Uname", PAX_UNAME)
      verify_string.call(@gname, ustar.group_name.size, "Gname", PAX_GNAME)

      verify_numeric.call(@mode, v7.mode.size, "Mode", PAX_NONE)
      verify_numeric.call(@uid.to_i64, v7.uid.size, "Uid", PAX_UID)
      verify_numeric.call(@gid.to_i64, v7.gid.size, "Gid", PAX_GID)
      verify_numeric.call(@size, v7.size.size, "Size", PAX_SIZE)
      verify_numeric.call(@dev_major, ustar.dev_major.size, "Devmajor", PAX_NONE)
      verify_numeric.call(@dev_minor, ustar.dev_minor.size, "Devminor", PAX_NONE)

      verify_time.call(@mod_time, v7.mod_time.size, "ModTime", PAX_MTIME)
      verify_time.call(@access_time, gnu.access_time.size, "AccessTime", PAX_ATIME)
      verify_time.call(@change_time, gnu.change_time.size, "ChangeTime", PAX_CTIME)

      # Check for header-only types.
      why_only_pax = why_only_gnu = ""

      case flag
      when REG, CHAR, BLOCK, FIFO, GNU_SPARSE
        # Exclude LINK and SYM_LINK, since they may reference directories.
        raise Error.new("filename may not have trailing slash") if name.ends_with?('/')
      when XHEADER, GNU_LONGNAME, GNU_LONGLINK
        raise Error.new("cannot manually encode XHeader, GNULongName, or GNULongLink headers")
      when XGLOBAL_HEADER
        h2 = Header.new(name: name, flag: flag, xattr: xattr, pax_records: pax_records, format: @format)
        raise Error.new("only PAXRecords should be set for XGlobalHeader") if self == h2
        why_only_pax = "only PAX supports XGlobalHeader"
        format = format.may_only_be(Format::PAX)
      else
        #
      end

      raise Error.new("negative size on header-only type") if !Crystar.header_only_type?(flag) && size < 0

      # Check PAX records.
      if !xattr.empty?
        xattr.each do |k, v|
          pax_hdrs[PAX_SCHILY_XATTR + k] = v
        end
        why_only_pax = "only PAX supports Xattrs"
        format = format.may_only_be(Format::PAX)
      end

      if !pax_records.empty?
        pax_records.each do |k, v|
          case
          when pax_hdrs.has_key?(k)
            next
          when flag == XGLOBAL_HEADER
            pax_hdrs[k] = v # Copy all records
          when !BASIC_KEYS.fetch(k, true) && k.starts_with?(PAX_GNU_SPARSE)
            pax_hdrs[k] = v # Ignore local records that may conflict
          end
        end
        why_only_pax = "only PAX supports PAXRecords"
        format = format.may_only_be(Format::PAX)
      end

      pax_hdrs.each do |k, v|
        if !Crystar.valid_pax_record(k, v)
          raise Error.new("invalid PAX record: #{k} = #{v}")
        end
      end

      # Check desired format.
      if (want_format = @format) && (want_format != Format::None)
        if want_format.has(Format::PAX) && !prefer_pax
          want_format = want_format.maybe(Format::USTAR) # PAX implies USTAR allowed too
        end
        format = format.may_only_be(want_format)
      end

      if format.none?
        case @format
        when .ustar?
          raise Error.new(["Format specifies USTAR", why_no_ustar, why_only_pax, why_only_gnu].join(";"))
        when .pax?
          raise Error.new(["Format specified PAX", why_no_pax, why_only_gnu].join(";"))
        when .gnu?
          raise Error.new(["Format specifies GNU", why_no_gnu, why_only_pax].join(";"))
        else
          raise Error.new([why_no_ustar, why_no_pax, why_no_gnu, why_only_pax, why_no_gnu].join(";"))
        end
      end

      {format, pax_hdrs}
    end

    # file_info returns an File::Info for the header
    def file_info
      HeaderFileInfo.new(self)
    end
  end

  # SparseEntry represents a Length-sized fragment at Offset in the file
  private record SparseEntry, offset : Int64, length : Int64 do
    @@empty = SparseEntry.new 0, 0
    property :offset, :length

    def end_of_offset
      @offset + @length
    end

    def_equals_and_hash @offset, @length

    def self.empty
      @@empty
    end
  end

  # A sparse file can be represented as either a SparseDatas or a SparseHoles.
  # As long as the total size is known, they are equivalent and one can be
  # converted to the other form and back. The various tar formats with sparse
  # file support represent sparse files in the SparseDatas form. That is, they
  # specify the fragments in the file that has data, and treat everything else as
  # having zero bytes. As such, the encoding and decoding logic in this package
  # deals with SparseDatas.
  #
  # However, the external API uses SparseHoles instead of SparseDatas because the
  # zero value of SparseHoles logically represents a normal file (i.e., there are
  # no holes in it). On the other hand, the zero value of SparseDatas implies
  # that the file has no data in it, which is rather odd.
  #
  # As an example, if the underlying raw file contains the 10-byte data:
  #	compact_file = "abcdefgh"
  #
  # And the sparse map has the following entries:
  #	spd : SparseDatas = [SparseEntry.new(
  #		offset: 2,  length: 5),  # Data fragment for 2..6
  #		SparseEntry.new(offset: 18, length: 3)  # Data fragment for 18..20
  #	]
  #	sph : SparseHoles = [SparseEntry.new(
  #		offset: 0,  length: 2),  # Hole fragment for 0..1
  #		SparseEntry.new(offset: 7,  length: 11), # Hole fragment for 7..17
  #		SparseEntry.new(offset: 21, length: 4)  # Hole fragment for 21..24
  #	]
  #
  # Then the content of the resulting sparse file with a Header#size of 25 is:
  #	sparseFile = "\x00"*2 + "abcde" + "\x00"*11 + "fgh" + "\x00"*4

  alias SparseDatas = Array(SparseEntry)
  alias SparseHoles = Array(SparseEntry)

  # validate_sparse_entries reports whether sp is a valid sparse map.
  # It does not matter whether sp represents data fragments or hole fragments.

  def validate_sparse_entries(sp : Array(SparseEntry), size : Int64)
    # Validate all sparse entries. These are the same checks as performed by
    # the BSD tar utility.

    return false unless size >= 0

    pre = SparseEntry.new 0, 0
    sp.each do |cur|
      case
      when cur.offset < 0, cur.length < 0 then return false       # negative values are never okay
      when cur.offset > Int64::MAX - cur.length then return false # Integer overflow with large length
      when cur.end_of_offset > size then return false             # Region extends beyond the actual size
      when pre.end_of_offset > cur.offset then return false       # Regions cannot overlap and must be in order
      end
      pre = cur
    end
    true
  end

  # align_sparse_entries mutates src and returns dst where each fragment's
  # starting offset is aligned up to the nearest block edge, and each
  # ending offset is aligned down to the nearest block edge.
  #
  # Even though the Crystar Reader and the BSD tar utility can handle entries
  # with arbitrary offsets and lengths, the GNU tar utility can only handle
  # offsets and lengths that are multiples of blockSize.
  def align_sparse_entries(src : Array(SparseEntry), size : Int64)
    dst = src[...0]
    src.each do |s|
      p, e = s.offset, s.end_of_offset
      p += block_padding(+p)              # Round-up to nearest blocksize
      e -= block_padding(-e) if e != size # Round-down to nearest blocksize
      dst << SparseEntry.new(p, e - p) if p < e
    end
    dst
  end

  # invert_sparse_entries converts a sparse map from one form to the other.
  # If the input is SparseHoles, then it will output SparseDatas and vice-versa.
  # The input must have been already validated.
  #
  # This function mutates src and returns a normalized map where:
  #	* adjacent fragments are coalesced together
  #	* only the last fragment may be empty
  #	* the endOffset of the last fragment is the total size
  def invert_sparse_entries(src : Array(SparseEntry), size : Int64)
    dst = src[...0]
    pre = SparseEntry.new 0, 0
    src.each do |cur|
      next if cur.length == 0 # skip empty fragments
      pre.length = cur.offset - pre.offset
      dst << pre if pre.length > 0 # Only add non-empty fragments
      pre.offset = cur.end_of_offset
    end
    pre.length = size - pre.offset # Possibly the only empty fragment
    dst << pre
    dst
  end

  def header_only_type?(flag)
    case flag
    when LINK, SYMLINK, CHAR, BLOCK, DIR, FIFO then true
    else
      false
    end
  end

  # HeaderFileInfo extends File::Info
  private struct HeaderFileInfo < File::Info
    getter header : Header

    def initialize(@header)
    end

    def size : Int64
      header.size
    end

    def permissions : File::Permissions
      mode = header.mode.to_u32
      mode &= File::Permissions::All.value
      File::Permissions.new(mode)
    end

    def type : File::Type
      t = File::Type::File
      m = header.mode.to_u32 & ~File::Permissions::All.value
      case m
      when ISREG  then t |= File::Type::File
      when ISDIR  then t |= File::Type::Directory
      when ISFIFO then t |= File::Type::Pipe
      when ISLINK then t |= File::Type::Symlink
      when ISBLK  then t |= File::Type::BlockDevice
      when ISCHR  then t |= File::Type::CharacterDevice
      when ISSOCK then t |= File::Type::Socket
      end

      case header.flag.chr
      when SYMLINK    then t |= File::Type::Symlink
      when CHAR       then t |= File::Type::CharacterDevice
      when BLOCK      then t |= File::Type::BlockDevice
      when DIR        then t |= File::Type::Directory
      when FIFO       then t |= File::Type::Pipe
      when GNU_SPARSE then t |= File::Type::File
      end
      t
    end

    def flags : File::Flags
      mode = header.mode.to_u32
      f = File::Flags::None
      f |= File::Flags::SetUser if mode & ISUID != 0
      f |= File::Flags::SetGroup if mode & ISGID != 0
      f |= File::Flags::Sticky if mode & ISVTX != 0
      f
    end

    def modification_time : Time
      header.mod_time
    end

    def owner : UInt32
      header.uid
    end

    # Breaking change: added in Crystal v0.33.0
    def owner_id : String
      owner.to_s
    end

    def group : UInt32
      header.gid
    end

    # Breaking change: added in Crystal v0.33.0
    def group_id : String
      group.to_s
    end

    def same_file?(other : File::Info) : Bool
      size == other.size && permissions == other.permissions &&
        type == other.type && flags == other.flag && owner == other.owner &&
        group == other.group
    end
  end

  # file_info_header creates a partially-populated Header from *fi*.
  # If *fi* describes a symlink, this records link as the link target.
  # If *fi* describes a directory, a slash is appended to the name.
  def file_info_header(fi : File, link : String)
    info = File.info(fi.path, follow_symlinks: false)
    bname = File.basename fi.path
    h = Header.new(name: bname, mod_time: info.modification_time,
      mode: info.permissions.value.to_i64, uid: info.owner_id.to_i32, gid: info.group_id.to_i32)

    case info.type
    when .file?
      h.flag = REG.ord.to_u8
      h.size = fi.size
    when .directory?
      h.flag = DIR.ord.to_u8
      h.name += "/"
    when .symlink?
      h.flag = SYMLINK.ord.to_u8
      h.link_name = link
    when .character_device?
      h.flag = CHAR.ord.to_u8
    when .block_device?
      h.flag = BLOCK.ord.to_u8
    when .pipe?
      h.flag = FIFO.ord.to_u8
    when .socket?
      raise "Crystar Lib: sockets not supported"
    else
      raise "Crystar Lib: unknown file type #{info}"
    end

    case info.flags
    when .set_user?
      h.mode |= ISUID
    when .set_group?
      h.mode |= ISGID
    when .sticky?
      h.mode |= ISVTX
    else
      #
    end
    h
  end

  # FileState tracks the number of logical (includes sparse holes) and physical
  # (actual in tar archive) bytes remaining for the current file.
  #
  # Invariant: LogicalRemaining >= PhysicalRemaining

  private module FileState
    abstract def logical_remaining : Int64
    abstract def physical_remaining : Int64
  end
end
