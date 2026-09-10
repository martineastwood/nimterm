## Editable text input widget with UTF-8-safe cursor movement.

from std/unicode import Rune, fastRuneAt, isWhiteSpace
import ../canvas
import ../events
import ../geometry
import ../keys
import ../style
import ../widget
import ../text_width

type
  InputWidget* = ref object of Widget
    text*: string
    cursor*: int
    prefix*: string
    continuationPrefix*: string
    style*: Style
    cursorStyle*: Style
    cursorBarStyle*: Style
    paddingLeft*: int
    paddingRight*: int
    paddingTop*: int
    paddingBottom*: int
    scrollOffset*: int
    onChange*: proc (text: string) {.closure.}
    onSubmit*: proc (text: string) {.closure.}

  WrappedInputLine = object
    text: string
    sourceLine: int
    startColumn: int
    endColumn: int
    firstSegment: bool

proc defaultCursorStyle(): Style =
  result = defaultStyle()
  result.attributes.incl attrReverse

proc newInput*(prefix = "> ", continuationPrefix = "  ",
               style = defaultStyle(), cursorStyle = defaultCursorStyle(),
               cursorBarStyle = defaultCursorStyle()): InputWidget =
  InputWidget(prefix: prefix, continuationPrefix: continuationPrefix,
    style: style, cursorStyle: cursorStyle, cursorBarStyle: cursorBarStyle)

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

proc cursorLocation(text: string, cursor: int): tuple[line, column: int] =
  let stop = min(max(cursor, 0), text.len)
  var position = 0
  while position < stop:
    var next = position
    var rune: Rune
    fastRuneAt(text, next, rune)
    if next <= position: break
    if rune.int == 10:
      inc result.line
      result.column = 0
    else:
      result.column += rune.cellWidth
    position = next

proc byteAtColumn(text: string, column: int): int =
  result = 0
  var width = 0
  while result < text.len and width < max(0, column):
    var rune: Rune
    var next = result
    fastRuneAt(text, next, rune)
    if width + rune.cellWidth > column: break
    width += rune.cellWidth
    if next <= result: break
    result = next

proc inputLines(text: string): seq[string] =
  var line = ""
  for ch in text:
    if ch == '\n':
      result.add line
      line = ""
    else:
      line.add ch
  result.add line

proc lineStartByte(text: string, lineIndex: int): int =
  var line = 0
  var position = 0
  while position < text.len and line < lineIndex:
    if text[position] == '\n': inc line
    inc position
  position

proc lineEndByte(text: string, start: int): int =
  result = start
  while result < text.len and text[result] != '\n': inc result

proc wrappedInputLines(text: string, contentWidth: int,
                      prefix, continuationPrefix: string): seq[WrappedInputLine] =
  let width = max(1, contentWidth)
  var lineStart = 0
  var sourceLine = 0
  while true:
    let lineEnd = lineEndByte(text, lineStart)
    var position = lineStart
    var column = 0
    var firstSegment = true
    if position == lineEnd:
      result.add WrappedInputLine(sourceLine: sourceLine, firstSegment: true)
    while position < lineEnd:
      let segmentStart = position
      let segmentColumn = column
      let prefixWidth = if sourceLine == 0 and firstSegment:
        prefix.displayWidth else: continuationPrefix.displayWidth
      let segmentWidth = max(1, width - prefixWidth)
      var count = 0
      while position < lineEnd:
        var next = position
        var rune: Rune
        fastRuneAt(text, next, rune)
        let width = rune.cellWidth
        if count > 0 and count + width > segmentWidth: break
        position = next
        count += width
      result.add WrappedInputLine(text: text[segmentStart ..< position],
        sourceLine: sourceLine, startColumn: segmentColumn,
        endColumn: segmentColumn + count, firstSegment: firstSegment)
      column += count
      firstSegment = false
      if position == lineEnd and count == segmentWidth:
        result.add WrappedInputLine(sourceLine: sourceLine,
          startColumn: column, endColumn: column, firstSegment: false)
    if lineEnd >= text.len: break
    lineStart = lineEnd + 1
    inc sourceLine

proc visualLineCount*(widget: InputWidget, contentWidth: int): int =
  widget.text.wrappedInputLines(contentWidth, widget.prefix,
    widget.continuationPrefix).len

