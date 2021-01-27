# Crystal Tar (Crystar)
![CI](https://github.com/naqvis/crystar/workflows/CI/badge.svg)
[![GitHub release](https://img.shields.io/github/release/naqvis/crystar.svg)](https://github.com/naqvis/crystar/releases)
[![Docs](https://img.shields.io/badge/docs-available-brightgreen.svg)](https://naqvis.github.io/crystar/)

Shard `Crystar` implements access to tar archives.

*No external library needed.* This is written in **pure Crystal**.

Tape archives (tar) are a file format for storing a sequence of files that can be read and written in a streaming manner. This shard aims to cover most variations of the format, including those produced by **GNU** and **BSD** tar tools.

This module is mostly based on [`Tar`](https://golang.google.cn/pkg/archive/tar/) package implementation of [Golang](http://golang.org/)


  Format represents the tar archive format.

  The original tar format was introduced in Unix V7.
  Since then, there have been multiple competing formats attempting to
  standardize or extend the **V7** format to overcome its limitations.
  The most common formats are the **USTAR**, **PAX**, and **GNU** formats,
  each with their own advantages and limitations.

  The following table captures the capabilities of each format:

  	                  |  USTAR |       PAX |       GNU
  	------------------+--------+-----------+----------
  	Name              |   256B | unlimited | unlimited
  	Linkname          |   100B | unlimited | unlimited
  	Size              | uint33 | unlimited |    uint89
  	Mode              | uint21 |    uint21 |    uint57
  	Uid/Gid           | uint21 | unlimited |    uint57
  	Uname/Gname       |    32B | unlimited |       32B
  	ModTime           | uint33 | unlimited |     int89
  	AccessTime        |    n/a | unlimited |     int89
  	ChangeTime        |    n/a | unlimited |     int89
  	Devmajor/Devminor | uint21 |    uint21 |    uint57
  	------------------+--------+-----------+----------
  	string encoding   |  ASCII |     UTF-8 |    binary
  	sub-second times  |     no |       yes |        no
  	sparse files      |     no |       yes |       yes

  The table's upper portion shows the Header fields, where each format reports
  the maximum number of bytes allowed for each string field and
  the integer type used to store each numeric field
  (where timestamps are stored as the number of seconds since the Unix epoch).

  The table's lower portion shows specialized features of each format,
  such as supported string encodings, support for sub-second timestamps,
  or support for sparse files.

  The `Writer` currently provides **no support** for _sparse files_.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     crystar:
       github: naqvis/crystar
   ```

2. Run `shards install`

## Usage

```crystal
require "crystar"
```

`Crystar` module contains readers and writers for tar archive.
Tape archives (tar) are a file format for storing a sequence of files that can be read and written in a streaming manner.
This module aims to cover most variations of the format, including those produced by GNU and BSD tar tools.

## Sample Usage
```crystal
files = [
  {"readme.txt", "This archive contains some text files."},
  {"minerals.txt", "Mineral names:\nalunite\nchromium\nvlasovite"},
  {"todo.txt", "Get crystal mining license."},
]

buf = IO::Memory.new
Crystar::Writer.open(buf) do |tw|
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
#Open and iterate through the files in the archive
buf.pos = 0
Crystar::Reader.open(buf) do |tar|
  tar.each_entry do |entry|
    p "Contents of #{entry.name}"
    IO.copy entry.io, STDOUT
    p "\n"
  end
end
```

Supports compressed archives as well.

```crystal
require "gzip"

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
```

Refer to `Crystar::Reader` and `Crystar::Writer` module for documentation on detailed usage.

# Development

To run all tests:

```
crystal spec
```

# Contributing

1. Fork it (<https://github.com/naqvis/crystar/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

# Contributors

- [Ali Naqvi](https://github.com/naqvis) - creator and maintainer
