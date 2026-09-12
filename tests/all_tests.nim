import std/[json, strutils, unittest]
from std/unicode import Rune
import nimterm/[ansi, app, backend, canvas, events, geometry, input, markdown, keys,
  style, text_width, theme, transcript, widget, widgets]
import nimterm/term
when not defined(windows):
  import nimterm/platform_posix
else:
  import nimterm/platform_windows

proc decodeBytes(bytes: string): InputEvent =
  var index = 1
  proc nextByte(timeoutMs: int): int =
    discard timeoutMs
    if index >= bytes.len: return -1
    result = bytes[index].ord
    inc index
  decodeInput(if bytes.len == 0: -1 else: bytes[0].ord, nextByte)

suite "terminal input decoding":
  test "buffers escape until its ambiguity deadline":
    var decoder: InputDecoder
    decoder.feed("\e")
    check decoder.nextEvent(100).key == keyNone
    check decoder.nextEvent(114).key == keyNone
    check decoder.nextEvent(115).key == keyEscape

  test "decodes several events from one byte chunk":
    var decoder: InputDecoder
    decoder.feed("ab")
    check decoder.nextEvent(0).text == "a"
    check decoder.nextEvent(0).text == "b"
    check decoder.nextEvent(0).key == keyNone

  test "preserves sequences split at every byte boundary":
    for bytes in ["界", "\e[A", "\e[118;5u", "\e[<32;3;4M",
                  "\e[200~one\r\ntwo\e[201~"]:
      for split in 1 ..< bytes.len:
        var decoder: InputDecoder
        decoder.feed(bytes[0 ..< split])
        let partial = decoder.nextEvent(100)
        check partial.key == keyNone
        check partial.mouse == mouseNone
        check partial.focus == focusNone
        decoder.feed(bytes[split .. ^1])
        let complete = decoder.nextEvent(100)
        check complete.key != keyNone or complete.mouse != mouseNone or
          complete.scrollDelta != 0 or complete.focus != focusNone

  test "distinguishes escape from complete and partial control sequences":
    check decodeBytes("\e").key == keyEscape
    check decodeBytes("\e[A").key == keyUp
    check decodeBytes("\e[").key == keyNone

  test "normalizes modified key encodings":
    check decodeBytes("\e[118;5u").key == keyCtrlV
    check decodeBytes("\e[99;6u").key == keyCopy
    check decodeBytes("\e[111;5u").key == keyCtrlO
    check decodeBytes("\e\r").key == keyAltEnter
    check decodeBytes("\e[13;3u").key == keyAltEnter
    check decodeBytes("\e[1;3A").key == keyAltUp
    check decodeBytes("\e[13;2u").key == keyShiftEnter

  test "decodes function, insert, and control keys":
    check decodeBytes("\eOP").key == keyF1
    check decodeBytes("\e[15~").key == keyF5
    check decodeBytes("\e[24~").key == keyF12
    check decodeBytes("\e[2~").key == keyInsert
    check decodeBytes("\x04").key == keyCtrlD
    check decodeBytes("\x0b").key == keyCtrlK
    check decodeBytes("\x1a").key == keyCtrlZ

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
    let modified = decodeBytes("\e[<30;3;4M")
    check modified.button == umbRight
    check modified.shift and modified.alt and modified.ctrl

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

  test "tables omit the separator row and fit the viewport":
    let source = "| Location | Description |\n|---|---|\n| /tmp/a-long-path | a description that needs wrapping |"
    let rendered = renderMarkdown(source, false, 24)
    check "| --- |" notin rendered
    for line in rendered.splitLines:
      check displayWidth(line) <= 24

  test "streaming waits for a table separator":
    check "┌" notin renderMarkdown("| Location | Description |", false)
    check "┌" in renderMarkdown("| Location | Description |\n|---|---|", false)

  test "tables accept rows without outer pipes":
    let source = "Area | What it is | Status\n--- | --- | ---\nGeometry | Sizes and coordinates | Done"
    let rendered = renderMarkdown(source, false)
    check "Geometry" in rendered
    check "└" in rendered

  test "tables keep mixed outer-pipe styles in one table":
    let source = "| Area | What it is | Status |\n|---|---|---|\n| Geometry | Sizes and coordinates | Done |\nText | Styled text | Done\nPanel | Bordered container | Done"
    let rendered = renderMarkdown(source, false)
    for line in rendered.splitLines:
      if "Text" in line or "Panel" in line:
        check line.startsWith("│")

  test "colored table cells keep their column padding":
    let source = "| Area | Status |\n|---|---|\n| `Text` | Done |"
    let lines = renderMarkdown(source, true).splitLines
    check stripAnsi(lines[1]).find("│", 1) == stripAnsi(lines[3]).find("│", 1)

