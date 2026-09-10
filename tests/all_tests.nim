import std/[json, strutils, unittest]
import nimterm/[ansi, app, backend, canvas, events, geometry, markdown, keys,
  style, theme, transcript, widget, widgets]
when not defined(windows):
  import nimterm/platform_posix

suite "ansi text":
  test "visible width ignores escapes":
    check ansiVisibleWidth("\e[31mred\e[0m") == 3
    check stripAnsi("\e[31mred\e[0m") == "red"

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

suite "core canvas and app":
  test "constructs the POSIX backend without entering raw mode":
    check not newPosixBackend().isNil

  test "canvas writes text into a stable snapshot":
    var canvas = newCanvas(size(8, 2))
    canvas.writeText(1, 0, "hi")
    check canvas.plainText == " hi     \n        "

  test "app dispatches agent events and presents a frame":
    let backend = FakeBackend(events: @[agentEvent(AgentUiEvent(
      kind: ueTextDelta, text: "hello"))])
    var app = newApp(backend, newText("ready"))
    var seen = ""
    app.onEvent = proc (_: var App, event: UiEvent) =
      if event.kind == uiAgent:
        seen = event.agent.text
    check app.step()
    check seen == "hello"
    check backend.presented.plainText.startsWith("ready")

  test "menu changes selection and invokes selection callback":
    var selected = -1
    let menu = newMenu(@[
      MenuItem(label: "one", description: "first"),
      MenuItem(label: "two", description: "second")])
    menu.onSelect = proc (index: int) = selected = index
    discard menu.handle(UiEvent(kind: uiKey, key: keyDown))
    discard menu.handle(UiEvent(kind: uiKey, key: keyEnter))
    check selected == 1

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

  test "input edits UTF-8 and submits text":
    let input = newInput()
    input.insert("hé")
    check input.cursor == "hé".len
    discard input.handle(UiEvent(kind: uiKey, key: keyLeft))
    discard input.handle(UiEvent(kind: uiKey, key: keyBackspace))
    check input.text == "é"
    var submitted = ""
    input.onSubmit = proc (text: string) = submitted = text
    discard input.handle(UiEvent(kind: uiKey, key: keyEnter))
    check submitted == "é"

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
    var answer: QuestionAnswer
    question.onAnswer = proc (value: QuestionAnswer) = answer = value
    discard question.handle(UiEvent(kind: uiKey, key: keyDown))
    discard question.handle(UiEvent(kind: uiKey, key: keyEnter))
    check answer.selected == 1
    check answer.text == "Act"
    let other = newQuestion("Choose a mode", @[
      QuestionOption(label: "Plan")])
    other.selected = 1
    discard other.handle(UiEvent(kind: uiKey, key: keyChar, text: "custom"))
    discard other.handle(UiEvent(kind: uiKey, key: keyEnter))
    check other.freeText.text == "custom"

  test "question escape cancels without an answer":
    let question = newQuestion("Continue?", @[QuestionOption(label: "Yes")])
    var answer: QuestionAnswer
    question.onAnswer = proc (value: QuestionAnswer) = answer = value
    discard question.handle(UiEvent(kind: uiKey, key: keyEscape))
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

  test "resolves a generic approval callback from the transcript":
    var allowed = -1
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-1",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-1",
      approve: proc (value: bool) = allowed = if value: 1 else: 0)
    let handled = view.handle(UiEvent(kind: uiKey, key: keyChar, text: "y"))
    check handled == eventHandled
    check allowed == 1

  test "remember-session and remember-project actions resolve approval":
    var allowed = -1
    var remembered = ""
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-scope",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-scope",
      approve: proc (value: bool) = allowed = if value: 1 else: 0,
      rememberSession: proc () = remembered = "session",
      rememberProject: proc () = remembered = "project")
    check view.handle(UiEvent(kind: uiKey, key: keyChar, text: "s")) == eventHandled
    check remembered == "session"
    check allowed == 1

  test "escape denies approval without exiting":
    var allowed = -1
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-escape",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-escape",
      approve: proc (value: bool) = allowed = if value: 1 else: 0)
    let handled = view.handle(UiEvent(kind: uiKey, key: keyEscape))
    check handled == eventHandled
    check allowed == 0
    check not view.awaitingApproval

  test "enter approves a tool once":
    var allowed = -1
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-enter",
      toolName: "bash")
    view.apply AgentUiEvent(kind: ueApprovalRequired, toolId: "call-enter",
      approve: proc (value: bool) = allowed = if value: 1 else: 0)
    check view.handle(UiEvent(kind: uiKey, key: keyEnter)) == eventHandled
    check allowed == 1
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
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call-write",
      toolName: "write", toolInput: %*{
        "path": "new.txt",
        "content": "one\ntwo\nthree"
      })
    view.apply AgentUiEvent(kind: ueToolResult, toolId: "call-write",
      toolOutput: "OK")
    var canvas = newCanvas(size(30, 10))
    view.render(canvas, rect(0, 0, 30, 10))
    check "diff lines (Ctrl-O)" in canvas.plainText
    check view.handle(UiEvent(kind: uiKey, key: keyCtrlO)) == eventHandled
    canvas.clear()
    view.render(canvas, rect(0, 0, 30, 10))
    check "+ three" in canvas.plainText
