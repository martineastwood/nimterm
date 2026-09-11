## Compact transcript widget backed by nimterm's retained event reducer.

import std/[json, strutils]
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
import ./scroll

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
    viewport*: ScrollView
    selectionStart*: int
    selectionEnd*: int
    selectionStartCol*: int
    selectionEndCol*: int
    toolDetails*: proc (name: string, input: JsonNode,
                        output: string): seq[string] {.closure.}
    cachedWidth: int
    linesValid: bool
    itemCaches: seq[TranscriptItemCache]
    itemStarts: seq[int]
    totalLineCount: int

  TranscriptLine = object
    text: string
    style: Style
    railStyle: Style

  TranscriptItemCache = object
    revision: int
    width: int
    lines: seq[TranscriptLine]
    sourceRevision: int
    sourceLines: seq[string]
    streaming: bool
    streamKind: transcript_model.TranscriptItemKind
    streamModel: string
    streamTextLen: int
    streamRawLines: seq[string]
    streamTailRows: int

proc newTranscriptWidget*(transcript = transcript_model.newTranscript(),
                          userStyle = defaultStyle(),
                          assistantStyle = defaultStyle(),
                          thinkingStyle = defaultStyle(),
                          toolStyle = defaultStyle(),
                          errorStyle = defaultStyle()): TranscriptWidget =
  TranscriptWidget(transcript: transcript, userStyle: userStyle,
    assistantStyle: assistantStyle, thinkingStyle: thinkingStyle,
    toolStyle: toolStyle, errorStyle: errorStyle,
    viewport: newScrollView(), selectionStart: -1,
    selectionEnd: -1, selectionStartCol: -1, selectionEndCol: -1)

proc invalidateLines*(widget: TranscriptWidget) =
  widget.linesValid = false
  for cache in widget.itemCaches.mitems:
    cache.revision = -1
    cache.sourceRevision = -1

proc invalidateLayout(widget: TranscriptWidget) =
  widget.linesValid = false

proc appendUser*(widget: TranscriptWidget, text: string) =
  widget.transcript.appendUser(text)
  widget.invalidateLayout()

proc appendStatus*(widget: TranscriptWidget, text: string) =
  widget.transcript.items.add TranscriptItem(kind: tikStatus, text: text)
  widget.invalidateLayout()

proc setTranscript*(widget: TranscriptWidget,
                    transcript: transcript_model.Transcript) =
  widget.transcript = transcript
  widget.itemCaches.setLen(0)
  widget.itemStarts.setLen(0)
  widget.invalidateLines()

method focusable*(widget: TranscriptWidget): bool = true

proc itemLines(widget: TranscriptWidget,
               item: transcript_model.TranscriptItem): seq[string] =
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
    let details = if not item.pending and not item.isError and
        not widget.toolDetails.isNil:
      widget.toolDetails(item.title, item.toolInput, item.text)
    else: @[]
    if details.len > 0:
      let shownDetails = if item.expanded: details.len else: min(3, details.len)
      for i in 0 ..< shownDetails: result.add "│   " & details[i]
      if not item.expanded and details.len > shownDetails:
        result.add "│   … " & $(details.len - shownDetails) &
          " detail lines (Ctrl-O)"
    let lines = item.text.splitLines
    let shown = if item.expanded: lines.len else: min(2, lines.len)
    for i in 0 ..< shown: result.add "│   " & lines[i]
    if not item.expanded and lines.len > shown:
      result.add "│   … " & $(lines.len - shown) & " more (Ctrl-O)"
    if item.pending: result.add "│   working"
    if item.approvalRequired:
      for choice in item.approvalChoices:
        result.add "│   [" & choice.key & "] " & choice.label
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

proc wrapTranscriptLine(text: string, width: int): seq[string] =
  if width <= 0: return @[text]
  var prefix = ""
  if text.startsWith("│"):
    prefix = "│"
  elif text.startsWith("·"):
    prefix = "·"
  var prefixLen = prefix.len
  while prefixLen < text.len and text[prefixLen] == ' ':
    inc prefixLen
  prefix = if prefixLen > 0: text[0 ..< prefixLen] else: ""
  let body = if prefixLen < text.len: text[prefixLen .. ^1] else: ""
  for chunk in wrapAnsi(body, max(1, width - ansiVisibleWidth(prefix))):
    result.add prefix & chunk

