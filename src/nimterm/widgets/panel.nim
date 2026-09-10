## Bordered container widget.

from std/unicode import Rune
import ../canvas
import ../geometry
import ../style
import ../widget

type
  Panel* = ref object of Widget
    child*: Widget
    title*: string
    style*: Style
    borderStyle*: Style

proc newPanel*(child: Widget = nil, title = "", style = defaultStyle(),
               borderStyle = defaultStyle()): Panel =
  Panel(child: child, title: title, style: style, borderStyle: borderStyle)

method measure*(widget: Panel, constraints: Constraints): Size =
  let inner = Constraints(
    minSize: size(max(0, constraints.minSize.w - 2),
      max(0, constraints.minSize.h - 2)),
    maxSize: size(max(0, constraints.maxSize.w - 2),
      max(0, constraints.maxSize.h - 2)))
  let childSize = if widget.child.isNil: size(0, 0) else: widget.child.measure(inner)
  constraints.clamp(size(childSize.w + 2, childSize.h + 2))

method paint*(widget: Panel, canvas: var Canvas) =
  if widget.area.w < 2 or widget.area.h < 2:
    return
  let x = widget.area.x
  let y = widget.area.y
  let right = x + widget.area.w - 1
  let bottom = y + widget.area.h - 1
  for col in x .. right:
    canvas.setCell(col, y, Cell(glyph: Rune(0x2500), style: widget.borderStyle))
    canvas.setCell(col, bottom, Cell(glyph: Rune(0x2500), style: widget.borderStyle))
  for row in y .. bottom:
    canvas.setCell(x, row, Cell(glyph: Rune(0x2502), style: widget.borderStyle))
    canvas.setCell(right, row, Cell(glyph: Rune(0x2502), style: widget.borderStyle))
  canvas.setCell(x, y, Cell(glyph: Rune(0x250c), style: widget.borderStyle))
  canvas.setCell(right, y, Cell(glyph: Rune(0x2510), style: widget.borderStyle))
  canvas.setCell(x, bottom, Cell(glyph: Rune(0x2514), style: widget.borderStyle))
  canvas.setCell(right, bottom, Cell(glyph: Rune(0x2518), style: widget.borderStyle))
  if widget.title.len > 0:
    canvas.writeText(x + 2, y, " " & widget.title & " ", widget.style,
      max(0, widget.area.w - 4))
  if not widget.child.isNil:
    widget.child.render(canvas, rect(x + 1, y + 1, widget.area.w - 2,
      widget.area.h - 2))
