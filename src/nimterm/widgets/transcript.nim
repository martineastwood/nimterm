## Compact transcript widget backed by nimterm's retained event reducer.

import std/strutils
from std/unicode import Rune
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
    scrollOffset*: int

  TranscriptLine = object
    text: string
    style: Style
    railStyle: Style

proc newTranscriptWidget*(transcript = transcript_model.newTranscript(),
                          userStyle = defaultStyle(),
                          assistantStyle = defaultStyle(),
                          thinkingStyle = defaultStyle(),
                          toolStyle = defaultStyle(),
                          errorStyle = defaultStyle()): TranscriptWidget =
  TranscriptWidget(transcript: transcript, userStyle: userStyle,
    assistantStyle: assistantStyle, thinkingStyle: thinkingStyle,
    toolStyle: toolStyle, errorStyle: errorStyle)

proc itemLines(item: transcript_model.TranscriptItem): seq[string] =
  case item.kind
  of tikUser:
    result.add "│ You"
    for line in item.text.splitLines: result.add "│ " & line
  of tikAssistant:
    result.add "│ " & (if item.model.len > 0: item.model else: "Assistant")
    for line in markdown_renderer.renderMarkdown(item.text, true).splitLines:
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
    if item.approvalRequired: result.add "│   [y] approve  [n] deny"
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

proc apply*(widget: TranscriptWidget, event: AgentUiEvent) =
  widget.transcript.apply(event)

proc awaitingApproval*(widget: TranscriptWidget): bool =
  for item in widget.transcript.items:
    if item.approvalRequired:
      return true

proc allLines(widget: TranscriptWidget): seq[TranscriptLine] =
  for item in widget.transcript.items:
    if result.len > 0:
      result.add TranscriptLine(style: defaultStyle(), railStyle: defaultStyle())
    let style = widget.itemStyle(item.kind)
    let railStyle = widget.itemRailStyle(item.kind)
    result.add TranscriptLine(text: "│", style: style, railStyle: railStyle)
    for line in item.itemLines:
      result.add TranscriptLine(text: line, style: style,
        railStyle: railStyle)
    result.add TranscriptLine(text: "│", style: style, railStyle: railStyle)

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
    of keyChar:
      for i in countdown(widget.transcript.items.high, 0):
        if not widget.transcript.items[i].approvalRequired: continue
        let allowed = event.text.toLowerAscii == "y"
        if not allowed and event.text.toLowerAscii != "n":
          return eventIgnored
        let callback = widget.transcript.items[i].approve
        if not callback.isNil: callback(allowed)
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
    if event.scrollDelta == 0: return eventIgnored
    widget.scrollBy(event.scrollDelta)
  else:
    return eventIgnored
  eventHandled

method measure*(widget: TranscriptWidget, constraints: Constraints): Size =
  var height = 0
  var width = 0
  for item in widget.transcript.items:
    for line in item.itemLines:
      width = max(width, ansiVisibleWidth(line))
      inc height
  constraints.clamp(size(width, height))

method paint*(widget: TranscriptWidget, canvas: var Canvas) =
  let lines = widget.allLines
  let start = max(0, lines.len - widget.area.h - widget.scrollOffset)
  var y = widget.area.y
  for i in start ..< lines.len:
    if y >= widget.area.y + widget.area.h: return
    for x in widget.area.x ..< widget.area.x + widget.area.w:
      canvas.setCell(x, y, Cell(glyph: Rune(32), style: lines[i].style))
    let line = lines[i]
    if line.text.startsWith("▌") or line.text.startsWith("│"):
      let railLen = if line.text.startsWith("▌"): "▌".len else: "│".len
      let rail = line.text[0 ..< railLen]
      let body = if line.text.len > railLen: line.text[railLen .. ^1] else: ""
      canvas.writeText(widget.area.x, y, rail, line.railStyle, 1)
      canvas.writeAnsiText(widget.area.x + 1, y, body, line.style,
        max(0, widget.area.w - 1))
    else:
      canvas.writeAnsiText(widget.area.x, y, line.text, line.style,
        widget.area.w)
    inc y