proc apply*(widget: TranscriptWidget, event: AgentUiEvent) =
  widget.transcript.apply(event)
  widget.invalidateLayout()

proc awaitingApproval*(widget: TranscriptWidget): bool =
  for item in widget.transcript.items:
    if item.approvalRequired:
      return true

proc appendStreamingText(widget: TranscriptWidget,
                         item: transcript_model.TranscriptItem,
                         cache: var TranscriptItemCache) =
  if cache.streamTextLen > item.text.len: return
  let oldRawCount = cache.streamRawLines.len
  if oldRawCount > 0:
    if cache.lines.len > 0: cache.lines.setLen(cache.lines.len - 1)
    if cache.streamTailRows > 0:
      cache.lines.setLen(cache.lines.len - cache.streamTailRows)
  else:
    cache.streamRawLines.add ""
  if cache.streamTextLen < item.text.len:
    let delta = item.text[cache.streamTextLen .. ^1]
    var start = 0
    for i, ch in delta:
      if ch != '\n': continue
      cache.streamRawLines[^1].add delta[start ..< i]
      if cache.streamRawLines[^1].endsWith("\r"):
        cache.streamRawLines[^1].setLen(cache.streamRawLines[^1].len - 1)
      cache.streamRawLines.add ""
      start = i + 1
    if start < delta.len:
      cache.streamRawLines[^1].add delta[start .. ^1]
    cache.streamTextLen = item.text.len
  let first = max(0, oldRawCount - 1)
  for i in first ..< cache.streamRawLines.len:
    for wrapped in wrapTranscriptLine("│ " & cache.streamRawLines[i],
                                      widget.area.w):
      cache.lines.add TranscriptLine(text: wrapped,
        style: widget.itemStyle(item.kind),
        railStyle: widget.itemRailStyle(item.kind))
  cache.streamTailRows = 0
  if cache.streamRawLines.len > 0:
    cache.streamTailRows = wrapTranscriptLine(
      "│ " & cache.streamRawLines[^1], widget.area.w).len
  cache.lines.add TranscriptLine(text: "│",
    style: widget.itemStyle(item.kind), railStyle: widget.itemRailStyle(item.kind))

proc buildStreamingCache(widget: TranscriptWidget,
                         item: transcript_model.TranscriptItem,
                         cache: var TranscriptItemCache) =
  cache.lines.setLen(0)
  cache.lines.add TranscriptLine(text: "│",
    style: widget.itemStyle(item.kind), railStyle: widget.itemRailStyle(item.kind))
  let heading = if item.kind == transcript_model.tikAssistant:
    "│ " & (if item.model.len > 0: item.model else: "Assistant")
  else:
    "│ Thinking"
  for wrapped in wrapTranscriptLine(heading, widget.area.w):
    cache.lines.add TranscriptLine(text: wrapped,
      style: widget.itemStyle(item.kind),
      railStyle: widget.itemRailStyle(item.kind))
  cache.streaming = true
  cache.streamKind = item.kind
  cache.streamModel = item.model
  cache.streamTextLen = 0
  cache.streamRawLines.setLen(0)
  cache.streamTailRows = 0
  appendStreamingText(widget, item, cache)

proc rebuildStreamingWidth(widget: TranscriptWidget,
                           item: transcript_model.TranscriptItem,
                           cache: var TranscriptItemCache) =
  cache.lines.setLen(0)
  let style = widget.itemStyle(item.kind)
  let railStyle = widget.itemRailStyle(item.kind)
  cache.lines.add TranscriptLine(text: "│", style: style,
    railStyle: railStyle)
  let heading = if item.kind == transcript_model.tikAssistant:
    "│ " & (if item.model.len > 0: item.model else: "Assistant")
  else:
    "│ Thinking"
  for wrapped in wrapTranscriptLine(heading, widget.area.w):
    cache.lines.add TranscriptLine(text: wrapped, style: style,
      railStyle: railStyle)
  for raw in cache.streamRawLines:
    for wrapped in wrapTranscriptLine("│ " & raw, widget.area.w):
      cache.lines.add TranscriptLine(text: wrapped, style: style,
        railStyle: railStyle)
  cache.streamTailRows = if cache.streamRawLines.len == 0: 0 else:
    wrapTranscriptLine("│ " & cache.streamRawLines[^1], widget.area.w).len
  cache.lines.add TranscriptLine(text: "│", style: style,
    railStyle: railStyle)

