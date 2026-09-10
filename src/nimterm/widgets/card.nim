## Simple bordered card for generic terminal content.

import std/strutils
from std/unicode import Rune
import ../canvas
import ../geometry
import ../style
import ../widget

type
  Card* = ref object of Widget
    title*: string
    body*: string
    style*: Style
    borderStyle*: Style

proc newCard*(title, body: string, style = defaultStyle(),
              borderStyle = defaultStyle()): Card =
  Card(title: title, body: body, style: style, borderStyle: borderStyle)

method measure*(widget: Card, constraints: Constraints): Size =
  var width = widget.title.len + 4
  var height = 2
  for line in widget.body.splitLines:
    width = max(width, line.len + 4)
    inc height
  constraints.clamp(size(width, height))

method paint*(widget: Card, canvas: var Canvas) =
  if widget.area.w < 2 or widget.area.h < 2:
    return
  let right = widget.area.x + widget.area.w - 1
  let bottom = widget.area.y + widget.area.h - 1
  for x in widget.area.x .. right:
    canvas.setCell(x, widget.area.y, Cell(glyph: Rune(45), style: widget.borderStyle))
    canvas.setCell(x, bottom, Cell(glyph: Rune(45), style: widget.borderStyle))
  for y in widget.area.y .. bottom:
    canvas.setCell(widget.area.x, y, Cell(glyph: Rune(124), style: widget.borderStyle))
    canvas.setCell(right, y, Cell(glyph: Rune(124), style: widget.borderStyle))
  canvas.setCell(widget.area.x, widget.area.y, Cell(glyph: Rune(43), style: widget.borderStyle))
  canvas.setCell(right, widget.area.y, Cell(glyph: Rune(43), style: widget.borderStyle))
  canvas.setCell(widget.area.x, bottom, Cell(glyph: Rune(43), style: widget.borderStyle))
  canvas.setCell(right, bottom, Cell(glyph: Rune(43), style: widget.borderStyle))
  if widget.title.len > 0:
    canvas.writeText(widget.area.x + 2, widget.area.y, widget.title,
      widget.style, max(0, widget.area.w - 4))
  var y = widget.area.y + 1
  for line in widget.body.splitLines:
    if y >= bottom: break
    canvas.writeText(widget.area.x + 2, y, line, widget.style,
      max(0, widget.area.w - 4))
    inc y
