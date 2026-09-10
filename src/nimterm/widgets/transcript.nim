## Compact transcript widget backed by nimterm's retained event reducer.

import std/strutils
from std/unicode import Rune, fastRuneAt, runeLenAt
import ../canvas
import ../ansi
import ../events
import ../geometry
import ../keys
import ../markdown as markdown_renderer
import ../style
import ../transcript as transcript_model
import ../widget

type
  TranscriptWidget* = ref object of Widget
    transcript*: transcript_model.Transcript
    userStyle*: Style
    assistantStyle*: Style
    thinkingStyle*: Style
    toolStyle*: Style
    errorStyle*: Style
    userRailStyle*: Style
    assistantRailStyle*: Style
    thinkingRailStyle*: Style
    toolRailStyle*: Style
    errorRailStyle*: Style
    selectionStyle*: Style
    scrollOffset*: int
    selectionStart*: int
    selectionEnd*: int
    selectionStartCol*: int
    selectionEndCol*: int
    onCopy*: proc (text: string) {.closure.}
    lineCache: seq[CachedItemLines]

  TranscriptLine = object
    text: string
    style: Style
    railStyle: Style

  CachedItemLines = object
    id: string
    kind: TranscriptItemKind
    textLen: int
    title: string
    model: string
    pending: bool
    isError: bool
    expanded: bool
    approvalRequired: bool
    lines: seq[string]

proc newTranscriptWidget*(transcript = transcript_model.newTranscript(),
                          userStyle = defaultStyle(),
                          assistantStyle = defaultStyle(),
                          thinkingStyle = defaultStyle(),
                          toolStyle = defaultStyle(),
                          errorStyle = defaultStyle()): TranscriptWidget =
  TranscriptWidget(transcript: transcript, userStyle: userStyle,
    assistantStyle: assistantStyle, thinkingStyle: thinkingStyle,
    toolStyle: toolStyle, errorStyle: errorStyle, selectionStart: -1,
    selectionEnd: -1, selectionStartCol: -1, selectionEndCol: -1)

proc itemLines(item: transcript_model.TranscriptItem): seq[string] =
  case item.kind
  of tikUser:
    result.add "│ You"
    for line in item.text.splitLines: result.add "│ " & line
  of tikAssistant:
    result.add "│ " & (if item.model.len > 0: item.model else: "Assistant")
    let text = if item.pending: item.text else:
      markdown_renderer.renderMarkdown(item.text, true)
    for line in text.splitLines:
      result.add "│ " & line
  of tikThinking:
    result.add "│ Thinking"
    for line in item.text.splitLines: result.add "│ " & line
  of tikTool:
    result.add "│ " & (if item.isError: "✗ " else: "● ") & item.title
    let lines = item.text.splitLines
    let shown = if item.expanded: lines.len else: min(2, lines.len)
    for i in 0 ..< shown: result.add "│   " & lines[i]
    if not item.expanded and lines.len > shown:
      result.add "│   … " & $(lines.len - shown) & " more (Ctrl-O)"
    if item.pending: result.add "│   working"
    if item.approvalRequired:
      result.add "│   [Enter] once"
      if not item.rememberSession.isNil: result.add "  [s] session"
      if not item.rememberProject.isNil: result.add "  [p] project"
      result.add "  [n] deny"
  of tikError:
    for line in item.text.splitLines: result.add "│ " & line
  of tikStatus:
    for line in item.text.splitLines: result.add "· " & line

proc itemStyle(widget: TranscriptWidget, kind: TranscriptItemKind): Style =
  case kind
  of tikUser: widget.userStyle
  of tikAssistant: widget.assistantStyle
  of tikThinking: widget.thinkingStyle
  of tikTool: widget.toolStyle
  of tikError: widget.errorStyle
  of tikStatus: widget.thinkingStyle

proc itemRailStyle(widget: TranscriptWidget, kind: TranscriptItemKind): Style =
  case kind
  of tikUser: widget.userRailStyle
  of tikAssistant: widget.assistantRailStyle
  of tikThinking: widget.thinkingRailStyle
  of tikTool: widget.toolRailStyle
  of tikError: widget.errorRailStyle
  of tikStatus: widget.thinkingRailStyle

proc cacheMatches(cache: CachedItemLines,
                  item: transcript_model.TranscriptItem): bool =
  cache.id == item.id and cache.kind == item.kind and
    cache.textLen == item.text.len and cache.title == item.title and
    cache.model == item.model and cache.pending == item.pending and
    cache.isError == item.isError and cache.expanded == item.expanded and
    cache.approvalRequired == item.approvalRequired

