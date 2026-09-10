import std/[json, strutils, unittest]
import nimterm/[ansi, app, backend, canvas, events, geometry, input, markdown, keys,
  style, text_width, theme, transcript, widget, widgets]
import nimterm/term
when not defined(windows):
  import nimterm/platform_posix

proc decodeBytes(bytes: string): InputEvent =
  var index = 1
  proc nextByte(timeoutMs: int): int =
    discard timeoutMs
    if index >= bytes.len: return -1
    result = bytes[index].ord
    inc index
  decodeInput(if bytes.len == 0: -1 else: bytes[0].ord, nextByte)

suite "terminal input decoding":
  test "distinguishes escape from complete and partial control sequences":
    check decodeBytes("\e").key == keyEscape
    check decodeBytes("\e[A").key == keyUp
    check decodeBytes("\e[").key == keyNone

  test "normalizes modified key encodings":
    check decodeBytes("\e[118;5u").key == keyCtrlV
    check decodeBytes("\e[99;6u").key == keyCopy
    check decodeBytes("\e[111;5u").key == keyCtrlO
    check decodeBytes("\e[13;2u").key == keyShiftEnter

  test "decodes bracketed paste as one normalized text event":
    let event = decodeBytes("\e[200~one\r\ntwo\rthree\e[201~")
    check event.key == keyChar
    check event.text == "one\ntwo\nthree"

  test "decodes SGR mouse press drag release and wheel":
    let press = decodeBytes("\e[<0;3;4M")
    check press.mouse == mousePress
    check (press.mouseX, press.mouseY) == (2, 3)
    check decodeBytes("\e[<32;3;4M").mouse == mouseDrag
    check decodeBytes("\e[<0;3;4m").mouse == mouseRelease
    check decodeBytes("\e[<65;3;4M").scrollDelta == -3

  test "keeps UTF-8 bytes together and tolerates an incomplete rune":
    check decodeBytes("界").text == "界"
    check decodeBytes("\xE7\x95").text == "\xE7\x95"

  test "decodes terminal focus reports":
    check decodeBytes("\e[I").focus == focusIn
    check decodeBytes("\e[O").focus == focusOut

  test "enables only declared terminal protocols":
    let basic = TerminalCapabilities(bracketedPaste: true, focusEvents: true)
    check enableProtocols(basic) == "\e[?1004h\e[?2004h"
    check disableProtocols(basic) == "\e[?2004l\e[?1004l"
    let kitty = TerminalCapabilities(modifyOtherKeys: true, kittyKeyboard: true)
    check enableProtocols(kitty) == "\e[>1u"
    check disableProtocols(kitty) == "\e[<u"

suite "ansi text":
  test "visible width ignores escapes":
    check ansiVisibleWidth("\e[31mred\e[0m") == 3
    check stripAnsi("\e[31mred\e[0m") == "red"

  test "display width follows terminal columns":
    check displayWidth("界") == 2
    check displayWidth("e\u0301") == 1
    check ansiVisibleWidth("\e[31m界\e[0m") == 2

suite "markdown":
  test "renders common inline markup without color":
    let rendered = renderMarkdown("## Heading\n\n**bold** and `code`", false)
    check "Heading" in rendered
    check "bold" in rendered
    check "code" in rendered
    check "strike" in renderMarkdown("~~strike~~", false)
    check "\e" notin rendered

  test "renders themed markdown into semantic cells":
    let base = defaultStyle().withBackground(ansi256(236))
    var canvas = newCanvas(size(40, 3))
    canvas.writeAnsiText(0, 0, renderMarkdown("## Heading", true), base, 40)
    check canvas.getCell(0, 0).style.foreground.kind != colorDefault
    canvas.clear()
    canvas.writeAnsiText(0, 0, renderMarkdown("`code`", true), base, 40)
    check canvas.getCell(0, 0).style.foreground.kind != colorDefault
    canvas.clear()
    canvas.writeAnsiText(0, 0, renderMarkdown("~~strike~~", true), base, 40)
    check attrStrikethrough in canvas.getCell(0, 0).style.attributes
    canvas.clear()
    let code = renderMarkdown("```nim\nlet answer = 42\n```", true).splitLines
    canvas.writeAnsiText(0, 1, code[0], base, 40)
    check attrDim in canvas.getCell(0, 1).style.attributes

