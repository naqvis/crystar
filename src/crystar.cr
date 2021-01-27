require "./tar/*"

# `Crystar` module contains readers and writers for tar archive.
# Tape archives (tar) are a file format for storing a sequence of files that can be read and written in a streaming manner.
# This module aims to cover most variations of the format, including those produced by GNU and BSD tar tools.
#
# ### Example
# ```
# files = [
#   {"readme.txt", "This archive contains some text files."},
#   {"minerals.txt", "Mineral names:\nalunite\nchromium\nvlasovite"},
#   {"todo.txt", "Get crystal mining license."},
# ]
# buf = IO::Memory.new
# Crystar::Writer.open(buf) do |tw|
#   files.each do |f|
#     hdr = Header.new(
#       name: f[0],
#       mode: 0o600_i64,
#       size: f[1].size.to_i64
#     )
#     tw.write_header(hdr)
#     tw.write(f[1].to_slice)
#   end
# end
#
# # Open and iterate through the files in the archive
# buf.pos = 0
# Crystar::Reader.open(buf) do |tar|
#   tar.each_entry do |entry|
#     p "Contents of #{entry.name}"
#     IO.copy entry.io, STDOUT
#     p "\n"
#   end
# end
# ```
module Crystar
  VERSION = "0.1.9"

  # Common Crystar exceptions
  class Error < Exception
  end

  class ErrWriteTooLong < Error
  end

  # Type flags for Header#flag
  REG  = '0' # '0' indicated a regular file
  @[Deprecated("Use `REG` instead")]
  REGA = '\0'

  # '1' to '6' are header-only flags and may not have a data body.
  LINK    = '1' # Hard link
  SYMLINK = '2' # Symbolic link
  CHAR    = '3' # Character device node
  BLOCK   = '4' # Block device node
  DIR     = '5' # Directory
  FIFO    = '6' # FIFO node

  CONT           = '7' # reserved
  XHEADER        = 'x' # Used by PAX format to store key-value records that are only relevant to the next file.
  XGLOBAL_HEADER = 'g' # Used by PAX format to key-value records that are relevant to all subsequent files.
  GNU_SPARSE     = 'S' # indicated a sparse file in the GNU format

  # 'L' and 'K' are used by teh GNU format for a meta file
  # used to store the path or link name for the next file.
  GNU_LONGNAME = 'L'
  GNU_LONGLINK = 'K'

  # Keywords for PAX extended header records
  PAX_NONE      = "" # indicates that no PAX key is suitable
  PAX_PATH      = "path"
  PAX_LINK_PATH = "linkpath"
  PAX_SIZE      = "size"
  PAX_UID       = "uid"
  PAX_GID       = "gid"
  PAX_UNAME     = "uname"
  PAX_GNAME     = "gname"
  PAX_MTIME     = "mtime"
  PAX_ATIME     = "atime"
  PAX_CTIME     = "ctime"   # Removed from later revision of PAX spec, but was valid
  PAX_CHARSET   = "charset" # Currently unused
  PAX_COMMENT   = "comment" # Currently unused

  PAX_SCHILY_XATTR = "SCHILY.xattr."

  # Keywords for GNU sparse files in a PAX extended header.
  PAX_GNU_SPARSE           = "GNU.sparse."
  PAX_GNU_SPARSE_NUMBLOCKS = "GNU.sparse.numblocks"
  PAX_GNU_SPARSE_OFFSET    = "GNU.sparse.offset"
  PAX_GNU_SPARSE_NUMBYTES  = "GNU.sparse.numbytes"
  PAX_GNU_SPARSE_MAP       = "GNU.sparse.map"
  PAX_GNU_SPARSE_NAME      = "GNU.sparse.name"
  PAX_GNU_SPARSE_MAJOR     = "GNU.sparse.major"
  PAX_GNU_SPARSE_MINOR     = "GNU.sparse.minor"
  PAX_GNU_SPARSE_SIZE      = "GNU.sparse.size"
  PAX_GNU_SPARSE_REALSIZE  = "GNU.sparse.realsize"

  #  set of the PAX keys for which we have built-in support.
  # This does not contain "charset" or "comment", which are both PAX-specific,
  # so adding them as first-class features of Header is unlikely.
  # Users can use the PAXRecords field to set it themselves.

  BASIC_KEYS = {
    PAX_PATH => true, PAX_LINK_PATH => true, PAX_SIZE => true,
    PAX_UID => true, PAX_GID => true, PAX_UNAME => true,
    PAX_GNAME => true, PAX_MTIME => true, PAX_ATIME => true,
    PAX_CTIME => true,
  }

  # Mode constants from USTAR spec:
  # See http://pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html#tag_20_92_13_06
  ISUID = 0o4000 # Set uid
  ISGID = 0o2000 # Set gid
  ISVTX = 0o1000 # Save text (sticky bit)
  # Common Unix mode constants; these are not defined in any common tar standard.
  # Header.FileInfo understands these, but FileInfoHeader will never produce these.
  ISDIR  =  0o40000 # Directory
  ISFIFO =  0o10000 # FIFO
  ISREG  = 0o100000 # Regular file
  ISLINK = 0o120000 # Symbolic link
  ISBLK  =  0o60000 # Block special file
  ISCHR  =  0o20000 # Character special file
  ISSOCK = 0o140000 # Socket
end
