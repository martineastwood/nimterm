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
    prefixStyle*: Style
    cursorStyle*: Style
    cursorBarStyle*: Style
    paddingLeft*: int
    paddingRight*: int
    paddingTop*: int
    paddingBottom*: int
    scrollOffset*: int
    wrappedLines: seq[WrappedInputLine]
    wrappedTextVersion: uint64
    wrappedWidth: int
    wrappedPrefix, wrappedContinuationPrefix: string
    wrappedValid: bool
    textVersion: uint64
    cursorCacheTextVersion: uint64
    cursorCachePosition: int
    cursorCache: tuple[line, column: int]
    cursorValid: bool
    undoStack: seq[tuple[text: string, cursor: int]]
    yankText*: string

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
               cursorBarStyle = defaultCursorStyle(),
               prefixStyle = defaultStyle()): InputWidget =
  let resolvedPrefixStyle = if prefixStyle == defaultStyle(): style else: prefixStyle
  InputWidget(prefix: prefix, continuationPrefix: continuationPrefix,
    style: style, prefixStyle: resolvedPrefixStyle,
    cursorStyle: cursorStyle, cursorBarStyle: cursorBarStyle)

proc invalidateTextLayout(widget: InputWidget) =
  inc widget.textVersion
  widget.wrappedValid = false
  widget.cursorValid = false

proc saveUndo(widget: InputWidget) =
  if widget.undoStack.len == 0 or widget.undoStack[^1].text != widget.text or
      widget.undoStack[^1].cursor != widget.cursor:
    widget.undoStack.add (widget.text, widget.cursor)
  if widget.undoStack.len > 100: widget.undoStack.delete(0)

proc replaceText(widget: InputWidget, text: string, cursor: int) =
  widget.text = text
  widget.cursor = min(max(cursor, 0), text.len)
  widget.invalidateTextLayout()

method focusable*(widget: InputWidget): bool = true

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

proc clear*(widget: InputWidget) =
  widget.replaceText("", 0)
  widget.undoStack.setLen(0)
  widget.yankText = ""

proc setText*(widget: InputWidget, text: string) =
  widget.replaceText(text, text.len)
  widget.undoStack.setLen(0)

proc insert*(widget: InputWidget, piece: string) =
  if piece.len == 0: return
  widget.saveUndo()
  let p = min(max(widget.cursor, 0), widget.text.len)
  widget.text = widget.text[0 ..< p] & piece & widget.text[p .. ^1]
  widget.cursor = p + piece.len
  widget.invalidateTextLayout()

proc deleteBefore(widget: InputWidget) =
  if widget.cursor == 0: return
  let start = previousPosition(widget.text, widget.cursor)
  widget.saveUndo()
  widget.yankText = widget.text[start ..< widget.cursor]
  widget.text = widget.text[0 ..< start] & widget.text[widget.cursor .. ^1]
  widget.cursor = start
  widget.invalidateTextLayout()

proc deleteAfter(widget: InputWidget) =
  if widget.cursor == widget.text.len: return
  let finish = nextPosition(widget.text, widget.cursor)
  widget.saveUndo()
  widget.yankText = widget.text[widget.cursor ..< finish]
  widget.text = widget.text[0 ..< widget.cursor] & widget.text[finish .. ^1]
  widget.invalidateTextLayout()

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

proc deleteWordBackward(widget: InputWidget) =
  let finish = widget.cursor
  if finish == 0: return
  widget.saveUndo()
  widget.wordBackward()
  let start = widget.cursor
  if start == finish: return
  widget.yankText = widget.text[start ..< finish]
  widget.replaceText(widget.text[0 ..< start] & widget.text[finish .. ^1], start)

proc deleteWordForward(widget: InputWidget) =
  let start = widget.cursor
  if start == widget.text.len: return
  widget.saveUndo()
  widget.wordForward()
  let finish = widget.cursor
  widget.yankText = widget.text[start ..< finish]
  widget.replaceText(widget.text[0 ..< start] & widget.text[finish .. ^1], start)

proc deleteToLineStart(widget: InputWidget) =
  var line = -1
  if widget.cursor > 0:
    for i in countdown(widget.cursor - 1, 0):
      if widget.text[i] == '\n':
        line = i
        break
  let start = if line < 0: 0 else: line + 1
  if start == widget.cursor: return
  widget.saveUndo()
  widget.yankText = widget.text[start ..< widget.cursor]
  widget.replaceText(widget.text[0 ..< start] & widget.text[widget.cursor .. ^1], start)

