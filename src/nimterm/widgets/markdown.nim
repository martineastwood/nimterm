## Markdown renderable using nimterm's plain semantic text path.

import ../canvas
import ../geometry
import ../markdown as markdown_renderer
import ../style
import ../styled_text
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
  for line in markdown_renderer.renderMarkdownLines(widget.text):
    width = max(width, line.width)
    inc height
  constraints.clamp(size(width, height))

method paint*(widget: Markdown, canvas: var Canvas) =
  var y = widget.area.y
  for line in markdown_renderer.renderMarkdownLines(widget.text):
    if y >= widget.area.y + widget.area.h: break
    line.write(canvas, widget.area.x, y, widget.area.w, widget.style)
    inc y
