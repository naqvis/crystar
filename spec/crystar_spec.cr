require "./spec_helper"
require "file_utils"

module Crystar
  describe Crystar do
    describe "helper" do
      it "Test Fits In Base256" do
        texture = NamedTuple(in: Int64, width: Int32, ok: Bool)
        vectors = [texture.new(in: 1_i64, width: 8, ok: true),
                   texture.new(in: 0_i64, width: 8, ok: true),
                   texture.new(in: -1_i64, width: 8, ok: true),
                   texture.new(in: 1_i64, width: 8, ok: true),
                   texture.new(in: 1_i64 << 56, width: 8, ok: false),
                   texture.new(in: (1_i64 << 56) - 1, width: 8, ok: true),
                   texture.new(in: -1_i64 << 56, width: 8, ok: true),
                   texture.new(in: (-1_i64 << 56) - 1, width: 8, ok: false),
                   texture.new(in: 121654_i64, width: 8, ok: true),
                   texture.new(in: -9849849_i64, width: 8, ok: true),
                   texture.new(in: Int64::MAX, width: 9, ok: true),
                   texture.new(in: 0_i64, width: 9, ok: true),
                   texture.new(in: Int64::MIN, width: 9, ok: true),
                   texture.new(in: Int64::MAX, width: 12, ok: true),
                   texture.new(in: 0_i64, width: 12, ok: true),
                   texture.new(in: Int64::MIN, width: 12, ok: true),
        ]

        vectors.each do |v|
          ok = fits_in_base256(v[:width], v[:in])
          ok.should eq(v[:ok])
        end
      end

      it "Test Parse Numeric" do
        vectors = [{"", 0, true},
                   {"\x80", 0, true},
                   {"\x80\x00", 0, true},
                   {"\x80\x00\x00", 0, true},
                   {"\xbf", (1 << 6) - 1, true},
                   {"\xbf\xff", (1 << 14) - 1, true},
                   {"\xbf\xff\xff", (1 << 22) - 1, true},
                   {"\xff", -1, true},
                   {"\xff\xff", -1, true},
                   {"\xff\xff\xff", -1, true},
                   {"\xc0", -1 * (1 << 6), true},
                   {"\xc0\x00", -1 * (1 << 14), true},
                   {"\xc0\x00\x00", -1 * (1 << 22), true},
                   {"\x87\x76\xa2\x22\xeb\x8a\x72\x61", 537795476381659745, true},
                   {"\x80\x00\x00\x00\x07\x76\xa2\x22\xeb\x8a\x72\x61", 537795476381659745, true},
                   {"\xf7\x76\xa2\x22\xeb\x8a\x72\x61", -615126028225187231, true},
                   {"\xff\xff\xff\xff\xf7\x76\xa2\x22\xeb\x8a\x72\x61", -615126028225187231, true},
                   {"\x80\x7f\xff\xff\xff\xff\xff\xff\xff", Int64::MAX, true},
                   {"\x80\x80\x00\x00\x00\x00\x00\x00\x00", 0, false},
                   {"\xff\x80\x00\x00\x00\x00\x00\x00\x00", Int64::MIN, true},
                   {"\xff\x7f\xff\xff\xff\xff\xff\xff\xff", 0, false},
                   {"\xf5\xec\xd1\xc7\x7e\x5f\x26\x48\x81\x9f\x8f\x9b", 0, false},

                   # Test base-8 (octal) encoded values.
                   {"0000000\x00", 0, true},
                   {" \x0000000\x00", 0, true},
                   {" \x0000003\x00", 3, true},
                   {"00000000227\x00", 0o227, true},
                   {"032033\x00 ", 0o32033, true},
                   {"320330\x00 ", 0o320330, true},
                   {"0000660\x00 ", 0o660, true},
                   {"\x00 0000660\x00 ", 0o660, true},
                   {"0123456789abcdef", 0, false},
                   {"0123456789\x00abcdef", 0, false},
                   {"01234567\x0089abcdef", 342391, true},
                   {"0123\x7e\x5f\x264123", 0, false},
        ]
        pr = Parser.new
        vectors.each do |v|
          begin
            got = pr.parse_numeric(v[0].to_slice)
            got.should eq(v[1])
          rescue ex
            if v[2]
              raise "got: #{got}, want: #{v[1]}, ok: #{v[2]}" if got != v[1]
            end
          end
        end
      end

      it "Test Format Numeric" do
        vectors = [ # Test base-8 (octal) encoded values.
          {0, "0\x00", true},
          {7, "7\x00", true},
          {8, "\x80\x08", true},
          {0o77, "77\x00", true},
          {0o100, "\x80\x00\x40", true},
          {0, "0000000\x00", true},
          {0o123, "0000123\x00", true},
          {0o7654321, "7654321\x00", true},
          {0o7777777, "7777777\x00", true},
          {0o10000000, "\x80\x00\x00\x00\x00\x20\x00\x00", true},
          {0, "00000000000\x00", true},
          {0o00001234567, "00001234567\x00", true},
          {0o76543210321, "76543210321\x00", true},
          {0o12345670123, "12345670123\x00", true},
          {0o77777777777, "77777777777\x00", true},
          {0o100000000000, "\x80\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00", true},
          {Int64::MAX, "777777777777777777777\x00", true},

          # Test base-256 (binary) encoded values.
          {-1, "\xff", true},
          {-1, "\xff\xff", true},
          {-1, "\xff\xff\xff", true},
          {(1 << 0_i64), "0", false},
          {(1 << 8_i64) - 1, "\x80\xff", true},
          {(1 << 8_i64), "0\x00", false},
          {(1 << 16_i64) - 1, "\x80\xff\xff", true},
          {(1 << 16_i64), "00\x00", false},
          {-1 * (1 << 0_i64), "\xff", true},
          {-1*(1 << 0_i64) - 1, "0", false},
          {-1 * (1 << 8_i64), "\xff\x00", true},
          {-1*(1 << 8_i64) - 1, "0\x00", false},
          {-1 * (1 << 16_i64), "\xff\x00\x00", true},
          {-1*(1 << 16_i64) - 1, "00\x00", false},
          {537795476381659745, "0000000\x00", false},
          {537795476381659745, "\x80\x00\x00\x00\x07\x76\xa2\x22\xeb\x8a\x72\x61", true},
          {-615126028225187231, "0000000\x00", false},
          {-615126028225187231, "\xff\xff\xff\xff\xf7\x76\xa2\x22\xeb\x8a\x72\x61", true},
          {Int64::MAX, "0000000\x00", false},
          {Int64::MAX, "\x80\x00\x00\x00\x7f\xff\xff\xff\xff\xff\xff\xff", true},
          {Int64::MIN, "0000000\x00", false},
          {Int64::MIN, "\xff\xff\xff\xff\x80\x00\x00\x00\x00\x00\x00\x00", true},
          {Int64::MAX, "\x80\x7f\xff\xff\xff\xff\xff\xff\xff", true},
          {Int64::MIN, "\xff\x80\x00\x00\x00\x00\x00\x00\x00", true},
        ]

        fmt = Formatter.new

        vectors.each do |v|
          begin
            got = Bytes.new(v[1].to_slice.size)
            # begin
            fmt.format_numeric(got, v[0].to_i64)
          rescue
            next
          end
          got = String.new(got)
          if v[2]
            got.should eq(v[1])
          else
            got.should_not eq(v[1])
          end
          # rescue
          #   if v[2]
          #     raise Error.new("#{i + 1}: got: #{got}, want: #{v[1]}, ok: #{v[2]}") if got != v[1]
          #   end
          # end
        end
      end

      it "Test Fits in Octal" do
        vectors = [{-1, 1, false},
                   {-1, 2, false},
                   {-1, 3, false},
                   {0, 1, true},
                   {0 + 1, 1, false},
                   {0, 2, true},
                   {0o7, 2, true},
                   {0o7 + 1, 2, false},
                   {0, 4, true},
                   {0o777, 4, true},
                   {0o777 + 1, 4, false},
                   {0, 8, true},
                   {0o7777777, 8, true},
                   {0o7777777 + 1, 8, false},
                   {0, 12, true},
                   {0o77777777777, 12, true},
                   {0o77777777777 + 1, 12, false},
                   {Int64::MAX, 22, true},
                   {0o12345670123, 12, true},
                   {0o1564164, 12, true},
                   {-0o12345670123, 12, false},
                   {-0o1564164, 12, false},
                   {-1564164, 30, false},
        ]

        vectors.each do |v|
          ok = fits_in_octal(v[1], v[0].to_i64)
          ok.should eq(v[2])
        end
      end

      it "Test Parse PAXTime" do
        vectors = [
          {"1350244992.023960108", unix_time(1350244992, 23960108), true},
          {"1350244992.02396010", unix_time(1350244992, 23960100), true},
          {"1350244992.0239601089", unix_time(1350244992, 23960108), true},
          {"1350244992.3", unix_time(1350244992, 300000000), true},
          {"1350244992", unix_time(1350244992, 0), true},
          {"-1.000000001", unix_time(-1, -1e0), true},
          {"-1.000001", unix_time(-1, -1e3), true},
          {"-1.001000", unix_time(-1, -1e6), true},
          {"-1", unix_time(-1, -0), true},
          {"-1.999000", unix_time(-1, -1e9 + 1e6), true},
          {"-1.999999", unix_time(-1, -1e9 + 1e3), true},
          {"-1.999999999", unix_time(-1, -1e9 + 1e0), true},
          {"0.000000001", unix_time(0, 1e0), true},
          {"0.000001", unix_time(0, 1e3), true},
          {"0.001000", unix_time(0, 1e6), true},
          {"0", unix_time(0, 0), true},
          {"0.999000", unix_time(0, 1e9 - 1e6), true},
          {"0.999999", unix_time(0, 1e9 - 1e3), true},
          {"0.999999999", unix_time(0, 1e9 - 1e0), true},
          {"1.000000001", unix_time(+1, +1e0), true},
          {"1.000001", unix_time(+1, +1e3), true},
          {"1.001000", unix_time(+1, +1e6), true},
          {"1", unix_time(+1, 0), true},
          {"1.999000", unix_time(+1, +1e9 - 1e6), true},
          {"1.999999", unix_time(+1, +1e9 - 1e3), true},
          {"1.999999999", unix_time(+1, +1e9 - 1e0), true},
          {"-1350244992.023960108", unix_time(-1350244992, -23960108), true},
          {"-1350244992.02396010", unix_time(-1350244992, -23960100), true},
          {"-1350244992.0239601089", unix_time(-1350244992, -23960108), true},
          {"-1350244992.3", unix_time(-1350244992, -300000000), true},
          {"-1350244992", unix_time(-1350244992, 0), true},
          {"", unix_time(0, 0), false},
          {"0", unix_time(0, 0), true},
          {"1.", unix_time(1, 0), true},
          {"0.0", unix_time(0, 0), true},
          {".5", unix_time(0, 0), false},
          {"-1.3", unix_time(-1, -3e8), true},
          {"-1.0", unix_time(-1, 0), true},
          {"-0.0", unix_time(-0, 0), true},
          {"-0.1", unix_time(-0, -1e8), true},
          {"-0.01", unix_time(-0, -1e7), true},
          {"-0.99", unix_time(-0, -99e7), true},
          {"-0.98", unix_time(-0, -98e7), true},
          {"-1.1", unix_time(-1, -1e8), true},
          {"-1.01", unix_time(-1, -1e7), true},
          {"-2.99", unix_time(-2, -99e7), true},
          {"-5.98", unix_time(-5, -98e7), true},
          {"-", unix_time(0, 0), false},
          {"+", unix_time(0, 0), false},
          {"-1.-1", unix_time(0, 0), false},
          {"99999999999999999999999999999999999999999999999", unix_time(0, 0), false},
          {"0.123456789abcdef", unix_time(0, 0), false},
          {"foo", unix_time(0, 0), false},
          {"\x00", unix_time(0, 0), false},
          {"𝟵𝟴𝟳𝟲𝟱.𝟰𝟯𝟮𝟭𝟬", unix_time(0, 0), false}, # Unicode numbers (U+1D7EC to U+1D7F5)
          {"98765﹒43210", unix_time(0, 0), false}, # Unicode period (U+FE52)
        ]
        vectors.each do |v|
          begin
            ts = parse_pax_time(v[0])
            ts.should eq(v[1])
          rescue ex
            raise ex if v[2]
          end
        end
      end

      it "Test Format PAXTime" do
        vectors = [
          {1350244992, 0, "1350244992"},
          {1350244992, 300000000, "1350244992.3"},
          {1350244992, 23960100, "1350244992.0239601"},
          {1350244992, 23960108, "1350244992.023960108"},
          {+1, +1E9 - 1E0, "1.999999999"},
          {+1, +1E9 - 1E3, "1.999999"},
          {+1, +1E9 - 1E6, "1.999"},
          {+1, 0, "1"},
          {+1, +1E6, "1.001"},
          {+1, +1E3, "1.000001"},
          {+1, +1E0, "1.000000001"},
          {0, 1E9 - 1E0, "0.999999999"},
          {0, 1E9 - 1E3, "0.999999"},
          {0, 1E9 - 1E6, "0.999"},
          {0, 0, "0"},
          {0, 1E6, "0.001"},
          {0, 1E3, "0.000001"},
          {0, 1E0, "0.000000001"},
          {-1, -1E9 + 1E0, "-1.999999999"},
          {-1, -1E9 + 1E3, "-1.999999"},
          {-1, -1E9 + 1E6, "-1.999"},
          {-1, -0, "-1"},
          {-1, -1E6, "-1.001"},
          {-1, -1E3, "-1.000001"},
          {-1, -1E0, "-1.000000001"},
          {-1350244992, 0, "-1350244992"},
          {-1350244992, -300000000, "-1350244992.3"},
          {-1350244992, -23960100, "-1350244992.0239601"},
          {-1350244992, -23960108, "-1350244992.023960108"},
        ]
        vectors.each do |v|
          begin
            ts = format_pax_time(unix_time(v[0], v[1]))
            ts.should eq(v[2])
          rescue ex
            raise ex if v[2]
          end
        end
      end

      it "Test Parse PAX Record" do
        med_name = "CD" * 50
        long_name = "AB" * 100
        vectors = [
          {"6 k=v\n\n", "\n", "k", "v", true},
          {"19 path=/etc/hosts\n", "", "path", "/etc/hosts", true},
          {"210 path=#{long_name}\nabc", "abc", "path", long_name, true},
          {"110 path=#{med_name}\n", "", "path", med_name, true},
          {"9 foo=ba\n", "", "foo", "ba", true},
          {"11 foo=bar\n\x00", "\x00", "foo", "bar", true},
          {"18 foo=b=\nar=\n==\x00\n", "", "foo", "b=\nar=\n==\x00", true},
          {"27 foo=hello9 foo=ba\nworld\n", "", "foo", "hello9 foo=ba\nworld", true},
          {"27 ☺☻☹=日a本b語ç\nmeow mix", "meow mix", "☺☻☹", "日a本b語ç", true},
          {"17 \x00hello=\x00world\n", "17 \x00hello=\x00world\n", "", "", false},
          {"1 k=1\n", "1 k=1\n", "", "", false},
          {"6 k~1\n", "6 k~1\n", "", "", false},
          {"6_k=1\n", "6_k=1\n", "", "", false},
          {"6 k=1 ", "6 k=1 ", "", "", false},
          {"632 k=1\n", "632 k=1\n", "", "", false},
          {"16 longkeyname=hahaha\n", "16 longkeyname=hahaha\n", "", "", false},
          {"3 somelongkey=\n", "3 somelongkey=\n", "", "", false},
          {"50 tooshort=\n", "50 tooshort=\n", "", "", false},

        ]
        vectors.each do |v|
          begin
            key, val, res = parse_pax_record(v[0])
            if v[4]
              key.should eq(v[2])
              val.should eq(v[3])
              res.should eq(v[1])
            end
          rescue ex
            raise ex if v[4]
            # raise "expected: #{v[2]} = #{v[3]}, got: #{key} = #{val}" if v[4]
          end
        end
      end

      it "test Format PAX Record" do
        med_name = "CD" * 50
        long_name = "AB" * 100
        vectors = [
          {"k", "v", "6 k=v\n", true},
          {"path", "/etc/hosts", "19 path=/etc/hosts\n", true},
          {"path", long_name, "210 path=#{long_name}\n", true},
          {"path", med_name, "110 path=#{med_name}\n", true},
          {"foo", "ba", "9 foo=ba\n", true},
          {"foo", "bar", "11 foo=bar\n", true},
          {"foo", "b=\nar=\n==\x00", "18 foo=b=\nar=\n==\x00\n", true},
          {"foo", "hello9 foo=ba\nworld", "27 foo=hello9 foo=ba\nworld\n", true},
          {"☺☻☹", "日a本b語ç", "27 ☺☻☹=日a本b語ç\n", true},
          {"xhello", "\x00world", "17 xhello=\x00world\n", true},
          {"path", "null\x00", "", false},
          {"null\x00", "value", "", false},
          {PAX_SCHILY_XATTR + "key", "null\x00", "26 SCHILY.xattr.key=null\x00\n", true},
        ]
        vectors.each do |v|
          begin
            got = format_pax_record(v[0], v[1])
            got.should eq(v[2])
          rescue ex
            raise ex if v[3]
          end
        end
      end
    end

    describe "Crystar Common" do
      it "Test Sparse Entries" do
        vectors = [
          {in: [SparseEntry.new 0, 0], size: 0, want_valid: true,
           want_aligned: [] of SparseEntry,
           want_inverted: [SparseEntry.new 0, 0]},
          {in: [SparseEntry.empty], size: 5000, want_valid: true,
           want_aligned: [] of SparseEntry,
           want_inverted: [SparseEntry.new 0, 5000]},
          {
            in: [SparseEntry.new 0, 5000], size: 5000,
            want_valid: true,
            want_aligned: [SparseEntry.new 0, 5000],
            want_inverted: [SparseEntry.new 5000, 0],
          },
          {
            in: [SparseEntry.new 1000, 4000], size: 5000,
            want_valid: true,
            want_aligned: [SparseEntry.new 1024, 3976],
            want_inverted: [SparseEntry.new(0, 1000), SparseEntry.new 5000, 0],
          },
          {
            in: [SparseEntry.new 0, 3000], size: 5000,
            want_valid: true,
            want_aligned: [SparseEntry.new 0, 2560],
            want_inverted: [SparseEntry.new 3000, 2000],
          }, {
            in: [SparseEntry.new 3000, 2000], size: 5000,
            want_valid: true,
            want_aligned: [SparseEntry.new 3072, 1928],
            want_inverted: [SparseEntry.new(0, 3000), SparseEntry.new 5000, 0],
          }, {
            in: [SparseEntry.new 2000, 2000], size: 5000,
            want_valid: true,
            want_aligned: [SparseEntry.new 2048, 1536],
            want_inverted: [SparseEntry.new(0, 2000), SparseEntry.new 4000, 1000],
          }, {
            in: [SparseEntry.new(0, 2000), SparseEntry.new 8000, 2000], size: 10000,
            want_valid: true,
            want_aligned: [SparseEntry.new(0, 1536), SparseEntry.new 8192, 1808],
            want_inverted: [SparseEntry.new(2000, 6000), SparseEntry.new 10000, 0],
          }, {
            in:           [SparseEntry.new(0, 2000), SparseEntry.new(2000, 2000), SparseEntry.new(4000, 0), SparseEntry.new(4000, 3000),
                 SparseEntry.new(7000, 1000), SparseEntry.new(8000, 0), SparseEntry.new 8000, 2000], size:         10000,
            want_valid:   true,
            want_aligned: [SparseEntry.new(0, 1536), SparseEntry.new(2048, 1536), SparseEntry.new(4096, 2560), SparseEntry.new(7168, 512),
                           SparseEntry.new 8192, 1808],
            want_inverted: [SparseEntry.new 10000, 0],
          }, {
            in:            [SparseEntry.new(0, 0), SparseEntry.new(1000, 0), SparseEntry.new(2000, 0), SparseEntry.new(3000, 0), SparseEntry.new(4000, 0),
                 SparseEntry.new 5000, 0], size:          5000,
            want_valid:    true,
            want_aligned:  [] of SparseEntry,
            want_inverted: [SparseEntry.new 0, 5000],
          }, {
            in: [SparseEntry.new 1, 0], size: 0,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new -1, 0], size: 100,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new 0, -1], size: 100,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new 0, 0], size: -100,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new(Int64::MAX, 3), SparseEntry.new 6, -5], size: 35,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new(1, 3), SparseEntry.new 6, -5], size: 35,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new Int64::MAX, Int64::MAX], size: Int64::MAX,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new 3, 3], size: 5,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new(2, 0), SparseEntry.new(1, 0), SparseEntry.new 0, 0], size: 3,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          }, {
            in: [SparseEntry.new(1, 3), SparseEntry.new 2, 2], size: 10,
            want_valid: false,
            want_aligned: [] of SparseEntry,
            want_inverted: [] of SparseEntry,
          },
        ]

        vectors.each do |v|
          valid = validate_sparse_entries(v[:in], v[:size].to_i64)
          valid.should eq(v[:want_valid])
          next unless v[:want_valid]
          aligned = align_sparse_entries([SparseEntry.empty] + v[:in], v[:size].to_i64)
          aligned.should eq(v[:want_aligned])
          inverted = invert_sparse_entries([SparseEntry.empty] + v[:in], v[:size].to_i64)
          inverted.should eq(v[:want_inverted])
        end
      end
    end

    describe "Crystar Header" do
      it "Test Header Allowed" do
        vectors = [
          {
            header:  Header.new,
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(size: 0o77777777777),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(size: 0o77777777777, format: Format::USTAR),
            formats: Format::USTAR,
          }, {
            header:  Header.new(size: 0o77777777777, format: Format::PAX),
            formats: Format::USTAR | Format::PAX,
          }, {
            header:  Header.new(size: 0o77777777777, format: Format::GNU),
            formats: Format::GNU,
          }, {
            header:   Header.new(size: 0o77777777777 + 1),
            pax_hdrs: Hash{PAX_SIZE => "8589934592"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(size: 0o77777777777 + 1, format: Format::PAX),
            pax_hdrs: Hash{PAX_SIZE => "8589934592"},
            formats:  Format::PAX,
          }, {
            header:   Header.new(size: 0o77777777777 + 1, format: Format::GNU),
            pax_hdrs: Hash{PAX_SIZE => "8589934592"},
            formats:  Format::GNU,
          }, {
            header:  Header.new(mode: 0o7777777_i64),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(mode: 0o7777777_i64 + 1),
            formats: Format::GNU,
          }, {
            header:  Header.new(dev_major: -123_i64),
            formats: Format::GNU,
          }, {
            header:  Header.new(dev_major: 1_i64 << 56 - 1),
            formats: Format::GNU,
          }, {
            header:  Header.new(dev_major: 1_i64 << 56),
            formats: Format::None,
          }, {
            header:  Header.new(dev_major: -1_i64 << 56),
            formats: Format::GNU,
          }, {
            header:  Header.new(dev_major: -1_i64 << 56 - 1),
            formats: Format::None,
          }, {
            header:  Header.new(name: "用戶名", dev_major: -1_i64 << 56),
            formats: Format::GNU,
          }, {
            header:   Header.new(size: Int64::MAX),
            pax_hdrs: Hash{PAX_SIZE => "9223372036854775807"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(size: Int64::MIN),
            pax_hdrs: Hash{PAX_SIZE => "-9223372036854775808"},
            formats:  Format::None,
          }, {
            header:  Header.new(uname: "0123456789abcdef0123456789abcdef"),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(uname: "0123456789abcdef0123456789abcdefx"),
            pax_hdrs: Hash{PAX_UNAME => "0123456789abcdef0123456789abcdefx"},
            formats:  Format::PAX,
          }, {
            header:  Header.new(name: "foobar"),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(name: "a" * NAME_SIZE),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(name: "a" * (NAME_SIZE + 1)),
            pax_hdrs: Hash{PAX_PATH => "a" * (NAME_SIZE + 1)},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(link_name: "用戶名"),
            pax_hdrs: Hash{PAX_LINK_PATH => "用戶名"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(link_name: "用戶名\x00" * NAME_SIZE),
            pax_hdrs: Hash{PAX_LINK_PATH => "用戶名\x00" * NAME_SIZE},
            formats:  Format::None,
          }, {
            header:   Header.new(link_name: "\x00hello"),
            pax_hdrs: Hash{PAX_LINK_PATH => "\x00hello"},
            formats:  Format::None,
          }, {
            header:  Header.new(uid: 0o7777777),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(uid: 0o7777777 + 1),
            pax_hdrs: Hash{PAX_UID => "2097152"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:  Header.new(xattr: Hash(String, String).new),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(xattr: Hash{"foo" => "bar"}),
            pax_hdrs: Hash{PAX_SCHILY_XATTR + "foo" => "bar"},
            formats:  Format::PAX,
          }, {
            header:   Header.new(xattr: Hash{"foo" => "bar"}, format: Format::GNU),
            pax_hdrs: Hash{PAX_SCHILY_XATTR + "foo" => "bar"},
            formats:  Format::None,
          }, {
            header:   Header.new(xattr: Hash{"用戶名" => "\x00hello"}),
            pax_hdrs: Hash{PAX_SCHILY_XATTR + "用戶名" => "\x00hello"},
            formats:  Format::PAX,
          }, {
            header:  Header.new(xattr: Hash{"foo=bar" => "baz"}),
            formats: Format::None,
          }, {
            header:   Header.new(xattr: Hash{"foo" => ""}),
            pax_hdrs: Hash{PAX_SCHILY_XATTR + "foo" => ""},
            formats:  Format::PAX,
          }, {
            header:  Header.new(mod_time: unix_time(0, 0)),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(mod_time: unix_time(0o77777777777, 0)),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(0o77777777777 + 1, 0)),
            pax_hdrs: Hash{PAX_MTIME => "8589934592"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(Int32::MAX.to_i64, 0)),
            pax_hdrs: Hash{PAX_MTIME => "2147483647"},
            formats:  Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(Int32::MAX.to_i64, 0), format: Format::USTAR),
            pax_hdrs: Hash{PAX_MTIME => "2147483647"},
            formats:  Format::None,
          }, {
            header:   Header.new(mod_time: unix_time(-1, 0)),
            pax_hdrs: Hash{PAX_MTIME => "-1"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(1, 500)),
            pax_hdrs: Hash{PAX_MTIME => "1.0000005"},
            formats:  Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(mod_time: unix_time(1, 0)),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(mod_time: unix_time(1, 0), format: Format::PAX),
            formats: Format::USTAR | Format::PAX,
          }, {
            header:   Header.new(mod_time: unix_time(1, 500), format: Format::USTAR),
            pax_hdrs: Hash{PAX_MTIME => "1.0000005"},
            formats:  Format::USTAR,
          }, {
            header:   Header.new(mod_time: unix_time(1, 500), format: Format::PAX),
            pax_hdrs: Hash{PAX_MTIME => "1.0000005"},
            formats:  Format::PAX,
          }, {
            header:   Header.new(mod_time: unix_time(1, 500), format: Format::GNU),
            pax_hdrs: Hash{PAX_MTIME => "1.0000005"},
            formats:  Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(-1, 500)),
            pax_hdrs: Hash{PAX_MTIME => "-0.9999995"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(mod_time: unix_time(-1, 500), format: Format::GNU),
            pax_hdrs: Hash{PAX_MTIME => "-0.9999995"},
            formats:  Format::GNU,
          }, {
            header:   Header.new(access_time: unix_time(1, 0)),
            pax_hdrs: Hash{PAX_ATIME => "1"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(access_time: unix_time(0, 0), format: Format::USTAR),
            pax_hdrs: Hash{PAX_ATIME => "0"},
            formats:  Format::None,
          }, {
            header:   Header.new(access_time: unix_time(1, 0), format: Format::PAX),
            pax_hdrs: Hash{PAX_ATIME => "1"},
            formats:  Format::PAX,
          }, {
            header:   Header.new(access_time: unix_time(0, 0), format: Format::GNU),
            pax_hdrs: Hash{PAX_ATIME => "1"},
            formats:  Format::GNU,
          }, {
            header:   Header.new(access_time: unix_time(-123, 0)),
            pax_hdrs: Hash{PAX_ATIME => "-123"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(access_time: unix_time(-123, 0), format: Format::PAX),
            pax_hdrs: Hash{PAX_ATIME => "-123"},
            formats:  Format::PAX,
          }, {
            header:   Header.new(change_time: unix_time(123, 456)),
            pax_hdrs: Hash{PAX_CTIME => "123.000000456"},
            formats:  Format::PAX | Format::GNU,
          }, {
            header:   Header.new(change_time: unix_time(123, 456), format: Format::USTAR),
            pax_hdrs: Hash{PAX_CTIME => "123.000000456"},
            formats:  Format::None,
          }, {
            header:   Header.new(change_time: unix_time(123, 456), format: Format::GNU),
            pax_hdrs: Hash{PAX_CTIME => "123.000000456"},
            formats:  Format::GNU,
          }, {
            header:   Header.new(change_time: unix_time(123, 456), format: Format::PAX),
            pax_hdrs: Hash{PAX_CTIME => "123.000000456"},
            formats:  Format::PAX,
          }, {
            header:  Header.new(name: "foo/", flag: DIR.ord.to_u8),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          }, {
            header:  Header.new(name: "foo/", flag: REG.ord.to_u8),
            formats: Format::None,
          }, {
            header:  Header.new(name: "foo/", flag: SYMLINK.ord.to_u8),
            formats: Format::USTAR | Format::PAX | Format::GNU,
          },
        ]

        vectors.each_with_index do |v, i|
          begin
            formats, pax_hdrs = v[:header].allowed_formats
            formats.should eq(v[:formats])
            if formats.pax? && ((h = v[:pax_hdrs]?) && pax_hdrs.size == h.size)
              pax_hdrs.should eq(h)
            end
          rescue ex
            msg = "#{i + 1} - #{ex.message}"
            raise msg if !v[:formats].none?
          end
        end
      end
    end

    describe "File Info Header" do
      it "Test file info header file" do
        f = File.open("spec/testdata/small.txt")
        info = f.info
        begin
          h = Crystar.file_info_header(f, "")
          h.name.should eq("small.txt")
          h.mod_time.should eq(info.modification_time)
          h.mode.should eq(info.permissions.value)
          h.size.should eq(5)
        ensure
          f.close
        end
      end

      it "Test file info header directory" do
        f = File.open("spec/testdata")
        info = f.info
        begin
          h = Crystar.file_info_header(f, "")
          h.name.should eq("testdata/")
          h.mod_time.should eq(info.modification_time)
          h.mode.should eq(info.permissions.value)
          h.size.should eq(0)
        ensure
          f.close
        end
      end

      it "Test file info header symlink" do
        t = File.tempfile("TestFileInfoHeaderSymlink", "link")
        tempname = File.tempname
        begin
          FileUtils.ln_s(t.path, tempname)
          f = File.open(tempname)
          h = Crystar.file_info_header(f, t.path)
          h.name.should eq(File.basename(tempname))
          h.link_name.should eq(t.path)
          h.flag.should eq(SYMLINK.ord)
        ensure
          t.delete
          File.delete(tempname)
        end
      end
    end
  end
end