suite "themes":
  test "compiles built-in themes":
    let compiled = compileNamedTheme("dark", cd256)
    check compiled.ok
    check compiled.theme.accent == Dark256.accent

  test "keeps muted greys visible at 16-colour depth":
    let dark = compileTheme(DarkSpec, cd16)
    let light = compileTheme(LightSpec, cd16)
    check dark.muted == "\e[90m"
    check light.muted == "\e[90m"

  test "parses a complete custom theme":
    let doc = %*{
      "name": "custom",
      "colors": {
        "accent": "#00ffff", "success": "#00ff00", "error": "#ff0000",
        "warning": "#ffff00", "code": "#afaf00", "muted": 242, "dim": "dim", "text": "#fff",
        "heading": "#fff", "model": "#f0f", "panelBg": "#000000",
        "selectedBg": "#ffffff", "selectedFg": "#000000"
      }
    }
    check parseThemeJson(doc).ok

suite "scroll view":
  test "follows appended content only while anchored at the tail":
    var view = newScrollView()
    view.update(10, 3)
    check view.offset == 7
    view.scrollBy(-2)
    check not view.followTail
    check view.offset == 5
    view.update(12, 3)
    check view.offset == 5
    view.tail()
    view.update(14, 3)
    check view.offset == 11

  test "clamps after content and viewport resize":
    var view = newScrollView(false)
    view.update(20, 5)
    view.scrollBy(6)
    view.update(4, 8)
    check view.offset == 0
    check view.visibleRange == 0 .. 3

type
  FakeBackend = ref object of TerminalBackend
    presented: Canvas
    events: seq[UiEvent]
    lastTimeout: int
    wakeCount: int

  FailingBackend = ref object of TerminalBackend
    shutdownCalled: bool

method init(backend: FailingBackend) =
  raise newException(IOError, "init failed")

method shutdown(backend: FailingBackend) = backend.shutdownCalled = true

method size(backend: FakeBackend): Size = size(12, 4)

method readEvent(backend: FakeBackend, timeoutMs: int): UiEvent =
  backend.lastTimeout = timeoutMs
  if backend.events.len == 0:
    return UiEvent(kind: uiNone)
  result = backend.events[0]
  backend.events.delete(0)

method present(backend: FakeBackend, frame: Canvas) =
  backend.presented = frame

method wake(backend: FakeBackend) = inc backend.wakeCount

type FakeSource = ref object of EventSource
  events: seq[UiEvent]
  closed: bool

type FailingSource = ref object of EventSource
  closed: bool

method poll(source: FakeSource): seq[UiEvent] =
  result = source.events
  source.events.setLen(0)

method close(source: FakeSource) = source.closed = true

method poll(source: FailingSource): seq[UiEvent] =
  raise newException(IOError, "source failed")