proc moveVertical(widget: InputWidget, delta: int) =
  let lines = widget.text.inputLines
  let current = cursorLocation(widget.text, widget.cursor)
  let target = clamp(current.line + delta, 0, lines.high)
  if target == current.line: return
  let start = lineStartByte(widget.text, target)
  let finish = lineEndByte(widget.text, start)
  let line = widget.text[start ..< finish]
  let column = min(current.column, line.displayWidth)
  widget.cursor = start + byteAtColumn(line, column)

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
  of keyUp:
    widget.moveVertical(-1)
  of keyDown:
    widget.moveVertical(1)
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
  for line in widget.text.inputLines:
    width = max(width, line.len)
    inc height
  constraints.clamp(size(width + widget.prefix.len + widget.paddingLeft +
    widget.paddingRight, max(1, height) + widget.paddingTop +
    widget.paddingBottom))

method paint*(widget: InputWidget, canvas: var Canvas) =
  for row in widget.area.y ..< widget.area.y + widget.area.h:
    for col in widget.area.x ..< widget.area.x + widget.area.w:
      canvas.setCell(col, row, Cell(glyph: Rune(32), style: widget.style))
  let contentX = widget.area.x + max(0, widget.paddingLeft)
  let contentWidth = max(0, widget.area.w - max(0, widget.paddingLeft) -
    max(0, widget.paddingRight))
  let lines = widget.text.wrappedInputLines(contentWidth, widget.prefix,
    widget.continuationPrefix)
  let cursor = cursorLocation(widget.text, widget.cursor)
  let contentY = widget.area.y + max(0, widget.paddingTop)
  let contentBottom = widget.area.y + widget.area.h - max(0, widget.paddingBottom)
  let visibleRows = max(1, contentBottom - contentY)
  var cursorVisualLine = -1
  var cursorVisualColumn = 0
  for i, line in lines:
    if line.sourceLine != cursor.line: continue
    let nextIsSameLine = i + 1 < lines.len and
      lines[i + 1].sourceLine == cursor.line
    if cursor.column >= line.startColumn and
        (cursor.column < line.endColumn or
         (cursor.column == line.endColumn and not nextIsSameLine)):
      cursorVisualLine = i
      cursorVisualColumn = cursor.column - line.startColumn
      break
  if cursorVisualLine < 0:
    cursorVisualLine = max(0, lines.len - 1)
  widget.scrollOffset = clamp(widget.scrollOffset, 0,
    max(0, lines.len - visibleRows))
  if cursorVisualLine < widget.scrollOffset:
    widget.scrollOffset = cursorVisualLine
  elif cursorVisualLine >= widget.scrollOffset + visibleRows:
    widget.scrollOffset = cursorVisualLine - visibleRows + 1
  for rowIndex in 0 ..< visibleRows:
    let lineIndex = widget.scrollOffset + rowIndex
    if lineIndex >= lines.len: break
    let line = lines[lineIndex]
    let prefix = if line.firstSegment and line.sourceLine == 0:
      widget.prefix else: widget.continuationPrefix
    let row = contentY + rowIndex
    if lineIndex != cursorVisualLine:
      canvas.writeText(contentX, row, prefix & line.text, widget.style,
        contentWidth)
      continue
    let cursorByte = byteAtColumn(line.text, cursorVisualColumn)
    let cursorX = contentX + prefix.displayWidth + cursorVisualColumn
    canvas.writeText(contentX, row, prefix & line.text[0 ..< cursorByte],
      widget.style, contentWidth)
    let cursorEnd = if cursorByte < line.text.len: nextPosition(line.text, cursorByte)
                    else: cursorByte
    let cursorText = if cursorByte < line.text.len:
      line.text[cursorByte ..< cursorEnd]
    else:
      "▌"
    let cursorPaintStyle = if cursorByte < line.text.len: widget.cursorStyle
                           else: widget.cursorBarStyle
    let cursorWidth = max(1, cursorText.displayWidth)
    canvas.writeText(cursorX, row, cursorText, cursorPaintStyle, cursorWidth)
    if cursorEnd < line.text.len:
      canvas.writeText(cursorX + cursorWidth, row, line.text[cursorEnd .. ^1],
        widget.style, max(0, contentX + contentWidth - cursorX - cursorWidth))
