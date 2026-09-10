## ANSI-aware string walking, wrapping, and slicing for the TUI.

from std/unicode import Rune, fastRuneAt
import std/strutils
import ./text_width

proc skipAnsi*(s: string, i: var int): bool =
  ## If `s[i]` starts an ANSI sequence, advance `i` past it and return true.
  if i + 1 >= s.len or s[i] != '\x1b':
    return false
  if s[i + 1] == '[':
    i += 2
    while i < s.len and s[i] != 'm':
      inc i
    if i < s.len: inc i
    return true
  if s[i + 1] == ']':
    i += 2
    while i < s.len and s[i] != '\x07':
      inc i
    if i < s.len: inc i
    return true
  false

proc stripAnsi*(s: string): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    let start = i
    if skipAnsi(s, i):
      continue
    result.add s[start]
    inc i

proc ansiVisibleWidth*(s: string): int =
  ## Terminal columns ≈ rune count, ignoring ANSI escapes.
  var i = 0
  while i < s.len:
    if skipAnsi(s, i):
      continue
    var r: Rune
    fastRuneAt(s, i, r)
    result += r.cellWidth

proc wrapAnsi*(s: string, width: int): seq[string] =
  ## Hard-wrap ANSI text without counting escape sequences as columns.
  if width <= 0: return @[s]
  var line = ""
  var active = ""
  var column = 0
  var i = 0
  while i < s.len:
    if s[i] == '\e':
      let start = i
      if skipAnsi(s, i):
        let code = s[start ..< i]
        line.add code
        if code == "\e[0m" or code == "\e[m":
          active = ""
        elif code.startsWith("\e[") and code.endsWith("m"):
          active.add code
        continue
    var rune: Rune
    let start = i
    fastRuneAt(s, i, rune)
    if rune.int == 10:
      result.add line
      line = active
      column = 0
      continue
    let runeWidth = rune.cellWidth
    if column > 0 and column + runeWidth > width:
      if active.len > 0: line.add "\e[0m"
      result.add line
      line = active
      column = 0
    line.add s[start ..< i]
    column += runeWidth
  if line.len > 0 or result.len == 0:
    result.add line
