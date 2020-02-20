require "../src/crystar"
include Crystar

files = [
  {"readme.txt", "This archive contains some text files."},
  {"minerals.txt", "Mineral names:\nalunite\nchromium\nvlasovite"},
  {"todo.txt", "Get crystal mining license."},
]

File.open("test.tar", "w") do |file|
  Crystar::Writer.open(file) do |tw|
    files.each do |f|
      hdr = Header.new(
        name: f[0],
        mode: 0o600_i64,
        size: f[1].size.to_i64
      )
      tw.write_header(hdr)
      tw.write(f[1].to_slice)
    end
  end
end

# Open and iterate through the files in the archive
File.open("test.tar") do |file|
  Crystar::Reader.open(file) do |tar|
    tar.each_entry do |entry|
      p "Contents of #{entry.name}"
      IO.copy entry.io, STDOUT
      p ""
    end
  end
end
