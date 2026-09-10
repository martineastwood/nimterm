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
    titleStyle*: Style

proc newCard*(title, body: string, style = defaultStyle(),
              borderStyle = defaultStyle(), titleStyle = defaultStyle()): Card =
  Card(title: title, body: body, style: style, borderStyle: borderStyle,
    titleStyle: titleStyle)

method measure*(widget: Card, constraints: Constraints): Size =
  var width = widget.title.len + 4
  var height = 1
  for line in widget.body.splitLines:
    width = max(width, line.len + 4)
    inc height
  constraints.clamp(size(width, height))

method paint*(widget: Card, canvas: var Canvas) =
  if widget.area.w <= 0 or widget.area.h <= 0:
    return
  let right = widget.area.x + widget.area.w - 1
  let bottom = widget.area.y + widget.area.h - 1
  for y in widget.area.y .. bottom:
    for x in widget.area.x .. right:
      canvas.setCell(x, y, Cell(glyph: Rune(32), style: widget.style))
  for x in widget.area.x .. right:
    canvas.setCell(x, widget.area.y, Cell(glyph: Rune(32), style: widget.borderStyle))
  if widget.title.len > 0:
    canvas.writeText(widget.area.x + 1, widget.area.y, widget.title,
      widget.titleStyle, max(0, widget.area.w - 2))
  var y = widget.area.y + 1
  for line in widget.body.splitLines:
    if y > bottom: break
    canvas.writeText(widget.area.x + 1, y, line, widget.style,
      max(0, widget.area.w - 2))
    inc y