suite "themes":
  test "compiles built-in themes":
    let compiled = compileNamedTheme("dark", cd256)
    check compiled.ok
    check compiled.theme.accent == Dark256.accent

  test "parses a complete custom theme":
    let doc = %*{
      "name": "custom",
      "colors": {
        "accent": "#00ffff", "success": "#00ff00", "error": "#ff0000",
        "warning": "#ffff00", "muted": 242, "dim": "dim", "text": "#fff",
        "heading": "#fff", "model": "#f0f", "panelBg": "#000000",
        "selectedBg": "#ffffff", "selectedFg": "#000000"
      }
    }
    check parseThemeJson(doc).ok

type
  FakeBackend = ref object of TerminalBackend
    presented: Canvas
    events: seq[UiEvent]

method size(backend: FakeBackend): Size = size(12, 4)

method readEvent(backend: FakeBackend, timeoutMs: int): UiEvent =
  discard timeoutMs
  if backend.events.len == 0:
    return UiEvent(kind: uiNone)
  result = backend.events[0]
  backend.events.delete(0)

method present(backend: FakeBackend, frame: Canvas) =
  backend.presented = frame

type FakeSource = ref object of EventSource
  events: seq[UiEvent]
  closed: bool

method poll(source: FakeSource): seq[UiEvent] =
  result = source.events
  source.events.setLen(0)

method close(source: FakeSource) = source.closed = true

type Probe = ref object of Widget
  kids: seq[Widget]
  canFocus: bool
  handleKeys: bool
  handleMouse: bool
  capturePress: bool
  modalFlag: bool
  hidden: bool
  disabled: bool
  keysSeen: int
  mouseSeen: int

method children(widget: Probe): seq[Widget] = widget.kids
method focusable(widget: Probe): bool = widget.canFocus
method visible(widget: Probe): bool = not widget.hidden
method enabled(widget: Probe): bool = not widget.disabled
method modal(widget: Probe): bool = widget.modalFlag
method handle(widget: Probe, event: UiEvent): EventResponse =
  if event.kind == uiKey:
    inc widget.keysSeen
    return if widget.handleKeys: eventHandled else: eventIgnored
  if event.kind == uiMouse:
    inc widget.mouseSeen
    if event.mouse == umPress and widget.capturePress: return captureHandled()
    return if widget.handleMouse: eventHandled else: eventIgnored
  eventIgnored
method paint(widget: Probe, canvas: var Canvas) =
  for child in widget.kids: child.render(canvas, widget.area)

