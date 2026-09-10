## Minimal widget composition.

import ../canvas
import ../geometry
import ../widget

type
  Column* = ref object of Widget
    items*: seq[Widget]

  Stack* = ref object of Widget
    items*: seq[Widget]

proc newColumn*(items: seq[Widget]): Column = Column(items: items)
proc newStack*(items: seq[Widget]): Stack = Stack(items: items)

method children*(widget: Column): seq[Widget] = widget.items
method children*(widget: Stack): seq[Widget] = widget.items

method paint*(widget: Column, canvas: var Canvas) =
  if widget.items.len == 0: return
  var y = widget.area.y
  for i, child in widget.items:
    let bottom = widget.area.y + widget.area.h
    let height = (bottom - y) div (widget.items.len - i)
    child.render(canvas, rect(widget.area.x, y, widget.area.w, height))
    y += height

method paint*(widget: Stack, canvas: var Canvas) =
  for child in widget.items: child.render(canvas, widget.area)
