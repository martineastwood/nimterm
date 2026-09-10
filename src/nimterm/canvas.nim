## Testable terminal-cell canvas.

from std/unicode import Rune, fastRuneAt, toUTF8
import ./geometry
import ./style

type
  Cell* = object
    glyph*: Rune
    style*: Style

  Canvas* = object
    size*: Size
    cells: seq[Cell]

proc blankCell*(style = defaultStyle()): Cell =
  Cell(glyph: Rune(32), style: style)

proc newCanvas*(canvasSize: Size, fill = blankCell()): Canvas =
  result.size = canvasSize
  result.cells = newSeq[Cell](max(0, canvasSize.w * canvasSize.h))
  for i in 0 ..< result.cells.len:
    result.cells[i] = fill

proc valid*(canvas: Canvas, x, y: int): bool =
  x >= 0 and y >= 0 and x < canvas.size.w and y < canvas.size.h

proc cellIndex(canvas: Canvas, x, y: int): int = y * canvas.size.w + x

proc getCell*(canvas: Canvas, x, y: int): Cell =
  if canvas.valid(x, y): canvas.cells[canvas.cellIndex(x, y)]
  else: blankCell()

proc setCell*(canvas: var Canvas, x, y: int, cell: Cell) =
  if canvas.valid(x, y): canvas.cells[canvas.cellIndex(x, y)] = cell

proc clear*(canvas: var Canvas, fill = blankCell()) =
  for i in 0 ..< canvas.cells.len:
    canvas.cells[i] = fill

proc writeText*(canvas: var Canvas, x, y: int, text: string,
                style = defaultStyle(), maxWidth = int.high) =
  var col = x
  var i = 0
  while i < text.len and col - x < maxWidth:
    var rune: Rune
    fastRuneAt(text, i, rune)
    if rune.int == 10:
      break
    canvas.setCell(col, y, Cell(glyph: rune, style: style))
    inc col

proc lineText*(canvas: Canvas, y: int): string =
  if y < 0 or y >= canvas.size.h:
    return ""
  for x in 0 ..< canvas.size.w:
    result.add canvas.getCell(x, y).glyph.toUTF8

proc plainText*(canvas: Canvas): string =
  for y in 0 ..< canvas.size.h:
    if y > 0: result.add '\n'
    result.add canvas.lineText(y)
