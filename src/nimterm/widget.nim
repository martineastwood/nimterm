## Minimal retained widget protocol.

import ./canvas
import ./events
import ./geometry

type
  EventResponse* = object
    handled*: bool
    requestFocus*: bool
    captureMouse*: bool
    releaseMouse*: bool

  Widget* = ref object of RootObj
    area*: Rect

method children*(widget: Widget): seq[Widget] {.base.} = @[]

method focusable*(widget: Widget): bool {.base.} = false

method visible*(widget: Widget): bool {.base.} = true

method enabled*(widget: Widget): bool {.base.} = true

method modal*(widget: Widget): bool {.base.} = false

const
  eventIgnored* = EventResponse()
  eventHandled* = EventResponse(handled: true)

proc focusHandled*(): EventResponse =
  EventResponse(handled: true, requestFocus: true)

proc captureHandled*(): EventResponse =
  EventResponse(handled: true, requestFocus: true, captureMouse: true)

proc releaseHandled*(): EventResponse =
  EventResponse(handled: true, releaseMouse: true)

method measure*(widget: Widget, constraints: Constraints): Size {.base.} =
  constraints.minSize

method layout*(widget: Widget, area: Rect) {.base.} =
  widget.area = area

method handle*(widget: Widget, event: UiEvent): EventResponse {.base.} =
  eventIgnored

method paint*(widget: Widget, canvas: var Canvas) {.base.} =
  discard

proc render*(widget: Widget, canvas: var Canvas, area: Rect) =
  if widget.isNil or not widget.visible: return
  widget.layout(area)
  widget.paint(canvas)

proc contains*(widget: Widget, target: Widget): bool =
  if widget.isNil or not widget.visible or not widget.enabled: return false
  if widget == target: return true
  for child in widget.children:
    if child.contains(target): return true