proc ensureLayout(widget: TranscriptWidget) =
  if widget.linesValid and widget.cachedWidth == widget.area.w:
    return
  if widget.itemCaches.len != widget.transcript.items.len:
    widget.itemCaches.setLen(widget.transcript.items.len)
  widget.itemStarts.setLen(widget.transcript.items.len)
  var total = 0
  for i, item in widget.transcript.items:
    let cache = addr widget.itemCaches[i]
    if cache[].revision != item.revision or cache[].width != widget.area.w:
      let canStream = cache[].streaming and cache[].revision >= 0 and
        item.pending and
        item.kind in {transcript_model.tikAssistant,
                      transcript_model.tikThinking} and
        cache[].streamKind == item.kind and cache[].streamModel == item.model
      if canStream:
        if cache[].width == widget.area.w:
          appendStreamingText(widget, item, cache[])
        else:
          rebuildStreamingWidth(widget, item, cache[])
      else:
        cache[].lines.setLen(0)
        let style = widget.itemStyle(item.kind)
        let railStyle = widget.itemRailStyle(item.kind)
        cache[].lines.add TranscriptLine(text: "│", style: style,
          railStyle: railStyle)
        if cache[].sourceRevision != item.revision or cache[].sourceLines.len == 0:
          cache[].sourceLines = widget.itemLines(item)
          cache[].sourceRevision = item.revision
        for line in cache[].sourceLines:
          for wrapped in wrapTranscriptLine(line, widget.area.w):
            cache[].lines.add TranscriptLine(text: wrapped, style: style,
              railStyle: railStyle)
        cache[].lines.add TranscriptLine(text: "│", style: style,
          railStyle: railStyle)
        cache[].streaming = false
      cache[].revision = item.revision
      cache[].width = widget.area.w
    if i > 0: inc total
    widget.itemStarts[i] = total
    total += cache[].lines.len
  widget.totalLineCount = total
  widget.cachedWidth = widget.area.w
  widget.linesValid = true

proc lineCount(widget: TranscriptWidget): int =
  widget.ensureLayout()
  widget.totalLineCount

proc lineAt(widget: TranscriptWidget, index: int): TranscriptLine =
  widget.ensureLayout()
  if index < 0 or index >= widget.totalLineCount: return
  var lo = 0
  var hi = widget.itemStarts.high
  while lo <= hi:
    let mid = (lo + hi) div 2
    if widget.itemStarts[mid] <= index: lo = mid + 1
    else: hi = mid - 1
  if hi >= 0:
    let local = index - widget.itemStarts[hi]
    if local < widget.itemCaches[hi].lines.len:
      return widget.itemCaches[hi].lines[local]
  TranscriptLine(style: defaultStyle(), railStyle: defaultStyle())

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
  let count = widget.lineCount()
  if widget.selectionStart < 0 or widget.selectionEnd < 0 or count == 0:
    return ""
  let first = max(0, min(widget.selectionStart, widget.selectionEnd))
  let last = min(count - 1, max(widget.selectionStart, widget.selectionEnd))
  for i in first .. last:
    var line = stripAnsi(widget.lineAt(i).text)
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

proc copySelection*(widget: TranscriptWidget): EventResponse =
  let text = widget.selectedText()
  if text.len == 0: return eventIgnored
  widget.actionHandled("copy", text)

proc scrollBy*(widget: TranscriptWidget, delta: int) =
  widget.viewport.update(widget.lineCount(), widget.area.h)
  widget.viewport.scrollBy(-delta)

