## Markdown renderable using nimterm's plain semantic text path.

import std/strutils
import ../ansi
import ../canvas
import ../geometry
import ../markdown as markdown_renderer
import ../style
import ../widget

type
  Markdown* = ref object of Widget
    text*: string
    style*: Style

proc newMarkdown*(text: string, style = defaultStyle()): Markdown =
  Markdown(text: text, style: style)

method measure*(widget: Markdown, constraints: Constraints): Size =
  var width = 0
  var height = 0
  for line in markdown_renderer.renderMarkdown(widget.text, false).splitLines:
    width = max(width, ansiVisibleWidth(line))
    inc height
  constraints.clamp(size(width, height))

method paint*(widget: Markdown, canvas: var Canvas) =
  var y = widget.area.y
  for line in markdown_renderer.renderMarkdown(widget.text, false).splitLines:
    if y >= widget.area.y + widget.area.h: break
    canvas.writeText(widget.area.x, y, line, widget.style, widget.area.w)
    inc y