proc cachedItemLines(widget: TranscriptWidget, index: int,
                     item: transcript_model.TranscriptItem): seq[string] =
  if index < widget.lineCache.len and widget.lineCache[index].cacheMatches(item):
    return widget.lineCache[index].lines
  let lines = item.itemLines
  if index >= widget.lineCache.len:
    widget.lineCache.setLen(index + 1)
  widget.lineCache[index] = CachedItemLines(id: item.id, kind: item.kind,
    textLen: item.text.len, title: item.title, model: item.model,
    pending: item.pending, isError: item.isError, expanded: item.expanded,
    approvalRequired: item.approvalRequired, lines: lines)
  lines

proc apply*(widget: TranscriptWidget, event: AgentUiEvent) =
  widget.transcript.apply(event)

proc awaitingApproval*(widget: TranscriptWidget): bool =
  for item in widget.transcript.items:
    if item.approvalRequired:
      return true

proc allLines(widget: TranscriptWidget): seq[TranscriptLine] =
  for index, item in widget.transcript.items:
    if result.len > 0:
      result.add TranscriptLine(style: defaultStyle(), railStyle: defaultStyle())
    let style = widget.itemStyle(item.kind)
    let railStyle = widget.itemRailStyle(item.kind)
    result.add TranscriptLine(text: "│", style: style, railStyle: railStyle)
    for line in widget.cachedItemLines(index, item):
      result.add TranscriptLine(text: line, style: style,
        railStyle: railStyle)
    result.add TranscriptLine(text: "│", style: style, railStyle: railStyle)

proc visibleStart(widget: TranscriptWidget): int =
  max(0, widget.allLines.len - widget.area.h - widget.scrollOffset)

proc selectionColumns(widget: TranscriptWidget, line: int): tuple[lo, hi: int] =
  result = (-1, -1)
  if widget.selectionStart < 0 or widget.selectionEnd < 0: return
  let startLine = widget.selectionStart
  let endLine = widget.selectionEnd
  let startCol = widget.selectionStartCol
  let endCol = widget.selectionEndCol
  if startLine == endLine:
    if line == startLine: result = (min(startCol, endCol), max(startCol, endCol))
  elif startLine < endLine:
    if line == startLine: result = (startCol, widget.area.w - 1)
    elif line == endLine: result = (0, endCol)
    elif line > startLine and line < endLine: result = (0, widget.area.w - 1)
  elif line == startLine:
    result = (startCol, widget.area.w - 1)
  elif line == endLine:
    result = (0, endCol)
  elif line < startLine and line > endLine:
    result = (0, widget.area.w - 1)

proc runeSlice(text: string, first, last: int): string =
  if first > last: return
  var i = 0
  var column = 0
  while i < text.len:
    var rune: Rune
    fastRuneAt(text, i, rune, doInc = false)
    let width = runeLenAt(text, i)
    if column >= first and column <= last:
      let stop = min(text.len, i + width)
      if stop > i: result.add text[i ..< stop]
    i = min(text.len, i + width)
    inc column

proc lineSelected(widget: TranscriptWidget, index: int): bool =
  let bounds = widget.selectionColumns(index)
  bounds.lo >= 0

proc selectedText*(widget: TranscriptWidget): string =
  let lines = widget.allLines
  if widget.selectionStart < 0 or widget.selectionEnd < 0 or lines.len == 0:
    return ""
  let first = max(0, min(widget.selectionStart, widget.selectionEnd))
  let last = min(lines.high, max(widget.selectionStart, widget.selectionEnd))
  for i in first .. last:
    var line = stripAnsi(lines[i].text)
    var prefixColumns = 0
    let railPrefix = "│ "
    let statusPrefix = "· "
    if line.startsWith(railPrefix):
      line = if line.len > railPrefix.len: line[railPrefix.len .. ^1] else: ""
      prefixColumns = 2
    elif line == "│":
      line = ""
      prefixColumns = 1
    elif line.startsWith(statusPrefix):
      line = if line.len > statusPrefix.len: line[statusPrefix.len .. ^1] else: ""
      prefixColumns = 2
    let bounds = widget.selectionColumns(i)
    let firstColumn = max(0, bounds.lo - prefixColumns)
    let lastColumn = bounds.hi - prefixColumns
    let selected = runeSlice(line, firstColumn, lastColumn)
    if selected.len == 0: continue
    if result.len > 0: result.add '\n'
    result.add selected

proc copySelection*(widget: TranscriptWidget): bool =
  let text = widget.selectedText()
  if text.len == 0 or widget.onCopy.isNil: return false
  widget.onCopy(text)
  true

proc maxScroll(widget: TranscriptWidget): int =
  max(0, widget.allLines.len - widget.area.h)

proc scrollBy*(widget: TranscriptWidget, delta: int) =
  widget.scrollOffset = clamp(widget.scrollOffset + delta, 0,
    widget.maxScroll)

