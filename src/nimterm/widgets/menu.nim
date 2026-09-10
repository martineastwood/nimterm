## Selectable label/description menu.

import std/strutils
import ../canvas
import ../events
import ../geometry
import ../keys
import ../style
import ../widget
from std/unicode import Rune

type
  MenuItem* = object
    label*: string
    description*: string

  Menu* = ref object of Widget
    items*: seq[MenuItem]
    selected*: int
    scrollOffset*: int
    title*: string
    bordered*: bool
    style*: Style
    selectedStyle*: Style
    descriptionStyle*: Style
    selectedDescriptionStyle*: Style
    borderStyle*: Style
    titleStyle*: Style

proc newMenu*(items: seq[MenuItem], style = defaultStyle(),
              selectedStyle = defaultStyle(), title = "", bordered = false,
              borderStyle = defaultStyle(), titleStyle = defaultStyle(),
              descriptionStyle = defaultStyle(),
              selectedDescriptionStyle = defaultStyle()): Menu =
  Menu(items: items, selected: if items.len > 0: 0 else: -1,
    title: title, bordered: bordered, style: style, selectedStyle: selectedStyle,
    descriptionStyle: descriptionStyle,
    selectedDescriptionStyle: selectedDescriptionStyle,
    borderStyle: borderStyle, titleStyle: titleStyle)

method focusable*(widget: Menu): bool = widget.items.len > 0

method measure*(widget: Menu, constraints: Constraints): Size =
  var width = 0
  for item in widget.items:
    width = max(width, item.label.len + 4 + item.description.len)
  width = max(width, widget.title.len + 4)
  let border = if widget.bordered: 2 else: 0
  constraints.clamp(size(width + border, widget.items.len + border))

proc contentRows(widget: Menu): int =
  max(0, widget.area.h - (if widget.bordered: 2 else: 0))

proc keepSelectionVisible(widget: Menu, rows: int) =
  if rows <= 0 or widget.items.len == 0: return
  widget.scrollOffset = clamp(widget.scrollOffset, 0, max(0, widget.items.len - rows))
  if widget.selected < widget.scrollOffset:
    widget.scrollOffset = widget.selected
  elif widget.selected >= widget.scrollOffset + rows:
    widget.scrollOffset = widget.selected - rows + 1

proc moveSelection(widget: Menu, delta: int) =
  if widget.items.len == 0: return
  widget.selected = clamp(widget.selected + delta, 0, widget.items.high)
  widget.keepSelectionVisible(widget.contentRows)

method handle*(widget: Menu, event: UiEvent): EventResponse =
  if event.kind == uiMouse:
    if widget.items.len == 0: return eventIgnored
    if event.scrollDelta != 0:
      widget.moveSelection(if event.scrollDelta < 0: 3 else: -3)
      return eventHandled
    if event.mouse == umPress and widget.area.contains(event.x, event.y):
      let inset = if widget.bordered: 1 else: 0
      let index = widget.scrollOffset + event.y - widget.area.y - inset
      if index >= 0 and index < widget.items.len:
        widget.selected = index
        return widget.focusActionHandled("select", widget.items[index].label,
          index)
    return eventIgnored
  if event.kind != uiKey or widget.items.len == 0:
    return eventIgnored
  case event.key
  of keyUp:
    widget.moveSelection(-1)
  of keyDown:
    widget.moveSelection(1)
  of keyPageUp:
    widget.moveSelection(-max(1, widget.contentRows - 1))
  of keyPageDown:
    widget.moveSelection(max(1, widget.contentRows - 1))
  of keyEnter:
    return widget.actionHandled("select", widget.items[widget.selected].label,
      widget.selected)
  else:
    return eventIgnored
  eventHandled

method paint*(widget: Menu, canvas: var Canvas) =
  if widget.area.w <= 0 or widget.area.h <= 0: return
  let bordered = widget.bordered and widget.area.w >= 2 and widget.area.h >= 2
  let x = widget.area.x
  let y = widget.area.y
  let right = x + widget.area.w - 1
  let bottom = y + widget.area.h - 1
  if bordered:
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
      canvas.writeText(x + 2, y, " " & widget.title & " ", widget.titleStyle,
        max(0, widget.area.w - 4))

  let inset = if bordered: 1 else: 0
  let rows = max(0, widget.area.h - inset * 2)
  widget.keepSelectionVisible(rows)
  let labelWidth = block:
    var result = 0
    for item in widget.items: result = max(result, item.label.len)
    result
  for row in 0 ..< rows:
    let index = widget.scrollOffset + row
    let rowY = y + inset + row
    let baseStyle = if index == widget.selected: widget.selectedStyle else: widget.style
    for col in x + inset ..< x + widget.area.w - inset:
      canvas.setCell(col, rowY, Cell(glyph: Rune(32), style: baseStyle))
    if index >= widget.items.len: continue
    let item = widget.items[index]
    let marker = if index == widget.selected: "▸ " else: "  "
    let label = marker & item.label.alignLeft(labelWidth)
    canvas.writeText(x + inset, rowY, label, baseStyle,
      max(0, widget.area.w - inset * 2))
    if item.description.len > 0:
      let descX = x + inset + label.len + 2
      let descStyle = if index == widget.selected:
        widget.selectedDescriptionStyle
      else:
        widget.descriptionStyle
      canvas.writeText(descX, rowY, item.description, descStyle,
        max(0, x + widget.area.w - inset - descX))