method handle*(widget: TranscriptWidget, event: UiEvent): EventResponse =
  widget.viewport.update(widget.lineCount(), widget.area.h)
  case event.kind
  of uiKey:
    case event.key
    of keyPageUp, keyCtrlB:
      widget.viewport.pageBy(-1)
    of keyPageDown, keyCtrlF:
      widget.viewport.pageBy(1)
    of keyHome:
      widget.viewport.home()
    of keyEnd:
      widget.viewport.tail()
    of keyChar, keyEnter:
      for i in countdown(widget.transcript.items.high, 0):
        if not widget.transcript.items[i].approvalRequired: continue
        let key = if event.key == keyEnter: "enter" else: event.text.toLowerAscii
        var selected = -1
        for j, choice in widget.transcript.items[i].approvalChoices:
          if choice.key.toLowerAscii == key: selected = j
        if selected < 0: return eventIgnored
        let choice = widget.transcript.items[i].approvalChoices[selected]
        widget.transcript.items[i].approvalRequired = false
        widget.invalidateLines()
        return widget.actionHandled("approval", choice.id,
          targetId = widget.transcript.items[i].id)
      return eventIgnored
    of keyEscape:
      for i in countdown(widget.transcript.items.high, 0):
        if not widget.transcript.items[i].approvalRequired: continue
        let choiceId = widget.transcript.items[i].cancelChoiceId
        widget.transcript.items[i].approvalRequired = false
        widget.invalidateLines()
        return widget.actionHandled("approval", choiceId,
          targetId = widget.transcript.items[i].id)
      return eventIgnored
    of keyCtrlO:
      var expandable = false
      var expand = false
      for item in widget.transcript.items:
        let details = if item.kind == tikTool and not item.isError and
            not widget.toolDetails.isNil:
          widget.toolDetails(item.title, item.toolInput, item.text)
        else: @[]
        if item.kind == tikTool and (item.text.splitLines.len > 2 or
            details.len > 2):
          expandable = true
          if not item.expanded: expand = true
      if not expandable: return eventIgnored
      for item in widget.transcript.items.mitems:
        let details = if item.kind == tikTool and not item.isError and
            not widget.toolDetails.isNil:
          widget.toolDetails(item.title, item.toolInput, item.text)
        else: @[]
        if item.kind == tikTool and (item.text.splitLines.len > 2 or
            details.len > 2):
          item.expanded = expand
      widget.invalidateLines()
      widget.viewport.update(widget.lineCount(), widget.area.h)
      return eventHandled
    else:
      return eventIgnored
  of uiMouse:
    if event.scrollDelta != 0:
      widget.scrollBy(event.scrollDelta)
      return eventHandled
    if not widget.area.contains(event.x, event.y): return eventIgnored
    let line = widget.viewport.offset + event.y - widget.area.y
    if line < 0 or line >= widget.lineCount(): return eventIgnored
    case event.mouse
    of umPress:
      widget.selectionStart = line
      widget.selectionEnd = line
      widget.selectionStartCol = clamp(event.x - widget.area.x, 0,
        max(0, widget.area.w - 1))
      widget.selectionEndCol = widget.selectionStartCol
      return captureHandled()
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
        let copy = widget.copySelection()
        result = releaseHandled()
        result.action = copy.action
        return
    else:
      discard
  else:
    return eventIgnored
  eventHandled

method measure*(widget: TranscriptWidget, constraints: Constraints): Size =
  var height = 0
  var width = 0
  for item in widget.transcript.items:
    for line in widget.itemLines(item):
      width = max(width, ansiVisibleWidth(line))
      inc height
  constraints.clamp(size(width, height))

method paint*(widget: TranscriptWidget, canvas: var Canvas) =
  let count = widget.lineCount()
  widget.viewport.update(count, widget.area.h)
  let start = widget.viewport.offset
  let stop = min(count, start + widget.area.h)
  if start >= stop: return
  var y = widget.area.y
  for i in start ..< stop:
    let line = widget.lineAt(i)
    let lineStyle = line.style
    let railStyle = line.railStyle
    for x in widget.area.x ..< widget.area.x + widget.area.w:
      canvas.setCell(x, y, Cell(glyph: Rune(32), style: lineStyle))
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