proc deleteToLineEnd(widget: InputWidget) =
  var finish = widget.cursor
  while finish < widget.text.len and widget.text[finish] != '\n': inc finish
  let stop = finish
  if stop == widget.cursor: return
  widget.saveUndo()
  widget.yankText = widget.text[widget.cursor ..< stop]
  widget.replaceText(widget.text[0 ..< widget.cursor] & widget.text[stop .. ^1], widget.cursor)

proc undo*(widget: InputWidget) =
  if widget.undoStack.len == 0: return
  let state = widget.undoStack.pop()
  widget.replaceText(state.text, state.cursor)

proc yank*(widget: InputWidget) =
  widget.insert(widget.yankText)

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

proc layoutLines(widget: InputWidget, contentWidth: int): seq[WrappedInputLine] =
  let width = max(1, contentWidth)
  if not widget.wrappedValid or widget.wrappedTextVersion != widget.textVersion or
      widget.wrappedWidth != width or widget.wrappedPrefix != widget.prefix or
      widget.wrappedContinuationPrefix != widget.continuationPrefix:
    widget.wrappedLines = widget.text.wrappedInputLines(width, widget.prefix,
      widget.continuationPrefix)
    widget.wrappedTextVersion = widget.textVersion
    widget.wrappedWidth = width
    widget.wrappedPrefix = widget.prefix
    widget.wrappedContinuationPrefix = widget.continuationPrefix
    widget.wrappedValid = true
  widget.wrappedLines

proc cachedCursorLocation(widget: InputWidget): tuple[line, column: int] =
  if not widget.cursorValid or widget.cursorCacheTextVersion != widget.textVersion or
      widget.cursorCachePosition != widget.cursor:
    widget.cursorCache = cursorLocation(widget.text, widget.cursor)
    widget.cursorCacheTextVersion = widget.textVersion
    widget.cursorCachePosition = widget.cursor
    widget.cursorValid = true
  widget.cursorCache

proc visualLineCount*(widget: InputWidget, contentWidth: int): int =
  widget.layoutLines(contentWidth).len

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

method handle*(widget: InputWidget, event: UiEvent): EventResponse =
  if event.kind == uiMouse and event.mouse == umPress and
      widget.area.contains(event.x, event.y):
    return focusHandled()
  if event.kind != uiKey: return eventIgnored
  case event.key
  of keyChar:
    widget.insert(event.text)
  of keyBackspace:
    widget.deleteBefore()
  of keyCtrlD:
    widget.deleteAfter()
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
  of keyCtrlW:
    widget.deleteWordBackward()
  of keyAltD:
    widget.deleteWordForward()
  of keyUp:
    widget.moveVertical(-1)
  of keyDown:
    widget.moveVertical(1)
  of keyHome, keyCtrlA:
    widget.cursor = 0
  of keyEnd, keyCtrlE:
    widget.cursor = widget.text.len
  of keyCtrlU:
    widget.deleteToLineStart()
  of keyCtrlK:
    widget.deleteToLineEnd()
  of keyCtrlY:
    widget.yank()
  of keyCtrlZ:
    widget.undo()
  of keyShiftEnter, keyAltJ:
    widget.insert("\n")
  of keyEnter:
    return widget.actionHandled("submit", widget.text)
  else:
    return eventIgnored
  widget.actionHandled("change", widget.text)

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
  let lines = widget.layoutLines(contentWidth)
  let cursor = widget.cachedCursorLocation()
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
    let prefixStyle = if line.firstSegment and line.sourceLine == 0:
      widget.prefixStyle else: widget.style
    let row = contentY + rowIndex
    if lineIndex != cursorVisualLine:
      let prefixWidth = prefix.displayWidth
      canvas.writeText(contentX, row, prefix, prefixStyle, contentWidth)
      canvas.writeText(contentX + prefixWidth, row, line.text, widget.style,
        max(0, contentWidth - prefixWidth))
      continue
    let cursorByte = byteAtColumn(line.text, cursorVisualColumn)
    let cursorX = contentX + prefix.displayWidth + cursorVisualColumn
    canvas.writeText(contentX, row, prefix, prefixStyle, contentWidth)
    canvas.writeText(contentX + prefix.displayWidth, row,
      line.text[0 ..< cursorByte], widget.style,
      max(0, contentWidth - prefix.displayWidth))
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