method handle*(widget: TranscriptWidget, event: UiEvent): EventResult =
  case event.kind
  of uiKey:
    case event.key
    of keyPageUp, keyCtrlB:
      widget.scrollBy(max(1, widget.area.h div 2))
    of keyPageDown, keyCtrlF:
      widget.scrollBy(-max(1, widget.area.h div 2))
    of keyChar, keyEnter:
      for i in countdown(widget.transcript.items.high, 0):
        if not widget.transcript.items[i].approvalRequired: continue
        let choice = if event.key == keyEnter: "y" else: event.text.toLowerAscii
        if choice notin ["y", "n", "s", "p"]:
          return eventIgnored
        if choice == "s":
          if widget.transcript.items[i].rememberSession.isNil: return eventIgnored
          widget.transcript.items[i].rememberSession()
        elif choice == "p":
          if widget.transcript.items[i].rememberProject.isNil: return eventIgnored
          widget.transcript.items[i].rememberProject()
        let callback = widget.transcript.items[i].approve
        if not callback.isNil: callback(choice != "n")
        widget.transcript.items[i].approvalRequired = false
        return eventHandled
      return eventIgnored
    of keyEscape:
      for i in countdown(widget.transcript.items.high, 0):
        if not widget.transcript.items[i].approvalRequired: continue
        let callback = widget.transcript.items[i].approve
        if not callback.isNil: callback(false)
        widget.transcript.items[i].approvalRequired = false
        return eventHandled
      return eventIgnored
    of keyCtrlO:
      var expandable = false
      var expand = false
      for item in widget.transcript.items:
        if item.kind == tikTool and item.text.splitLines.len > 2:
          expandable = true
          if not item.expanded: expand = true
      if not expandable: return eventIgnored
      for item in widget.transcript.items.mitems:
        if item.kind == tikTool and item.text.splitLines.len > 2:
          item.expanded = expand
      widget.scrollOffset = 0
      return eventHandled
    else:
      return eventIgnored
  of uiMouse:
    if event.scrollDelta != 0:
      widget.scrollBy(event.scrollDelta)
      return eventHandled
    if not widget.area.contains(event.x, event.y): return eventIgnored
    let line = widget.visibleStart + event.y - widget.area.y
    if line < 0 or line >= widget.allLines.len: return eventIgnored
    case event.mouse
    of umPress:
      widget.selectionStart = line
      widget.selectionEnd = line
      widget.selectionStartCol = clamp(event.x - widget.area.x, 0,
        max(0, widget.area.w - 1))
      widget.selectionEndCol = widget.selectionStartCol
      return eventHandled
    of umDrag:
      if widget.selectionStart >= 0:
        widget.selectionEnd = line
        widget.selectionEndCol = clamp(event.x - widget.area.x, 0,
          max(0, widget.area.w - 1))
        return eventHandled
    of umRelease:
      if widget.selectionStart >= 0:
        widget.selectionEnd = line
        widget.selectionEndCol = clamp(event.x - widget.area.x, 0,
          max(0, widget.area.w - 1))
        discard widget.copySelection()
        return eventHandled
    else:
      discard
  else:
    return eventIgnored
  eventHandled

method measure*(widget: TranscriptWidget, constraints: Constraints): Size =
  var height = 0
  var width = 0
  for index, item in widget.transcript.items:
    for line in widget.cachedItemLines(index, item):
      width = max(width, ansiVisibleWidth(line))
      inc height
  constraints.clamp(size(width, height))

method paint*(widget: TranscriptWidget, canvas: var Canvas) =
  let lines = widget.allLines
  let start = max(0, lines.len - widget.area.h - widget.scrollOffset)
  var y = widget.area.y
  for i in start ..< lines.len:
    if y >= widget.area.y + widget.area.h: return
    let lineStyle = lines[i].style
    let railStyle = lines[i].railStyle
    for x in widget.area.x ..< widget.area.x + widget.area.w:
      canvas.setCell(x, y, Cell(glyph: Rune(32), style: lineStyle))
    let line = lines[i]
    if line.text.startsWith("▌") or line.text.startsWith("│"):
      let railLen = if line.text.startsWith("▌"): "▌".len else: "│".len
      let rail = line.text[0 ..< railLen]
      let body = if line.text.len > railLen: line.text[railLen .. ^1] else: ""
      canvas.writeText(widget.area.x, y, rail, railStyle, 1)
      canvas.writeAnsiText(widget.area.x + 1, y, body, lineStyle,
        max(0, widget.area.w - 1))
    else:
      canvas.writeAnsiText(widget.area.x, y, line.text, lineStyle,
        widget.area.w)
    let bounds = widget.selectionColumns(i)
    if bounds.lo >= 0:
      for x in max(0, bounds.lo) .. min(widget.area.w - 1, bounds.hi):
        var cell = canvas.getCell(widget.area.x + x, y)
        cell.style = widget.selectionStyle
        canvas.setCell(widget.area.x + x, y, cell)
    inc y
