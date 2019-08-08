require "./spec_helper"

module Crystar
  describe "Writer" do
    it "Test PAX - Create an archive with a large name" do
      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        f.close

        # Force a PAX long name to be written
        contents = " " * hdr.size
        long_name = "ab" * 100
        hdr.name = long_name
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.write(contents.to_slice)
        end

        # Simple test to make sure PAX extension are in effect
        buf.pos = 0
        buf.to_s.should contain("PaxHeaders.0")

        # Test that we can get a long name back out of the archive.
        buf.pos = 0
        t = Crystar::Reader.new(buf)
        hdr = t.next_entry
        if hdr
          hdr.name.should eq(long_name)
        else
          fail "no header"
        end
      ensure
        buf.close
      end
    end

    it "Test PAX - Create an archive with a large linkname" do
      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        hdr.flag = SYMLINK.ord.to_u8
        f.close

        # Force a PAX long linkname to be written
        long_linkname = "1234567890/1234567890" * 10
        hdr.link_name = long_linkname
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
        end

        # Simple test to make sure PAX extension are in effect
        buf.pos = 0
        buf.to_s.should contain("PaxHeaders.0")

        # Test that we can get a long name back out of the archive.
        buf.pos = 0
        t = Crystar::Reader.new(buf)
        hdr = t.next_entry
        if hdr
          hdr.link_name.should eq(long_linkname)
        else
          fail "no header"
        end
      ensure
        buf.close
      end
    end

    it "Test PAX - Create an archive with non ascii" do
      # These should trigger a pax header because pax headers
      # have a defined utf-8 encoding.
      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        f.close

        # some sample data
        chinese_filename = "文件名"
        chinese_groupname = "組"
        chinese_username = "用戶名"
        contents = " " * hdr.size

        hdr.name = chinese_filename
        hdr.gname = chinese_groupname
        hdr.uname = chinese_username

        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.write(contents.to_slice)
        end

        # Simple test to make sure PAX extension are in effect
        buf.pos = 0
        buf.to_s.should contain("PaxHeaders.0")

        # Test that we can get a long name back out of the archive.
        buf.pos = 0
        t = Crystar::Reader.new(buf)
        hdr = t.next_entry
        if hdr
          hdr.name.should eq(chinese_filename)
          hdr.gname.should eq(chinese_groupname)
          hdr.uname.should eq(chinese_username)
        else
          fail "no header"
        end
      ensure
        buf.close
      end
    end

    it "Test PAX - Create an archive with an xattr" do
      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        f.close

        xattr = Hash{"user.key" => "value"}
        contents = "Kilts"
        hdr.xattr = xattr
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.write(contents.to_slice)
        end

        # Test that we can get a xattr back out of the archive.
        buf.pos = 0
        t = Crystar::Reader.new(buf)
        hdr = t.next_entry
        if hdr
          hdr.xattr.should eq(xattr)
        else
          fail "no header"
        end
      ensure
        buf.close
      end
    end

    it "Test PAX headers are sorted" do
      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        f.close

        # Force a PAX long name to be written
        contents = " " * hdr.size
        hdr.xattr = Hash{
          "foo" => "foo",
          "bar" => "bar",
          "baz" => "baz",
          "qux" => "qux",
        }

        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.write(contents.to_slice)
        end

        # Simple test to make sure PAX extension are in effect
        buf.pos = 0
        buf.to_s.should contain("PaxHeaders.0")

        # xattr bar should always appear before others
        buf.pos = 0
        str = buf.to_s
        index = ->(strs : String, s : String) {
          a = strs.index(s)
          fail "Couldn't find xattr = #{s}" if a.nil?
          a
        }
        indices = [
          index.call(str, "bar=bar"),
          index.call(str, "baz=baz"),
          index.call(str, "foo=foo"),
          index.call(str, "qux=qux"),
        ]
        indices.should eq(indices.sort)
      ensure
        buf.close
      end
    end

    it "Test USTAR - Create an archive with a large name" do
      # Create an archive with a path that failed to split with USTAR extension in previous versions.

      buf = IO::Memory.new
      begin
        f = File.open("spec/testdata/small.txt")
        hdr = Crystar.file_info_header(f, "")
        hdr.flag = DIR.ord.to_u8
        f.close

        # Force a PAX long name to be written. The name was taken from a practical example
        # that fails and replaced ever char through numbers to anonymize the sample.
        long_name = "/0000_0000000/00000-000000000/0000_0000000/00000-0000000000000/0000_0000000/00000-0000000-00000000/0000_0000000/00000000/0000_0000000/000/0000_0000000/00000000v00/0000_0000000/000000/0000_0000000/0000000/0000_0000000/00000y-00/0000/0000/00000000/0x000000/"
        hdr.name = long_name
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
        end

        # Test that we can get a long name back out of the archive.
        buf.pos = 0
        t = Crystar::Reader.new(buf)
        hdr = t.next_entry
        if hdr
          hdr.name.should eq(long_name)
        else
          fail "no header"
        end
      ensure
        buf.close
      end
    end

    it "Test PAX - Valid flag with PAX Header" do
      buf = IO::Memory.new
      begin
        file_name = "ab" * 100
        hdr = Header.new(
          name: file_name,
          size: 4_i64,
          flag: 0_u8
        )
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.write "fooo".to_slice
        end

        Crystar::Reader.open(buf) do |tar|
          tar.each_entry do |entry|
            entry.flag.should eq(REG.ord.to_u8)
          end
        end
      ensure
        buf.close
      end
    end

    it "Test Prefix field when encoding GNU format" do
      # Prefix field is valid in USTAR and PAX, but not GNU

      names = [
        "0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30/file.txt",
        "0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30/31/32/33/file.txt",
        "0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30/31/32/333/file.txt",
        "0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30/31/32/33/34/35/36/37/38/39/40/file.txt",
        "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000/file.txt",
        "/home/support/.openoffice.org/3/user/uno_packages/cache/registry/com.sun.star.comp.deployment.executable.PackageRegistryBackend",
      ]

      names.each_with_index do |name, i|
        b = IO::Memory.new
        hdr = Header.new(
          name: name,
          uid: 1 << 25, # Prevent USTAR format
        )
        Crystar::Writer.open(b) do |tw|
          tw.write_header hdr
        end

        # The Prefix field should never appear in the GNU format.
        blk = Block.new
        blk.to_bytes.copy_from(b.to_slice.to_unsafe, blk.size)
        prefix = String.new(blk.ustar.prefix)
        if (idx = byte_index(prefix, '\0')) && (i >= 0)
          prefix = prefix[...idx]
        end
        if blk.get_format == Format::GNU && !prefix.blank? && name.starts_with?(prefix)
          fail "test #{i}, found prefix in GNU format: #{prefix}"
        end
        b.pos = 0
        Crystar::Reader.open(b) do |tar|
          tar.each_entry do |entry|
            entry.name.should eq(name)
          end
        end
      end
    end
  end

  describe "Writer Errors" do
    it "Test for WriteTooLong" do
      buf = IO::Memory.new
      hdr = Header.new(name: "dir/", flag: DIR.ord.to_u8)
      Crystar::Writer.open(buf) do |tw|
        tw.write_header(hdr)
        expect_raises(ErrWriteTooLong) do
          tw.write(Bytes.new(1))
        end
      end
    end

    it "Test for Negative Size" do
      buf = IO::Memory.new
      hdr = Header.new(name: "small.txt", size: -1_i64)
      Crystar::Writer.open(buf) do |tw|
        expect_raises(Error, "negative size on header-only type") do
          tw.write_header(hdr)
        end
      end
    end

    it "Test write before header" do
      buf = IO::Memory.new

      Crystar::Writer.open(buf) do |tw|
        expect_raises(ErrWriteTooLong) do
          tw.write "Kilts".to_slice
        end
      end
    end

    it "Test After close" do
      buf = IO::Memory.new
      hdr = Header.new(name: "small.txt")
      tw = Crystar::Writer.new(buf)
      tw.write_header(hdr)
      tw.close
      expect_raises(Error, "Can't write to closed writer") do
        tw.write "Kilts".to_slice
      end
      expect_raises(Error, "Can't write to closed writer") do
        tw.flush
      end
      tw.close
    end

    it "Test for Premature flush" do
      buf = IO::Memory.new
      hdr = Header.new(name: "small.txt", size: 5_i64)
      expect_raises(Error) do
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
          tw.flush
        end
      end
    end

    it "Test for Premature close" do
      buf = IO::Memory.new
      hdr = Header.new(name: "small.txt", size: 5_i64)
      expect_raises(Error) do
        Crystar::Writer.open(buf) do |tw|
          tw.write_header(hdr)
        end
      end
    end
  end
end
