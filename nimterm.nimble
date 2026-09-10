version       = "0.1.0"
author        = "martin"
description   = "Terminal UI primitives for Nim applications"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"

task test, "Run the test suite":
  exec "nim c -r --hints:off --path:src tests/all_tests.nim"