method close(source: FailingSource) = source.closed = true

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
  test "failed backend initialization still shuts down":
    let backend = FailingBackend()
    var app = newApp(backend)
    expect IOError: app.run()
    check backend.shutdownCalled

  test "posting wakes the backend and preserves queue order":
    let backend = FakeBackend()
    var app = newApp(backend)
    var seen: seq[string]
    app.onEvent = proc (_: var App, event: UiEvent): EventResponse =
      if event.kind == uiTimer: seen.add event.timerId
      eventIgnored
    app.post UiEvent(kind: uiTimer, timerId: "first")
    app.post UiEvent(kind: uiTimer, timerId: "second")
    check backend.wakeCount == 2
    check app.step()
    check app.step()
    check seen == @["first", "second"]

  test "an idle step can block without a polling deadline":
    let backend = FakeBackend()
    var app = newApp(backend)
    check not app.step(-1)
    check backend.lastTimeout == -1

  test "event source failures become events and disable the source":
    let backend = FakeBackend()
    let source = FailingSource(id: "broken")
    var app = newApp(backend)
    var failure: UiEvent
    app.onEvent = proc (_: var App, event: UiEvent): EventResponse =
      if event.kind == uiError:
        failure = event
        return eventHandled
      eventIgnored
    app.addSource(source)
    check app.step()
    check failure.sourceId == "broken"
    check failure.error == "source failed"
    check source.closed
    check app.sources.len == 0

  test "controller failures become UI errors":
    let backend = FakeBackend(events: @[UiEvent(kind: uiKey, key: keyEnter)])
    var app = newApp(backend)
    var first = true
    var failure = ""
    app.onEvent = proc (_: var App, event: UiEvent): EventResponse =
      if first:
        first = false
        raise newException(ValueError, "controller failed")
      if event.kind == uiError:
        failure = event.error
        return eventHandled
      eventIgnored
    check app.step()
    check app.step()
    check failure == "controller failed"

  test "constructs the platform backend without entering raw mode":
    when defined(windows):
      check not newWindowsBackend().isNil
      check not newWindowsBackend(fullscreen = false).isNil
    else:
      check not newPosixBackend().isNil
      check not newPosixBackend(fullscreen = false).isNil

  test "canvas writes text into a stable snapshot":
    var canvas = newCanvas(size(8, 2))
    canvas.writeText(1, 0, "hi")
    check canvas.plainText == " hi     \n        "

  test "canvas fills a clipped rectangle":
    var canvas = newCanvas(size(4, 2))
    canvas.fill(rect(2, -1, 4, 3), Cell(glyph: Rune(ord('x'))))
    check canvas.plainText == "  xx\n  xx"

  test "canvas reserves wide cells and joins combining marks":
    var canvas = newCanvas(size(4, 1))
    canvas.writeText(0, 0, "界e\u0301")
    check canvas.getCell(1, 0).continuation
    check canvas.getCell(2, 0).combining.len > 0

  when not defined(windows):
    test "differential frames skip unchanged cells and isolate damage":
      let previous = newCanvas(size(4, 2))
      var frame = previous.copy
      check frameOutput(frame, previous) == ""
      frame.writeText(2, 1, "X")
      check frameOutput(frame, previous) == "\e[2;3H\e[0mX\e[0m"

    test "differential frames clear tails and preserve wide boundaries":
      var previous = newCanvas(size(5, 1))
      previous.writeText(0, 0, "abcde")
      var frame = newCanvas(size(5, 1))
      frame.writeText(0, 0, "a")
      check frameOutput(frame, previous) == "\e[1;2H\e[0m    \e[0m"
      previous = newCanvas(size(5, 1))
      frame = previous.copy
      frame.writeText(1, 0, "界")
      check frameOutput(frame, previous) == "\e[1;2H\e[0m界\e[0m"

    test "differential frames retain combining marks and style changes":
      let previous = newCanvas(size(3, 1))
      var frame = previous.copy
      frame.writeText(0, 0, "e\u0301", defaultStyle().withForeground(ansi16(1)))
      frame.writeText(1, 0, "x")
      check frameOutput(frame, previous) ==
        "\e[1;1H\e[0m\e[31me\u0301\e[0mx\e[0m"

    test "differential frames fully redraw after resize":
      let previous = newCanvas(size(1, 1))
      let frame = newCanvas(size(2, 1))
      check frameOutput(frame, previous) == "\e[1;1H\e[0m  \e[0m"

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
  test "streaming preserves manual position and follows an active tail":
    let widget = newTranscriptWidget()
    widget.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "one\ntwo\nthree\nfour\nfive\nsix")
    var canvas = newCanvas(size(20, 4))
    widget.render(canvas, rect(0, 0, 20, 4))
    let firstTail = widget.viewport.offset
    check widget.viewport.followTail
    widget.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "\nseven")
    widget.render(canvas, rect(0, 0, 20, 4))
    check widget.viewport.offset > firstTail
    discard widget.handle(UiEvent(kind: uiKey, key: keyPageUp))
    let anchored = widget.viewport.offset
    check not widget.viewport.followTail
    widget.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "\neight")
    widget.render(canvas, rect(0, 0, 20, 4))
    check widget.viewport.offset == anchored

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
    check "│ answer" notin transcriptCanvas.plainText

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

  test "cards wrap long body lines":
    let card = newCard("status", "a long body line")
    var canvas = newCanvas(size(10, 4))
    check card.measure(Constraints(maxSize: size(10, 4))).h == 4
    card.render(canvas, rect(0, 0, 10, 4))
    check "a long" in canvas.plainText
    check "body" in canvas.plainText
    check "line" in canvas.plainText

  test "recedes thinking and makes tool status scannable":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueThinkingDelta, runId: "run", step: 0,
      text: "private\nreason")
    view.apply AgentUiEvent(kind: ueStepFinished, runId: "run", step: 0)
    view.apply AgentUiEvent(kind: ueToolCalled, runId: "run", step: 0,
      toolId: "call", toolName: "grep")
    view.apply AgentUiEvent(kind: ueToolResult, runId: "run", step: 0,
      toolId: "call", toolOutput: "src/main.nim:7:match")
    var canvas = newCanvas(size(40, 10))
    view.render(canvas, rect(0, 0, 40, 10))
    check "Thinking · 2 lines (Ctrl-O)" in canvas.plainText
    check "private" notin canvas.plainText
    check "│ ✓ grep" in canvas.plainText
    check "src/main.nim:7:match" in canvas.plainText
    check view.handle(UiEvent(kind: uiKey, key: keyCtrlO)) == eventHandled
    canvas.clear()
    view.render(canvas, rect(0, 0, 40, 10))
    check "private" in canvas.plainText

  test "renders assistant markdown before a tool question":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "**before the question**")
    check view.transcript.items[0].pending
    view.apply AgentUiEvent(kind: ueToolCalled, runId: "run", step: 0,
      toolId: "ask", toolName: "ask_user")
    check not view.transcript.items[0].pending
    var canvas = newCanvas(size(40, 5))
    view.render(canvas, rect(0, 0, 40, 5))
    check attrBold in canvas.getCell(0, 0).style.attributes

  test "renders completed markdown while assistant text streams":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "**already complete** and **still open")
    var canvas = newCanvas(size(40, 2))
    view.render(canvas, rect(0, 0, 40, 2))
    check attrBold in canvas.getCell(0, 0).style.attributes
    check canvas.getCell(21, 0).glyph.int == ord('*')

  test "preserves assistant markdown box drawing":
    let view = newTranscriptWidget()
    view.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "| A |\n|---|\n| B |")
    view.apply AgentUiEvent(kind: ueStepFinished, runId: "run", step: 0)
    var canvas = newCanvas(size(30, 8))
    view.render(canvas, rect(0, 0, 30, 8))
    check "┌" in canvas.plainText
    check "│ A" in canvas.plainText

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
    view.selectionStart = 1
    view.selectionEnd = 1
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

  test "Ctrl-O preserves a manually scrolled viewport":
    let view = newTranscriptWidget()
    view.toolDetails = proc (name: string, input: JsonNode,
                             output: string): seq[string] =
      @["one", "two", "three", "four"]
    view.apply AgentUiEvent(kind: ueTextDelta, runId: "run", step: 0,
      text: "a\nb\nc\nd\ne\nf")
    view.apply AgentUiEvent(kind: ueToolCalled, toolId: "call",
      toolName: "read", toolInput: %*{})
    view.apply AgentUiEvent(kind: ueToolResult, toolId: "call",
      toolOutput: "OK")
    var canvas = newCanvas(size(30, 4))
    view.render(canvas, rect(0, 0, 30, 4))
    discard view.handle(UiEvent(kind: uiKey, key: keyPageUp))
    let anchored = view.viewport.offset
    check not view.viewport.followTail
    check view.handle(UiEvent(kind: uiKey, key: keyCtrlO)) == eventHandled
    check view.viewport.offset == anchored
