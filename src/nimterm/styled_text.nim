from std/unicode import Rune, fastRuneAt
import ./canvas
import ./style
import ./text_width

type
  TextSpan* = object
    text*: string
    style*: Style
  StyledLine* = seq[TextSpan]

proc add*(line: var StyledLine, text: string, style = defaultStyle()) =
  if text.len == 0: return
  if line.len > 0 and line[^1].style == style: line[^1].text.add text
  else: line.add TextSpan(text: text, style: style)

proc text*(line: StyledLine): string =
  for span in line: result.add span.text

proc width*(line: StyledLine): int =
  for span in line: result += span.text.displayWidth

proc ansi*(line: StyledLine, enabled = true): string =
  for span in line:
    let code = if enabled: span.style.ansi else: ""
    if code.len > 0: result.add code
    result.add span.text
    if code.len > 0: result.add "\e[0m"

proc write*(line: StyledLine, canvas: var Canvas, x, y, maxWidth: int,
            base = defaultStyle()) =
  var column = x
  for span in line:
    let remaining = maxWidth - (column - x)
    if remaining <= 0: break
    canvas.writeText(column, y, span.text, base.overlay(span.style), remaining)
    column += min(remaining, span.text.displayWidth)

proc wrap*(line: StyledLine, maxWidth: int): seq[StyledLine] =
  if maxWidth <= 0: return @[line]
  var current: StyledLine
  var currentWidth = 0
  for span in line:
    var i = 0
    while i < span.text.len:
      let start = i
      var rune: Rune
      fastRuneAt(span.text, i, rune)
      let runeWidth = rune.cellWidth
      if currentWidth > 0 and currentWidth + runeWidth > maxWidth:
        result.add current
        current = @[]
        currentWidth = 0
      current.add(span.text[start ..< i], span.style)
      currentWidth += runeWidth
  if current.len > 0 or result.len == 0: result.add current
