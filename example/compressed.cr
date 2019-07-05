require "gzip"
require "../src/crystar"
include Crystar

File.open("test.tar.gz") do |file|
  Gzip::Reader.open(file) do |gzip|
    Crystar::Reader.open(gzip) do |tar|
      tar.each_entry do |entry|
        p "Contents of #{entry.name}"
        IO.copy entry.io, STDOUT
      end
    end
  end
end
