## Multiple-choice question with an optional free-text answer.

import std/strutils
from std/unicode import Rune
import ../canvas
import ../events
import ../geometry
import ../keys
import ../style
import ../widget
import ./input

type
  QuestionOption* = object
    label*: string
    description*: string

  QuestionAnswer* = object
    selected*: int
    text*: string
    cancelled*: bool

  QuestionWidget* = ref object of Widget
    prompt*: string
    options*: seq[QuestionOption]
    selected*: int
    allowFreeText*: bool
    freeTextLabel*: string
    freeText*: InputWidget
    style*: Style
    selectedStyle*: Style
    descriptionStyle*: Style
    hintStyle*: Style
    resolved: bool

proc newQuestion*(prompt: string, options: seq[QuestionOption],
                  style = defaultStyle(), selectedStyle = defaultStyle(),
                  descriptionStyle = defaultStyle(), hintStyle = defaultStyle(),
                  allowFreeText = true, freeTextLabel = "Other"): QuestionWidget =
  let cursorStyle = style.withAttribute(attrReverse)
  result = QuestionWidget(prompt: prompt, options: options,
    selected: if options.len > 0: 0 else: (if allowFreeText: 0 else: -1),
    allowFreeText: allowFreeText, freeTextLabel: freeTextLabel, style: style,
    selectedStyle: selectedStyle, descriptionStyle: descriptionStyle,
    hintStyle: hintStyle, freeText: newInput(prefix = "  > ", style = style,
      cursorStyle = cursorStyle, cursorBarStyle = cursorStyle))

method focusable*(widget: QuestionWidget): bool = not widget.resolved
method modal*(widget: QuestionWidget): bool = not widget.resolved

method allowsBackgroundEvent*(widget: QuestionWidget, event: UiEvent): bool =
  (event.kind == uiKey and event.key in {keyPageUp, keyPageDown}) or
    (event.kind == uiMouse and event.scrollDelta != 0)

proc optionCount(widget: QuestionWidget): int =
  widget.options.len + (if widget.allowFreeText: 1 else: 0)

proc freeTextSelected(widget: QuestionWidget): bool =
  widget.allowFreeText and widget.selected == widget.options.len

proc answer*(widget: QuestionWidget): EventResponse =
  if widget.resolved or widget.selected < 0: return eventIgnored
  if widget.freeTextSelected and widget.freeText.text.strip.len == 0:
    return eventIgnored
  widget.resolved = true
  widget.actionHandled("answer",
    if widget.freeTextSelected: widget.freeText.text else:
      widget.options[widget.selected].label,
    if widget.freeTextSelected: -1 else: widget.selected)

proc cancel*(widget: QuestionWidget): EventResponse =
  if widget.resolved: return eventIgnored
  widget.resolved = true
  widget.actionHandled("answer", index = -1, cancelled = true)

proc moveSelection(widget: QuestionWidget, delta: int) =
  let count = widget.optionCount
  if count > 0:
    widget.selected = clamp(widget.selected + delta, 0, count - 1)

proc promptLines(widget: QuestionWidget): seq[string] =
  widget.prompt.splitLines

method handle*(widget: QuestionWidget, event: UiEvent): EventResponse =
  if widget.resolved: return eventIgnored
  if event.kind == uiMouse:
    if event.mouse != umPress or not widget.area.contains(event.x, event.y):
      return eventIgnored
    let index = event.y - widget.area.y - widget.promptLines.len - 1
    if index < 0 or index >= widget.optionCount: return eventIgnored
    widget.selected = index
    return focusHandled()
  if event.kind != uiKey: return eventIgnored
  if event.key == keyEscape:
    return widget.cancel()
  if event.key == keyUp:
    widget.moveSelection(-1)
    return eventHandled
  if event.key == keyDown:
    widget.moveSelection(1)
    return eventHandled
  if widget.freeTextSelected:
    case event.key
    of keyChar, keyBackspace, keyDelete, keyLeft, keyRight, keyHome, keyEnd,
       keyCtrlA, keyCtrlB, keyCtrlE, keyCtrlF, keyCtrlU, keyAltB, keyAltF,
       keyShiftEnter:
      discard widget.freeText.handle(event)
      return eventHandled
    of keyEnter:
      return widget.answer()
    else:
      discard
  elif event.key == keyEnter:
    return widget.answer()
  eventIgnored

method measure*(widget: QuestionWidget, constraints: Constraints): Size =
  var width = 0
  for line in widget.promptLines:
    width = max(width, line.len)
  for option in widget.options:
    width = max(width, option.label.len + 4 + option.description.len)
  if widget.allowFreeText:
    width = max(width, widget.freeTextLabel.len + 4)
  let height = widget.promptLines.len + 1 + widget.optionCount +
    (if widget.allowFreeText: 2 else: 0) + 1
  constraints.clamp(size(width, height))

method paint*(widget: QuestionWidget, canvas: var Canvas) =
  if widget.area.w <= 0 or widget.area.h <= 0: return
  for row in widget.area.y ..< widget.area.y + widget.area.h:
    for col in widget.area.x ..< widget.area.x + widget.area.w:
      canvas.setCell(col, row, Cell(glyph: Rune(32), style: widget.style))

  var row = widget.area.y
  for line in widget.promptLines:
    if row >= widget.area.y + widget.area.h: return
    canvas.writeText(widget.area.x, row, line, widget.selectedStyle,
      widget.area.w)
    inc row
  inc row
  for i, option in widget.options:
    if row >= widget.area.y + widget.area.h: return
    let selected = i == widget.selected
    let optionStyle = if selected: widget.selectedStyle else: widget.style
    let marker = if selected: "◉ " else: "○ "
    canvas.writeText(widget.area.x, row, marker & option.label, optionStyle,
      widget.area.w)
    if option.description.len > 0:
      let descX = widget.area.x + marker.len + option.label.len + 2
      canvas.writeText(descX, row, option.description,
        if selected: widget.selectedStyle else: widget.descriptionStyle,
        max(0, widget.area.x + widget.area.w - descX))
    inc row
  let hintRow = widget.area.y + widget.area.h - 1
  if widget.allowFreeText and row < hintRow:
    let selected = widget.freeTextSelected
    canvas.writeText(widget.area.x, row, (if selected: "◉ " else: "○ ") &
      widget.freeTextLabel, if selected: widget.selectedStyle else: widget.style,
      widget.area.w)
    inc row
    if selected and row < hintRow:
      widget.freeText.render(canvas, rect(widget.area.x, row, widget.area.w,
        hintRow - row))
  if hintRow >= row and hintRow < widget.area.y + widget.area.h:
    canvas.writeText(widget.area.x, hintRow,
      "↑↓ select  Enter submit  Esc cancel", widget.hintStyle, widget.area.w)
