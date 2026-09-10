## ANSI-aware string walking, wrapping, and slicing for the TUI.

from std/unicode import Rune, fastRuneAt

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
    inc result
