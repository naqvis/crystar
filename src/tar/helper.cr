require "time"

module Crystar
  extend self

  MAX_NANO_SECOND_DIGITS = 9
  PADDING                = 3 # Extra padding for ' ', '=', and '\n'

  # checks whether NUL character exists within s
  def has_nul(s : String)
    s.byte_index(0) ? true : false
  end

  # to_ascii converts the input to an ASCII C-style string.
  # This a best effort conversion, so invalid characters are dropped.
  def to_ascii(s : String)
    return s if s.ascii_only?
    b = Bytes.new(s.size)
    index = 0
    s.bytes.each do |c|
      if c < 0x80 && c != 0x00
        b[index] = c
        index += 1
      end
    end
    String.new(b[...index])
  end

  # split_ustar_path splits a path according to USTAR prefix and suffix rules.
  # If the path is not splittable, then it will return ("", "", false).

  def split_ustar_path(name : String)
    length = name.size
    return "", "", false if length <= NAME_SIZE || !name.ascii_only?
    length = PREFIX_SIZE + 1 if length > PREFIX_SIZE + 1
    length -= 1 if name.char_at(name.size - 1) == '/'

    i = name[..length].rindex("/")
    if !i
      return "", "", false
    else
      nlen = name.size - i - 1 # nlen is length of suffix
      plen = i                 # plen is length of prefix
      if i <= 0 || nlen > NAME_SIZE || nlen == 0 || plen > PREFIX_SIZE
        return "", "", false
      else
        return name[..i], name[i + 1..], true
      end
    end
  end

  # fits_in_base256 reports whether x can be encoded into n bytes using base-256
  # encoding. Unlike octal encoding, base-256 encoding does not require that the
  # string ends with a NUL character. Thus, all n bytes are available for output.
  #
  # If operating in binary mode, this assumes strict GNU binary mode; which means
  # that the first byte can only be either 0x80 or 0xff. Thus, the first byte is
  # equivalent to the sign bit in two's complement form.

  def fits_in_base256(n : Int32, x : Int64)
    bin_bits = (n - 1).to_u32 * 8
    n >= 9 || (x >= -1_i64 << bin_bits && x < 1_i64 << bin_bits)
  end

  # fits_in_octal reports whether the integer x fits in a field n-bytes long
  # using octal encoding with the appropriate NUL terminator.
  def fits_in_octal(n : Int32, x : Int64)
    oct_bits = (n - 1).to_u32 * 3
    x >= 0 && (n >= 22 || x < 1_i64 << oct_bits)
  end

  # parse_pax_time takes a string of the form %d.%d as described in the PAX
  # specification. Note that this implementation allows for negative timestamps,
  # which is allowed for by the PAX specification, but not always portable.
  def parse_pax_time(s : String)
    return unix_time(0, 0) unless s.size > 0
    ss, sn = s, ""
    if (pos = s.index('.')) && (pos >= 0)
      ss, sn = s[...pos], s[pos + 1..]
    end

    # Parse the seconds
    begin
      secs = ss.to_i64
    rescue
      raise Error.new("invalid tar header")
    end

    return unix_time(secs, 0) unless sn.size > 0 # No sub-second values

    # Parse the nanoseconds.
    raise "invalid tar header" unless sn.strip("0123456789") == ""

    if sn.size < MAX_NANO_SECOND_DIGITS
      sn += ("0" * (MAX_NANO_SECOND_DIGITS - sn.size))
    else
      sn = sn[...MAX_NANO_SECOND_DIGITS] # Right truncate
    end

    nsecs = sn.to_i64                                               # Must succeed
    return unix_time(secs, -1*nsecs) if ss.size > 0 && ss[0] == '-' # negative correction

    unix_time(secs, nsecs)
  end

  # format_pax_time converts ts into a time of the form %d.%d as described in the
  # PAX specification. This function is capable of negative timestamps.
  def format_pax_time(ts : Time)
    secs, nsecs = ts.to_unix, ts.nanosecond
    return secs.to_s if nsecs == 0

    # If seconds is negative, then perform correction
    sign = ""
    if secs < 0
      sign = "-"             # Remember sign
      secs = -(secs + 1)     # Add a second to secs
      nsecs = -(nsecs - 1e9) # Take that second away from nsecs
    end
    sprintf("%s%d.%09d", [sign, secs, nsecs]).rstrip("0")
  end

  # parse_pax_record parses the input PAX record string into a key-value pair.
  # If parsing is successful, it will slice off the currently read record and
  # return the remainder as r.
  def parse_pax_record(s : String) : {String, String, String}
    # The size field ends at the first space.
    sp = byte_index(s, ' ')
    raise Error.new "invalid tar header" unless sp >= 0

    # Parse the first token as a decimal integer
    n = s[...sp].to_i { 0 } # Intentionally parse as native int
    raise Error.new "invalid tar header" if n < 5 || s.bytesize < n

    # Extract everything between the space and the final newline.
    rec = s.byte_slice(sp + 1, n - sp - 2)
    nl = s.byte_slice(n - 1, 1)
    rem = s.byte_slice(n)
    # return {"", "", s} unless nl == "\n"
    raise Error.new "invalid tar header" unless nl == "\n"

    # The first equals separates the key from the value
    eq = byte_index(rec, '=')
    return {"", "", s} unless eq >= 0
    k = rec.byte_slice(0, eq)
    v = rec.byte_slice(eq + 1)
    raise Error.new "invalid tar header" unless valid_pax_record(k, v)
    {k, v, rem}
  end

  # format_pax_record formats a single PAX record, prefixing it with the
  # appropriate length
  def format_pax_record(k : String, v : String)
    raise Error.new "invalid tar header" unless valid_pax_record(k, v)
    size = k.bytesize + v.bytesize + PADDING
    size += size.to_s.size
    rec = "#{size} #{k}=#{v}\n"
    # Final adjustment if adding size field increased the record size.
    if rec.bytesize != size
      size = rec.bytesize
      rec = "#{size} #{k}=#{v}\n"
    end
    rec
  end

  # valid_pax_record reports whether the key-value pair is valid where each
  # record is formatted as:
  #	"%d %s=%s\n" % (size, key, value)
  #
  # Keys and values should be UTF-8, but the number of bad writers out there
  # forces us to be a more liberal.
  # Thus, we only reject all keys with NUL, and only reject NULs in values
  # for the PAX version of the USTAR string fields.
  # The key must not contain an '=' character.
  def valid_pax_record(k : String, v : String)
    return false if k.blank? || byte_index(k, '=') >= 0
    case k
    when PAX_PATH, PAX_LINK_PATH, PAX_UNAME, PAX_GNAME
      !has_nul(v)
    else
      !has_nul(k)
    end
  end

  def byte_index(bytes : Bytes, b : Int)
    0.upto(bytes.size - 1) do |i|
      if bytes[i] == b
        return i
      end
    end
    -1
  end

  def byte_index(s : String, c : Char)
    byte_index(s.to_slice, c.ord)
  end

  def ltrim(b : Bytes, s : String)
    left = 0
    b.each do |c|
      if s.includes?(c.unsafe_chr)
        left += 1
      else
        break
      end
    end
    b[left..]
  end

  def rtrim(b : Bytes, s : String)
    a = b.dup.reverse!
    right = b.size - 1
    a.each do |c|
      if s.includes?(c.unsafe_chr)
        right -= 1
      else
        break
      end
    end
    b[..right]
  end

  def trim_bytes(b : Bytes, s : String)
    rtrim(ltrim(b, s), s)
  end

  def unix_time(sec : Int, nsec : Int)
    ts = Time.unix(sec)
    ts.shift(0, nsec)
  end

  def unix_time(sec, nsec)
    unix_time(sec.to_i64, nsec.to_i64)
  end

  private class Parser
    # parse_string parses bytes as a NUL-terminated C-style string.
    # If a NUL byte is not found then the whole slice is returned as a string.
    def parse_string(b : Bytes)
      if (i = Crystar.byte_index(b, 0)) && (i >= 0)
        String.new(b[...i])
      else
        String.new(b)
      end
    end

    # parse_numeric parses the input as being encoded in either base-256 or octal.
    # This function may return negative numbers.
    # If parsing fails or an integer overflow occurs, err will be set.
    def parse_numeric(b : Bytes) : Int64
      # Check for base-256 (binary) format first.
      # If the first bit is set, then all following bits constitue a two's
      # complement encoded number in big-endian byte order.
      if b.size > 0 && b[0] & 0x80 != 0
        # Handling negative numbers relies on the following identity:
        #	-a-1 == ^a
        #
        # If the number is negative, we use an inversion mask to invert the
        # data bytes and treat the value as an unsigned number.
        inv = b[0] & 0x40 != 0 ? 0xff_u8 : 0_u8
        x = 0_u64
        b.each_with_index do |c, i|
          c ^= inv            # inverts c only if inv is oxff, otherwise does nothing
          c &= 0x7f if i == 0 # Ignore signal bit in first byte
          raise Error.new("invalid tar header") if (x >> 56) > 0
          x = x << 8 | c.to_u64
        end
        raise Error.new("invalid tar header") if (x >> 63) > 0
        return ~x.to_i64 if inv == 0xff
        return x.to_i64
      end
      parse_octal(b)
    end

    def parse_octal(b : Bytes) : Int64
      # Because unused fields are filled with NULs, we need
      # to skip leading NULs. Fields may also be padded with
      # spaces or NULs.
      # So we remove leading and trailing NULs and spaces to
      # be sure.
      b = Crystar.trim_bytes(b, " \x00")
      return 0.to_i64 if b.size == 0
      begin
        (parse_string(b).to_u64(base: 8)).to_i64
      rescue exc
        raise Error.new "invalid tar header"
      end
    end
  end

  private class Formatter
    def initialize(@ignore_errors = false)
    end

    # format_string copies s into b, NUL-terminating if possible
    def format_string(b : Bytes, s : String) : Nil
      raise Error.new("header field too long") if !@ignore_errors && s.size > b.size
      size = s.bytesize > b.size ? b.size : s.bytesize
      b.copy_from(s.to_slice.to_unsafe, size)
      b[s.size] = 0 if s.size < b.size

      # Some buggy readers treat regular files with a trailing slash
      # in the V7 path field as a directory even though the full path
      # recorded elsewhere (e.g., via PAX record) contains no trailing slash.
      if b[b.size - 1] == '/'.ord
        n = s[...b.size].rstrip('/').size
        b[n] = 0 # Replace trailing slash with NUL terminator
      end
    end

    # format_numeric encodes x into b using base-8 (octal) encoding if possible.
    # Otherwise it will attempt to use base-256 (binary) encoding.
    def format_numeric(b : Bytes, x : Int64) : Nil
      if Crystar.fits_in_octal(b.size, x)
        format_octal(b, x)
        return
      end

      if Crystar.fits_in_base256(b.size, x)
        (b.size - 1).downto 0 do |i|
          b[i] = x.to_u8
          x >>= 8_i64
        end
        b[0] |= 0x80 # Highest bit indicates binary format
        return
      end

      format_octal(b, 0) # Last resort, just write zero
      raise Error.new("header field too long") if !@ignore_errors
    end

    def format_octal(b : Bytes, x : Int64) : Nil
      raise Error.new("header field too long") if !@ignore_errors && !Crystar.fits_in_octal(b.size, x)

      s = x.to_s(8) # .to_i64.to_s
      if (n = b.size - s.size - 1) && (n > 0)
        s = ("0" * n) + s
      end
      format_string(b, s)
    end
  end
end
