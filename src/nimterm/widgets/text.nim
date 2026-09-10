## Plain styled text widget.

import ../canvas
import ../geometry
import ../style
import ../widget

type
  TextWidget* = ref object of Widget
    text*: string
    style*: Style

proc newText*(text: string, style = defaultStyle()): TextWidget =
  TextWidget(text: text, style: style)

method measure*(widget: TextWidget, constraints: Constraints): Size =
  constraints.clamp(size(widget.text.len, 1))

method paint*(widget: TextWidget, canvas: var Canvas) =
  canvas.writeText(widget.area.x, widget.area.y, widget.text, widget.style,
    widget.area.w)
