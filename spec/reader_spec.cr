require "./spec_helper"
require "digest/md5"

module Crystar
  private struct TestInput
    getter file : String           # Test Input file
    getter headers : Array(Header) # Expected output headers
    getter chksums : Array(String) # MD5 checksum of files, leave as nil if not checked

    def initialize(@file, @headers, @chksums = Array(String).new)
    end
  end

  describe "Reader" do
    it "Test Reader" do
      vectors = [
        TestInput.new(
          file: "spec/testdata/gnu.tar",
          headers: [Header.new(
            name: "small.txt",
            mode: 0o640_i64,
            uid: 73025,
            gid: 5000,
            size: 5_i64,
            mod_time: unix_time(1244428340, 0),
            flag: '0'.ord.to_u8,
            uname: "dsymonds",
            gname: "eng",
            format: Format::GNU,
          ), Header.new(
            name: "small2.txt",
            mode: 0o640_i64,
            uid: 73025,
            gid: 5000,
            size: 11_i64,
            mod_time: unix_time(1244436044, 0),
            flag: '0'.ord.to_u8,
            uname: "dsymonds",
            gname: "eng",
            format: Format::GNU,
          )],
          chksums: [
            "e38b27eaccb4391bdec553a7f3ae6b2f",
            "c65bd2e50a56a2138bf1716f2fd56fe9",
          ]),
        TestInput.new(
          file: "spec/testdata/sparse-formats.tar",
          headers: [Header.new(
            name: "sparse-gnu",
            mode: 420_i64,
            uid: 1000,
            gid: 1000,
            size: 200_i64,
            mod_time: unix_time(1392395740, 0),
            flag: 0x53_u8,
            link_name: "",
            uname: "david",
            gname: "david",
            dev_major: 0_i64,
            dev_minor: 0_i64,
            format: Format::GNU,
          ), Header.new(
            name: "sparse-posix-0.0",
            mode: 420_i64,
            uid: 1000,
            gid: 1000,
            size: 200_i64,
            mod_time: unix_time(1392342187, 0),
            flag: 0x30_u8,
            link_name: "",
            uname: "david",
            gname: "david",
            dev_major: 0_i64,
            dev_minor: 0_i64,
            pax_records: Hash{
              "GNU.sparse.size"      => "200",
              "GNU.sparse.numblocks" => "95",
              "GNU.sparse.map"       => "1,1,3,1,5,1,7,1,9,1,11,1,13,1,15,1,17,1,19,1,21,1,23,1,25,1,27,1,29,1,31,1,33,1,35,1,37,1,39,1,41,1,43,1,45,1,47,1,49,1,51,1,53,1,55,1,57,1,59,1,61,1,63,1,65,1,67,1,69,1,71,1,73,1,75,1,77,1,79,1,81,1,83,1,85,1,87,1,89,1,91,1,93,1,95,1,97,1,99,1,101,1,103,1,105,1,107,1,109,1,111,1,113,1,115,1,117,1,119,1,121,1,123,1,125,1,127,1,129,1,131,1,133,1,135,1,137,1,139,1,141,1,143,1,145,1,147,1,149,1,151,1,153,1,155,1,157,1,159,1,161,1,163,1,165,1,167,1,169,1,171,1,173,1,175,1,177,1,179,1,181,1,183,1,185,1,187,1,189,1",
            },
            format: Format::PAX,
          ), Header.new(
            name: "sparse-posix-0.1",
            mode: 420_i64,
            uid: 1000,
            gid: 1000,
            size: 200_i64,
            mod_time: unix_time(1392340456, 0),
            flag: 0x30_u8,
            link_name: "",
            uname: "david",
            gname: "david",
            dev_major: 0_i64,
            dev_minor: 0_i64,
            pax_records: Hash{
              "GNU.sparse.size"      => "200",
              "GNU.sparse.numblocks" => "95",
              "GNU.sparse.map"       => "1,1,3,1,5,1,7,1,9,1,11,1,13,1,15,1,17,1,19,1,21,1,23,1,25,1,27,1,29,1,31,1,33,1,35,1,37,1,39,1,41,1,43,1,45,1,47,1,49,1,51,1,53,1,55,1,57,1,59,1,61,1,63,1,65,1,67,1,69,1,71,1,73,1,75,1,77,1,79,1,81,1,83,1,85,1,87,1,89,1,91,1,93,1,95,1,97,1,99,1,101,1,103,1,105,1,107,1,109,1,111,1,113,1,115,1,117,1,119,1,121,1,123,1,125,1,127,1,129,1,131,1,133,1,135,1,137,1,139,1,141,1,143,1,145,1,147,1,149,1,151,1,153,1,155,1,157,1,159,1,161,1,163,1,165,1,167,1,169,1,171,1,173,1,175,1,177,1,179,1,181,1,183,1,185,1,187,1,189,1",
              "GNU.sparse.name"      => "sparse-posix-0.1",
            },
            format: Format::PAX,
          ), Header.new(
            name: "sparse-posix-1.0",
            mode: 420_i64,
            uid: 1000,
            gid: 1000,
            size: 200_i64,
            mod_time: unix_time(1392337404, 0),
            flag: 0x30_u8,
            link_name: "",
            uname: "david",
            gname: "david",
            dev_major: 0_i64,
            dev_minor: 0_i64,
            pax_records: Hash{
              "GNU.sparse.major"    => "1",
              "GNU.sparse.minor"    => "0",
              "GNU.sparse.realsize" => "200",
              "GNU.sparse.name"     => "sparse-posix-1.0",
            },
            format: Format::PAX,
          ), Header.new(
            name: "end",
            mode: 420_i64,
            uid: 1000,
            gid: 1000,
            size: 4_i64,
            mod_time: unix_time(1392398319, 0),
            flag: 0x30_u8,
            link_name: "",
            uname: "david",
            gname: "david",
            dev_major: 0_i64,
            dev_minor: 0_i64,
            format: Format::GNU,
          )],
          chksums: [
            "6f53234398c2449fe67c1812d993012f",
            "6f53234398c2449fe67c1812d993012f",
            "6f53234398c2449fe67c1812d993012f",
            "6f53234398c2449fe67c1812d993012f",
            "b0061974914468de549a2af8ced10316",
          ]
        ),
        TestInput.new(
          file: "spec/testdata/star.tar",
          headers: [
            Header.new(
              name: "small.txt",
              mode: 0o0640_i64,
              uid: 73025,
              gid: 5000,
              size: 5_i64,
              mod_time: unix_time(1244592783, 0),
              flag: '0'.ord.to_u8,
              uname: "dsymonds",
              gname: "eng",
              access_time: unix_time(1244592783, 0),
              change_time: unix_time(1244592783, 0)
            ),
            Header.new(
              name: "small2.txt",
              mode: 0o0640_i64,
              uid: 73025,
              gid: 5000,
              size: 11_i64,
              mod_time: unix_time(1244592783, 0),
              flag: '0'.ord.to_u8,
              uname: "dsymonds",
              gname: "eng",
              access_time: unix_time(1244592783, 0),
              change_time: unix_time(1244592783, 0)
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/v7.tar",
          headers: [
            Header.new(
              name: "small.txt",
              mode: 0o0444_i64,
              uid: 73025,
              gid: 5000,
              size: 5_i64,
              mod_time: unix_time(1244593104, 0),
              flag: 0_u8
            ),
            Header.new(
              name: "small2.txt",
              mode: 0o0444_i64,
              uid: 73025,
              gid: 5000,
              size: 11_i64,
              mod_time: unix_time(1244593104, 0),
              flag: 0_u8
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/pax.tar",
          headers: [
            Header.new(
              name: "a/123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
              mode: 0o0664_i64,
              uid: 1000,
              gid: 1000,
              size: 7_i64,
              mod_time: unix_time(1350244992, 23960108),
              flag: Crystar::REG.ord.to_u8,
              uname: "shane",
              gname: "shane",
              access_time: unix_time(1350244992, 23960108),
              change_time: unix_time(1350244992, 23960108),
              pax_records: Hash{
                "path"  => "a/123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
                "mtime" => "1350244992.023960108",
                "atime" => "1350244992.023960108",
                "ctime" => "1350244992.023960108",
              },
              format: Format::PAX
            ),
            Header.new(
              name: "a/b",
              mode: 0o0777_i64,
              uid: 1000,
              gid: 1000,
              size: 0_i64,
              mod_time: unix_time(1350266320, 910238425),
              flag: Crystar::SYMLINK.ord.to_u8,
              uname: "shane",
              gname: "shane",
              access_time: unix_time(1350266320, 910238425),
              change_time: unix_time(1350266320, 910238425),
              link_name: "123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
              pax_records: Hash{
                "linkpath" => "123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
                "mtime"    => "1350266320.910238425",
                "atime"    => "1350266320.910238425",
                "ctime"    => "1350266320.910238425",
              },
              format: Format::PAX
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/pax-pos-size-file.tar",
          headers: [
            Header.new(
              name: "foo",
              mode: 0o0640_i64,
              uid: 319973,
              gid: 5000,
              size: 999_i64,
              mod_time: unix_time(1442282516, 0),
              flag: '0'.ord.to_u8,
              uname: "joetsai",
              gname: "eng",
              pax_records: Hash{
                "size" => "000000000000000000000999",
              },
              format: Format::PAX
            ),
          ],
          chksums: ["0afb597b283fe61b5d4879669a350556"]
        ),
        TestInput.new(
          file: "spec/testdata/pax-records.tar",
          headers: [
            Header.new(
              flag: REG.ord.to_u8,
              name: "file",
              uname: "long" * 10,
              mod_time: unix_time(0, 0),
              format: Format::PAX,
              pax_records: Hash{
                "GOLANG.pkg" => "tar",
                "comment"    => "Hello, 世界",
                "uname"      => "long" * 10,
              }
            ),
          ]),
        TestInput.new(
          file: "spec/testdata/trailing-slash.tar",
          headers: [
            Header.new(
              flag: DIR.ord.to_u8,
              name: "123456789/" * 30,
              mod_time: unix_time(0, 0),
              pax_records: Hash{
                "path" => "123456789/" * 30,
              },
              format: Format::PAX
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/pax-nil-sparse-data.tar",
          headers: [
            Header.new(
              flag: REG.ord.to_u8,
              name: "sparse.db",
              size: 1000_i64,
              mod_time: unix_time(0, 0),
              pax_records: Hash{
                "size"                => "1512",
                "GNU.sparse.major"    => "1",
                "GNU.sparse.minor"    => "0",
                "GNU.sparse.realsize" => "1000",
                "GNU.sparse.name"     => "sparse.db",
              },
              format: Format::PAX
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/gnu-utf8.tar",
          headers: [
            Header.new(
              flag: '0'.ord.to_u8,
              mode: 0o0644_i64,
              name: "☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹",
              uname: "☺",
              gname: "⚹",
              uid: 1000,
              gid: 1000,
              mod_time: unix_time(0, 0),
              format: Format::GNU
            ),
          ]
        ),
        TestInput.new(
          file: "spec/testdata/gnu-not-utf8.tar",
          headers: [
            Header.new(
              flag: '0'.ord.to_u8,
              mode: 0o0644_i64,
              name: "hi\x80\x81\x82\x83bye",
              uname: "rawr",
              gname: "dsnet",
              uid: 1000,
              gid: 1000,
              mod_time: unix_time(0, 0),
              format: Format::GNU
            ),
          ]
        ),
        # GNU tar file with atime and ctime fields set.
        # Created with the GNU tar v1.27.1.
        #	tar --incremental -S -cvf gnu-incremental.tar test2
        TestInput.new(
          file: "spec/testdata/gnu-incremental.tar",
          headers: [
            Header.new(
              name: "test2/",
              mode: 16877_i64,
              uid: 1000,
              gid: 1000,
              size: 14_i64,
              mod_time: unix_time(1441973427, 0),
              flag: 'D'.ord.to_u8,
              uname: "rawr",
              gname: "dsnet",
              access_time: unix_time(1441974501, 0),
              change_time: unix_time(1441973436, 0),
              format: Format::GNU
            ),
            Header.new(
              name: "test2/foo",
              mode: 33188_i64,
              uid: 1000,
              gid: 1000,
              size: 64_i64,
              mod_time: unix_time(1441973363, 0),
              flag: '0'.ord.to_u8,
              uname: "rawr",
              gname: "dsnet",
              access_time: unix_time(1441974501, 0),
              change_time: unix_time(1441973436, 0),
              format: Format::GNU
            ),
            Header.new(
              name: "test2/sparse",
              mode: 33188_i64,
              uid: 1000,
              gid: 1000,
              size: 536870912_i64,
              mod_time: unix_time(1441973427, 0),
              flag: 'S'.ord.to_u8,
              uname: "rawr",
              gname: "dsnet",
              access_time: unix_time(1441991948, 0),
              change_time: unix_time(1441973436, 0),
              format: Format::GNU
            ),
          ]
        ),
        #  Matches the behavior of GNU and BSD tar utilities.
        TestInput.new(
          file: "spec/testdata/pax-multi-hdrs.tar",
          headers: [
            Header.new(
              flag: '2'.ord.to_u8,
              name: "bar",
              link_name: "PAX4/PAX4/long-linkpath-name",
              mod_time: unix_time(0, 0),
              pax_records: Hash{
                "linkpath" => "PAX4/PAX4/long-linkpath-name",
              },
              format: Format::PAX
            ),
          ]
        ),
        # Both BSD and GNU tar truncate long names at first NUL even
        # if there is data following that NUL character.
        # This is reasonable as GNU long names are C-strings.
        TestInput.new(
          file: "spec/testdata/gnu-long-nul.tar",
          headers: [
            Header.new(
              flag: '0'.ord.to_u8,
              mode: 0o0644_i64,
              name: "0123456789",
              uid: 1000,
              gid: 1000,
              mod_time: unix_time(1486082191, 0),
              format: Format::GNU,
              uname: "rawr",
              gname: "dsnet"
            ),
          ]
        ),
      ]

      vectors.each do |v|
        File.open(v.file) do |file|
          Crystar::Reader.open(file) do |tar|
            p "Reading Crystar: #{v.file}"
            hdrs = Array(Header).new
            chksums = Array(String).new
            tar.each_entry do |entry|
              hdrs << entry
              next unless v.chksums.size > 0
              data = IO::Memory.new
              if entry.io.responds_to?(:write_to)
                entry.io.as(Crystar::Reader::FileReader).write_to(data)
              else
                IO.copy entry.io, data
              end
              chksums << Digest::MD5.hexdigest data.to_s
            end

            hdrs.size.should eq(v.headers.size)
            hdrs.should eq(v.headers)

            chksums.size.should eq(v.chksums.size)
            chksums.should eq(v.chksums)
          end
        end
      end
    end

    it "Test Reader with invalid Crystar" do
      vectors = [
        "spec/testdata/pax-bad-hdr-file.tar",
        "spec/testdata/pax-bad-mtime-file.tar",
        # BSD tar v3.1.2 and GNU tar v1.27.1 both rejects PAX records
        # with NULs in the key.
        "spec/testdata/pax-nul-xattrs.tar",
        # BSD tar v3.1.2 rejects a PAX path with NUL in the value, while
        # GNU tar v1.27.1 simply truncates at first NUL.
        # We emulate the behavior of BSD since it is strange doing NUL
        # truncations since PAX records are length-prefix strings instead
        # of NUL-terminated C-strings.
        "spec/testdata/pax-nul-path.tar",
        "spec/testdata/neg-size.tar",
      ]

      vectors.each do |f|
        File.open(f) do |file|
          Crystar::Reader.open(file) do |tar|
            p "Reading Crystar: #{f}"
            expect_raises(Crystar::Error, "invalid tar header") do
              tar.each_entry do |_|
              end
            end
          end
        end
      end
    end
  end
end
