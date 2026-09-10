import std/[json, strutils, unittest]
import nimterm/[ansi, app, backend, canvas, events, geometry, markdown, keys,
  theme, transcript, widget, widgets]
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
    check "\e" notin rendered

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

  test "renders markdown, cards, diffs, and transcript into cells":
    var transcript = newTranscript()
    transcript.appendUser("hello")
    transcript.apply AgentUiEvent(kind: ueRunStarted, runId: "run", prompt: "ignored")
    transcript.apply AgentUiEvent(kind: ueStepStarted, runId: "run", step: 0)
    transcript.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "answer")
    var canvas = newCanvas(size(30, 12))
    let view = newTranscriptWidget(transcript)
    view.render(canvas, rect(0, 0, 30, 4))
    check "hello" in canvas.plainText
    check "answer" in canvas.plainText

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
