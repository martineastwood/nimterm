## Minimal retained widget protocol.

import ./canvas
import ./events
import ./geometry

type
  EventResult* = enum
    eventIgnored
    eventHandled

  Widget* = ref object of RootObj
    area*: Rect

method children*(widget: Widget): seq[Widget] {.base.} = @[]

method focusable*(widget: Widget): bool {.base.} = false

method measure*(widget: Widget, constraints: Constraints): Size {.base.} =
  constraints.minSize

method layout*(widget: Widget, area: Rect) {.base.} =
  widget.area = area

method handle*(widget: Widget, event: UiEvent): EventResult {.base.} =
  eventIgnored

method paint*(widget: Widget, canvas: var Canvas) {.base.} =
  discard

proc render*(widget: Widget, canvas: var Canvas, area: Rect) =
  if widget.isNil: return
  widget.layout(area)
  widget.paint(canvas)

proc contains*(widget: Widget, target: Widget): bool =
  if widget == target: return true
  for child in widget.children:
    if child.contains(target): return true