suite "core canvas and app":
  test "constructs the POSIX backend without entering raw mode":
    check not newPosixBackend().isNil

  test "canvas writes text into a stable snapshot":
    var canvas = newCanvas(size(8, 2))
    canvas.writeText(1, 0, "hi")
    check canvas.plainText == " hi     \n        "

  test "canvas reserves wide cells and joins combining marks":
    var canvas = newCanvas(size(4, 1))
    canvas.writeText(0, 0, "界e\u0301")
    check canvas.getCell(1, 0).continuation
    check canvas.getCell(2, 0).combining.len > 0

  test "run drains and closes event sources":
    let source = FakeSource(events: @[quitEvent()])
    var app = newApp(FakeBackend())
    app.addSource(source)
    app.run()
    check source.closed

  test "event sources and timers enter the normal dispatch queue":
    let source = FakeSource(events: @[UiEvent(kind: uiAgent,
      agent: AgentUiEvent(kind: ueTextDelta, text: "source"))])
    var app = newApp(FakeBackend())
    app.addSource(source)
    app.schedule("tick", 0)
    var seen: seq[string]
    app.onEvent = proc (_: var App, event: UiEvent): EventResponse =
      if event.kind == uiAgent: seen.add event.agent.text
      if event.kind == uiTimer: seen.add event.timerId
      eventIgnored
    check app.step()
    check app.step()
    check seen == @["source", "tick"]

  test "app dispatches agent events and presents a frame":
    let backend = FakeBackend(events: @[agentEvent(AgentUiEvent(
      kind: ueTextDelta, text: "hello"))])
    var app = newApp(backend, newText("ready"))
    var seen = ""
    app.onEvent = proc (_: var App, event: UiEvent): EventResponse =
      if event.kind == uiAgent:
        seen = event.agent.text
      eventIgnored
    check app.step()
    check seen == "hello"
    check backend.presented.plainText.startsWith("ready")

  test "app delivers inert widget actions to its controller":
    let input = newInput()
    input.id = "composer"
    input.setText("hello")
    var app = newApp(FakeBackend(), input)
    var received: UiAction
    app.onAction = proc (_: var App, action: UiAction) = received = action
    app.render()
    app.focus(input)
    app.dispatch(UiEvent(kind: uiKey, key: keyEnter))
    check received.sourceId == "composer"
    check received.kind == "submit"
    check received.value == "hello"

  test "keyboard events bubble from focus and Tab moves focus":
    let child = Probe(canFocus: true)
    let sibling = Probe(canFocus: true)
    let root = Probe(kids: @[Widget(child), Widget(sibling)], handleKeys: true)
    var app = newApp(FakeBackend(), root)
    app.render()
    app.focus(child)
    app.dispatch(UiEvent(kind: uiKey, key: keyChar, text: "x"))
    check child.keysSeen == 1
    check root.keysSeen == 1
    root.handleKeys = false
    app.dispatch(UiEvent(kind: uiKey, key: keyTab))
    check app.focus == sibling

  test "mouse uses reverse paint order and captures a drag":
    let lower = Probe(canFocus: true, handleMouse: true)
    let upper = Probe(canFocus: true, handleMouse: true, capturePress: true)
    let root = Probe(kids: @[Widget(lower), Widget(upper)])
    var app = newApp(FakeBackend(), root)
    app.render()
    app.dispatch(UiEvent(kind: uiMouse, mouse: umPress, x: 1, y: 1))
    check upper.mouseSeen == 1
    check lower.mouseSeen == 0
    check app.focus == upper
    app.dispatch(UiEvent(kind: uiMouse, mouse: umDrag, x: 50, y: 50))
    check upper.mouseSeen == 2
    app.dispatch(UiEvent(kind: uiMouse, mouse: umRelease, x: 50, y: 50))
    check app.mouseCapture.isNil

  test "modal widgets constrain keyboard routing and focus":
    let background = Probe(canFocus: true, handleKeys: true)
    let dialog = Probe(canFocus: true, handleKeys: true, modalFlag: true)
    let root = Probe(kids: @[Widget(background), Widget(dialog)])
    var app = newApp(FakeBackend(), root)
    app.render()
    app.focus(background)
    app.dispatch(UiEvent(kind: uiKey, key: keyEnter))
    check app.focus.isNil
    check background.keysSeen == 0
    check dialog.keysSeen == 1

  test "disabled widgets are skipped by focus traversal":
    let disabled = Probe(canFocus: true, disabled: true)
    let enabled = Probe(canFocus: true)
    let root = Probe(kids: @[Widget(disabled), Widget(enabled)])
    var app = newApp(FakeBackend(), root)
    app.render()
    app.dispatch(UiEvent(kind: uiKey, key: keyTab))
    check app.focus == enabled

  test "menu emits selection actions":
    let menu = newMenu(@[
      MenuItem(label: "one", description: "first"),
      MenuItem(label: "two", description: "second")])
    discard menu.handle(UiEvent(kind: uiKey, key: keyDown))
    let response = menu.handle(UiEvent(kind: uiKey, key: keyEnter))
    check response.action.kind == "select"
    check response.action.index == 1

  test "menu keeps the selected row inside a bounded popup":
    var items: seq[MenuItem]
    for i in 0 ..< 10:
      items.add MenuItem(label: "item-" & $i, description: "description")
    let menu = newMenu(items, bordered = true)
    var canvas = newCanvas(size(30, 5))
    menu.render(canvas, rect(0, 0, 30, 5))
    for _ in 0 ..< 8:
      discard menu.handle(UiEvent(kind: uiKey, key: keyDown))
    canvas.clear()
    menu.render(canvas, rect(0, 0, 30, 5))
    check menu.selected == 8
    check menu.scrollOffset > 0
    check "item-8" in canvas.plainText

  test "input edits UTF-8 and emits submitted text":
    let input = newInput()
    input.insert("hé")
    check input.cursor == "hé".len
    discard input.handle(UiEvent(kind: uiKey, key: keyLeft))
    discard input.handle(UiEvent(kind: uiKey, key: keyBackspace))
    check input.text == "é"
    let response = input.handle(UiEvent(kind: uiKey, key: keyEnter))
    check response.action.kind == "submit"
    check response.action.value == "é"

  test "input paints a visible cursor at the end and over text":
    let inputStyle = defaultStyle().withBackground(ansi256(236))
    let input = newInput(style = inputStyle)
    input.insert("abc")
    var canvas = newCanvas(size(12, 1))
    input.render(canvas, rect(0, 0, 12, 1))
    check canvas.getCell(10, 0).style.background.kind == colorAnsi256
    check canvas.getCell(10, 0).style.background.value == 236
    check canvas.getCell(5, 0).glyph.int == 0x258c
    check attrReverse in canvas.getCell(5, 0).style.attributes
    discard input.handle(UiEvent(kind: uiKey, key: keyLeft))
    canvas.clear()
    input.render(canvas, rect(0, 0, 12, 1))
    check canvas.getCell(4, 0).glyph.int == ord('c')
    check attrReverse in canvas.getCell(4, 0).style.attributes

  test "input preserves blank lines":
    let input = newInput()
    input.setText("a\n\nb")
    var canvas = newCanvas(size(12, 3))
    input.render(canvas, rect(0, 0, 12, 3))
    check canvas.lineText(0).startsWith("> a")
    check canvas.lineText(1).startsWith("  ")
    check canvas.lineText(2).startsWith("  b")
    input.setText("\n\n")
    canvas.clear()
    input.render(canvas, rect(0, 0, 12, 3))
    check canvas.getCell(2, 2).glyph.int == 0x258c
    let typed = newInput()
    discard typed.handle(UiEvent(kind: uiKey, key: keyShiftEnter))
    discard typed.handle(UiEvent(kind: uiKey, key: keyShiftEnter))
    check typed.text == "\n\n"
    typed.setText("a\nb\nc\nd")
    canvas.clear()
    typed.render(canvas, rect(0, 0, 12, 3))
    check typed.scrollOffset == 1
    check canvas.lineText(2).startsWith("  d")
    check canvas.getCell(3, 2).glyph.int == 0x258c

  test "input wraps long lines and keeps the cursor visible":
    let input = newInput()
    input.setText("abcdefgh")
    var canvas = newCanvas(size(8, 3))
    input.render(canvas, rect(0, 0, 8, 3))
    check canvas.lineText(0).startsWith("> abcdef")
    check canvas.lineText(1).startsWith("  gh▌")

  test "input moves vertically without losing the cursor column":
    let input = newInput()
    input.setText("one\ntwo")
    discard input.handle(UiEvent(kind: uiKey, key: keyUp))
    check input.cursor == 3
    discard input.handle(UiEvent(kind: uiKey, key: keyDown))
    check input.cursor == 7

  test "question selects options and accepts free text":
    let question = newQuestion("Choose a mode", @[
      QuestionOption(label: "Plan"), QuestionOption(label: "Act")])
    discard question.handle(UiEvent(kind: uiKey, key: keyDown))
    let answer = question.handle(UiEvent(kind: uiKey, key: keyEnter)).action
    check answer.index == 1
    check answer.value == "Act"
    let other = newQuestion("Choose a mode", @[
      QuestionOption(label: "Plan")])
    other.selected = 1
    discard other.handle(UiEvent(kind: uiKey, key: keyChar, text: "custom"))
    discard other.handle(UiEvent(kind: uiKey, key: keyEnter))
    check other.freeText.text == "custom"

  test "question escape cancels without an answer":
    let question = newQuestion("Continue?", @[QuestionOption(label: "Yes")])
    let answer = question.handle(UiEvent(kind: uiKey, key: keyEscape)).action
    check answer.cancelled

  test "question paints radio buttons":
    let question = newQuestion("Choose", @[QuestionOption(label: "one"),
      QuestionOption(label: "two")])
    var canvas = newCanvas(size(20, 6))
    question.render(canvas, rect(0, 0, 20, 6))
    check "◉ one" in canvas.plainText
    check "○ two" in canvas.plainText

