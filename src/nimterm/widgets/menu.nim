## Selectable label/description menu.

import ../canvas
import ../events
import ../geometry
import ../keys
import ../style
import ../widget

type
  MenuItem* = object
    label*: string
    description*: string

  Menu* = ref object of Widget
    items*: seq[MenuItem]
    selected*: int
    style*: Style
    selectedStyle*: Style
    onSelect*: proc (index: int) {.closure.}

proc newMenu*(items: seq[MenuItem], style = defaultStyle(),
              selectedStyle = defaultStyle()): Menu =
  Menu(items: items, selected: if items.len > 0: 0 else: -1,
    style: style, selectedStyle: selectedStyle)

method measure*(widget: Menu, constraints: Constraints): Size =
  var width = 0
  for item in widget.items:
    width = max(width, item.label.len + 2 + item.description.len)
  constraints.clamp(size(width, widget.items.len))

method handle*(widget: Menu, event: UiEvent): EventResult =
  if event.kind != uiKey or widget.items.len == 0:
    return eventIgnored
  case event.key
  of keyUp:
    widget.selected = max(0, widget.selected - 1)
  of keyDown:
    widget.selected = min(widget.items.high, widget.selected + 1)
  of keyEnter:
    if not widget.onSelect.isNil:
      widget.onSelect(widget.selected)
  else:
    return eventIgnored
  eventHandled

method paint*(widget: Menu, canvas: var Canvas) =
  for i, item in widget.items:
    if i >= widget.area.h: break
    let style = if i == widget.selected: widget.selectedStyle else: widget.style
    canvas.writeText(widget.area.x, widget.area.y + i,
      " " & item.label & "  " & item.description, style, widget.area.w)
