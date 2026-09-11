## Testable terminal-cell canvas.

from std/unicode import Rune, fastRuneAt, toUTF8
import ./geometry
import ./style
import ./ansi
import ./theme
import ./text_width

type
  Cell* = object
    glyph*: Rune
    combining*: string
    continuation*: bool
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

proc fill*(canvas: var Canvas, area: Rect, cell = blankCell()) =
  for y in max(0, area.y) ..< min(canvas.size.h, area.y + area.h):
    for x in max(0, area.x) ..< min(canvas.size.w, area.x + area.w):
      canvas.cells[canvas.cellIndex(x, y)] = cell

proc copy*(canvas: Canvas): Canvas =
  result.size = canvas.size
  result.cells = newSeq[Cell](canvas.cells.len)
  for i, cell in canvas.cells: result.cells[i] = cell

proc writeText*(canvas: var Canvas, x, y: int, text: string,
                style = defaultStyle(), maxWidth = int.high) =
  var col = x
  var i = 0
  while i < text.len and col - x < maxWidth:
    var rune: Rune
    fastRuneAt(text, i, rune)
    if rune.int == 10:
      break
    let width = rune.cellWidth
    if width == 0:
      if col > x:
        var cell = canvas.getCell(col - 1, y)
        cell.combining.add rune.toUTF8
        canvas.setCell(col - 1, y, cell)
    elif col - x + width <= maxWidth:
      canvas.setCell(col, y, Cell(glyph: rune, style: style))
      if width == 2: canvas.setCell(col + 1, y,
        Cell(glyph: Rune(32), style: style, continuation: true))
      col += width

proc writeAnsiText*(canvas: var Canvas, x, y: int, text: string,
                    baseStyle = defaultStyle(), maxWidth = int.high) =
  ## Write ANSI-styled text as semantic cells, preserving the base background.
  var col = x
  var i = 0
  var active = baseStyle
  while i < text.len and col - x < maxWidth:
    if text[i] == '\e':
      let start = i
      if skipAnsi(text, i):
        let code = text[start ..< i]
        if code == "\e[0m" or code == "\e[m":
          active = baseStyle
        else:
          let overlay = styleFromSgr(code)
          if overlay.foreground.kind != colorDefault:
            active.foreground = overlay.foreground
          if overlay.background.kind != colorDefault:
            active.background = overlay.background
          active.attributes = active.attributes + overlay.attributes
        continue
    var rune: Rune
    fastRuneAt(text, i, rune)
    let width = rune.cellWidth
    if width == 0:
      if col > x:
        var cell = canvas.getCell(col - 1, y)
        cell.combining.add rune.toUTF8
        canvas.setCell(col - 1, y, cell)
    elif col - x + width <= maxWidth:
      canvas.setCell(col, y, Cell(glyph: rune, style: active))
      if width == 2: canvas.setCell(col + 1, y,
        Cell(glyph: Rune(32), style: active, continuation: true))
      col += width

proc lineText*(canvas: Canvas, y: int): string =
  if y < 0 or y >= canvas.size.h:
    return ""
  for x in 0 ..< canvas.size.w:
    let cell = canvas.getCell(x, y)
    if not cell.continuation: result.add cell.glyph.toUTF8 & cell.combining
    else: result.add ' '

proc plainText*(canvas: Canvas): string =
  for y in 0 ..< canvas.size.h:
    if y > 0: result.add '\n'
    result.add canvas.lineText(y)