suite "transcript":
  test "reduces a streamed agent turn into stable items":
    var transcript = newTranscript()
    transcript.apply AgentUiEvent(kind: ueRunStarted, runId: "run-1",
      prompt: "List files")
    transcript.apply AgentUiEvent(kind: ueStepStarted, runId: "run-1", step: 0)
    transcript.apply AgentUiEvent(kind: ueThinkingDelta, runId: "run-1", step: 0,
      text: "Checking")
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "run-1", step: 0,
      text: "Done")
    transcript.apply AgentUiEvent(kind: ueToolCalled, runId: "run-1", step: 0,
      toolId: "call-1", toolName: "ls", toolInput: %*{"path": "."})
    transcript.apply AgentUiEvent(kind: ueToolResult, runId: "run-1", step: 0,
      toolId: "call-1", toolOutput: "README.md", durationMs: 3)
    transcript.apply AgentUiEvent(kind: ueStepFinished, runId: "run-1", step: 0)
    transcript.apply AgentUiEvent(kind: ueRunFinished, runId: "run-1", step: 0)
    check transcript.items.len == 4
    check transcript.items[0].kind == tikUser
    check transcript.items[1].text == "Checking"
    check transcript.items[2].text == "Done"
    check not transcript.items[2].pending
    check transcript.items[3].text == "README.md"
    check not transcript.items[3].pending

  test "ignores empty text and thinking deltas":
    var transcript = newTranscript()
    transcript.apply AgentUiEvent(kind: ueStepStarted, runId: "run-1", step: 0)
    transcript.apply AgentUiEvent(kind: ueThinkingDelta, runId: "run-1",
      step: 0, text: "")
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "run-1", step: 0,
      text: "")
    check transcript.items.len == 0

  test "keeps interleaved runs separate":
    var transcript = newTranscript()
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "a", step: 0,
      text: "one")
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "b", step: 0,
      text: "two")
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "a", step: 0,
      text: " three")
    check transcript.items.len == 2
    check transcript.items[0].text == "one three"
    check transcript.items[1].text == "two"

  test "renders markdown, cards, diffs, and transcript into cells":
    var transcript = newTranscript()
    transcript.appendUser("hello")
    transcript.apply AgentUiEvent(kind: ueRunStarted, runId: "run", prompt: "ignored")
    transcript.apply AgentUiEvent(kind: ueStepStarted, runId: "run", step: 0)
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
    text: "answer")
    var canvas = newCanvas(size(30, 12))
    let view = newTranscriptWidget(transcript)
    var transcriptCanvas = newCanvas(size(30, 12))
    view.render(transcriptCanvas, rect(0, 0, 30, 12))
    check "hello" in transcriptCanvas.plainText
    check "answer" in transcriptCanvas.plainText
    check "│ You" in transcriptCanvas.plainText
    check "│ Assistant" in transcriptCanvas.plainText

    let card = newCard("status", "ready")
    card.render(canvas, rect(0, 4, 15, 3))
    check "status" in canvas.plainText
    let markdown = newMarkdown("**bold**")
    markdown.render(canvas, rect(16, 4, 14, 2))
    check "bold" in canvas.plainText
    let diff = newDiffCard(DiffDocument(path: "file.nim",
      lines: @[DiffLine(kind: dlAdded, text: "new")]))
    diff.render(canvas, rect(0, 8, 20, 3))
    check "+ new" in canvas.plainText

  test "wraps long transcript lines":
    var transcript = newTranscript()
    transcript.appendUser("abcdefgh")
    let view = newTranscriptWidget(transcript)
    var canvas = newCanvas(size(8, 8))
    view.render(canvas, rect(0, 0, 8, 8))
    check "│ abcdef" in canvas.plainText
    check "│ gh" in canvas.plainText

  test "transcript selection tolerates empty and unicode rows":
    var transcript = newTranscript()
    transcript.appendUser("hello")
    let view = newTranscriptWidget(transcript)
    view.selectionStart = 0
    view.selectionEnd = 2
    view.selectionStartCol = 0
    view.selectionEndCol = 10
    check "hello" in view.selectedText()

  test "emits a generic approval action from the transcript":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-1",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-1",
      approvalChoices: @[ApprovalChoice(id: "allow", key: "y", label: "allow")])
    let handled = view.handle(UiEvent(kind: uiKey, key: keyChar, text: "y"))
    check handled.handled
    check handled.action.value == "allow"

  test "approval choices remain application-defined data":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-scope",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-scope",
      approvalChoices: @[
        ApprovalChoice(id: "once", key: "enter", label: "once"),
        ApprovalChoice(id: "session", key: "s", label: "session")])
    let response = view.handle(UiEvent(kind: uiKey, key: keyChar, text: "s"))
    check response.handled
    check response.action.value == "session"

  test "escape denies approval without exiting":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-escape",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-escape",
      cancelChoiceId: "deny")
    let handled = view.handle(UiEvent(kind: uiKey, key: keyEscape))
    check handled.handled
    check handled.action.value == "deny"
    check not view.awaitingApproval

  test "enter approves a tool once":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-enter",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-enter",
      approvalChoices: @[ApprovalChoice(id: "once", key: "enter", label: "once")])
    let response = view.handle(UiEvent(kind: uiKey, key: keyEnter))
    check response.handled
    check response.action.value == "once"
    check not view.awaitingApproval

  test "collapses and expands long tool output":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-1",
      toolName: "read")
    view.apply AgentUiEvent(kind: ueToolResult, toolId: "call-1",
      toolOutput: "one\ntwo\nthree")
    var canvas = newCanvas(size(30, 5))
    view.render(canvas, rect(0, 0, 30, 5))
    check "more (Ctrl-O)" in canvas.plainText
    check view.handle(UiEvent(kind: uiKey, key: keyCtrlO)) == eventHandled
    canvas.clear()
    view.render(canvas, rect(0, 0, 30, 5))
    check "three" in canvas.plainText

  test "renders edit tool diffs in the completed tool card":
    let view = newTranscriptWidget()
    view.toolDetails = proc (name: string, input: JsonNode,
                             output: string): seq[string] =
      @[input["path"].getStr, "- old line", "+ new line"]
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-edit",
      toolName: "edit", toolInput: %*{
        "path": "src/main.nim",
        "old_text": "old line",
        "new_text": "new line"
      })
    view.apply AgentUiEvent(kind: ueToolResult, toolId: "call-edit",
      toolOutput: "OK — src/main.nim")
    var canvas = newCanvas(size(40, 10))
    view.render(canvas, rect(0, 0, 40, 10))
    check "src/main.nim" in canvas.plainText
    check "- old line" in canvas.plainText
    check "+ new line" in canvas.plainText

  test "Ctrl-O expands collapsed tool diffs":
    let view = newTranscriptWidget()
    view.toolDetails = proc (name: string, input: JsonNode,
                             output: string): seq[string] =
      @[input["path"].getStr, "+ one", "+ two", "+ three"]
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-write",
      toolName: "write", toolInput: %*{
        "path": "new.txt",
        "content": "one\ntwo\nthree"
      })
    view.apply AgentUiEvent(kind: ueToolResult, toolId: "call-write",
      toolOutput: "OK")
    var canvas = newCanvas(size(30, 10))
    view.render(canvas, rect(0, 0, 30, 10))
    check "detail lines (Ctrl-O)" in canvas.plainText
    check view.handle(UiEvent(kind: uiKey, key: keyCtrlO)) == eventHandled
    canvas.clear()
    view.render(canvas, rect(0, 0, 30, 10))
    check "+ three" in canvas.plainText
