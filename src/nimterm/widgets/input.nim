## Editable text input widget with UTF-8-safe cursor movement.

import std/strutils
from std/unicode import Rune, fastRuneAt, isWhiteSpace
import ../canvas
import ../events
import ../geometry
import ../keys
import ../style
import ../widget

type
  InputWidget* = ref object of Widget
    text*: string
    cursor*: int
    prefix*: string
    continuationPrefix*: string
    style*: Style
    onChange*: proc (text: string) {.closure.}
    onSubmit*: proc (text: string) {.closure.}

proc newInput*(prefix = "> ", continuationPrefix = "  ",
               style = defaultStyle()): InputWidget =
  InputWidget(prefix: prefix, continuationPrefix: continuationPrefix,
    style: style)

proc previousPosition(text: string, position: int): int =
  result = min(max(position, 0), text.len)
  if result == 0: return
  dec result
  while result > 0 and (uint8(text[result]) and 0xC0) == 0x80:
    dec result

proc nextPosition(text: string, position: int): int =
  result = min(max(position, 0), text.len)
  if result == text.len: return
  var rune: Rune
  fastRuneAt(text, result, rune)

proc changed(widget: InputWidget) =
  if not widget.onChange.isNil: widget.onChange(widget.text)

proc clear*(widget: InputWidget) =
  widget.text = ""
  widget.cursor = 0
  widget.changed()

proc setText*(widget: InputWidget, text: string) =
  widget.text = text
  widget.cursor = text.len
  widget.changed()

proc insert*(widget: InputWidget, piece: string) =
  if piece.len == 0: return
  let p = min(max(widget.cursor, 0), widget.text.len)
  widget.text = widget.text[0 ..< p] & piece & widget.text[p .. ^1]
  widget.cursor = p + piece.len
  widget.changed()

proc deleteBefore(widget: InputWidget) =
  if widget.cursor == 0: return
  let start = previousPosition(widget.text, widget.cursor)
  widget.text = widget.text[0 ..< start] & widget.text[widget.cursor .. ^1]
  widget.cursor = start
  widget.changed()

proc deleteAfter(widget: InputWidget) =
  if widget.cursor == widget.text.len: return
  let finish = nextPosition(widget.text, widget.cursor)
  widget.text = widget.text[0 ..< widget.cursor] & widget.text[finish .. ^1]
  widget.changed()

proc wordBackward(widget: InputWidget) =
  while widget.cursor > 0:
    let start = previousPosition(widget.text, widget.cursor)
    var rune: Rune
    var next = start
    fastRuneAt(widget.text, next, rune)
    if not rune.isWhiteSpace: break
    widget.cursor = start
  while widget.cursor > 0:
    let start = previousPosition(widget.text, widget.cursor)
    var rune: Rune
    var next = start
    fastRuneAt(widget.text, next, rune)
    if rune.isWhiteSpace: break
    widget.cursor = start

proc wordForward(widget: InputWidget) =
  while widget.cursor < widget.text.len:
    var rune: Rune
    var next = widget.cursor
    fastRuneAt(widget.text, next, rune)
    if not rune.isWhiteSpace: break
    widget.cursor = next
  while widget.cursor < widget.text.len:
    var rune: Rune
    var next = widget.cursor
    fastRuneAt(widget.text, next, rune)
    if rune.isWhiteSpace: break
    widget.cursor = next

method handle*(widget: InputWidget, event: UiEvent): EventResult =
  if event.kind != uiKey: return eventIgnored
  case event.key
  of keyChar:
    widget.insert(event.text)
  of keyBackspace:
    widget.deleteBefore()
  of keyDelete:
    widget.deleteAfter()
  of keyLeft, keyCtrlB:
    widget.cursor = previousPosition(widget.text, widget.cursor)
  of keyRight, keyCtrlF:
    widget.cursor = nextPosition(widget.text, widget.cursor)
  of keyAltB:
    widget.wordBackward()
  of keyAltF:
    widget.wordForward()
  of keyHome, keyCtrlA:
    widget.cursor = 0
  of keyEnd, keyCtrlE:
    widget.cursor = widget.text.len
  of keyCtrlU:
    widget.clear()
  of keyShiftEnter:
    widget.insert("\n")
  of keyEnter:
    if not widget.onSubmit.isNil: widget.onSubmit(widget.text)
  else:
    return eventIgnored
  eventHandled

method measure*(widget: InputWidget, constraints: Constraints): Size =
  var width = 0
  var height = 0
  for line in widget.text.splitLines:
    width = max(width, line.len)
    inc height
  constraints.clamp(size(width + widget.prefix.len, max(1, height)))

method paint*(widget: InputWidget, canvas: var Canvas) =
  let lines = widget.text.splitLines
  for i, line in lines:
    if widget.area.y + i >= widget.area.y + widget.area.h: break
    let prefix = if i == 0: widget.prefix else: widget.continuationPrefix
    canvas.writeText(widget.area.x, widget.area.y + i, prefix & line,
      widget.style, widget.area.w)
