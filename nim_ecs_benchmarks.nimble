# Package

version       = "0.1.0"
author        = "Nycto"
description   = "ECS benchmarks"
license       = "MIT"
srcDir        = "src"
bin           = @["report"]

# Dependencies

requires "nim >= 2.2.10"
requires "ggplotnim >= 0.7.6"
requires "cborious" # Required by libs/vecs
