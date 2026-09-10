## Terminal display widths.

from std/unicode import Rune, fastRuneAt
from unicodedb/widths import UnicodeWidth, unicodeWidth, uwdtFull, uwdtWide
from unicodedb/properties import combining

proc cellWidth*(rune: Rune): int =
  if rune.combining != 0: 0
  elif rune.unicodeWidth in {uwdtFull, uwdtWide}: 2
  else: 1

proc displayWidth*(text: string): int =
  var i = 0
  while i < text.len:
    var rune: Rune
    fastRuneAt(text, i, rune)
    result += rune.cellWidth
