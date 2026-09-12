## Windows terminal backend.

import std/[monotimes, os, strutils, times, winlean]
from std/unicode import toUTF8
import ./backend
import ./canvas
import ./events
import ./geometry
import ./input
import ./keys
import ./style
import ./term

type
  WindowsBackend* = ref object of TerminalBackend
    capabilities*: TerminalCapabilities
    fullscreen*: bool
    decoder: InputDecoder
    wakeEvent: Handle
    previous: Canvas
    hasPrevious: bool

proc detectTerminalCapabilities*(): TerminalCapabilities =
  let term = getEnv("TERM").toLowerAscii
  let program = getEnv("TERM_PROGRAM").toLowerAscii
  ## Windows Terminal, ConPTY, mintty, and conhost all understand the basic
  ## protocols once VT processing/input are enabled. Kitty keyboard is only
  ## requested where the host advertises it explicitly.
  if term == "dumb" and getEnv("WT_SESSION").len == 0 and
      getEnv("MSYSTEM").len == 0:
    return TerminalCapabilities(bracketedPaste: true)
  result.mouse = true
  result.bracketedPaste = true
  result.focusEvents = true
  result.kittyKeyboard = getEnv("KITTY_WINDOW_ID").len > 0 or
    program in ["wezterm", "ghostty"]
  result.modifyOtherKeys = not result.kittyKeyboard and
    program in ["windows_terminal", "mintty", "conemu"]

proc newWindowsBackend*(capabilities = detectTerminalCapabilities(),
                        fullscreen = true): TerminalBackend =
  WindowsBackend(capabilities: capabilities, fullscreen: fullscreen,
    wakeEvent: INVALID_HANDLE_VALUE)

proc newPlatformBackend*(capabilities = detectTerminalCapabilities(),
                         fullscreen = true): TerminalBackend =
  newWindowsBackend(capabilities, fullscreen)

proc closeWakeEvent(backend: WindowsBackend) =
  if backend.wakeEvent != INVALID_HANDLE_VALUE:
    discard closeHandle(backend.wakeEvent)
    backend.wakeEvent = INVALID_HANDLE_VALUE

method init*(backend: WindowsBackend) =
  backend.wakeEvent = createEvent(nil, 0, 0, nil)
  if backend.wakeEvent == INVALID_HANDLE_VALUE or backend.wakeEvent == 0:
    raiseOSError(osLastError())
  try:
    termInit(backend.capabilities, backend.fullscreen)
    backend.hasPrevious = false
  except:
    backend.closeWakeEvent()
    raise

method shutdown*(backend: WindowsBackend) =
  try:
    termShutdown()
  finally:
    backend.closeWakeEvent()
    backend.hasPrevious = false

method wake*(backend: WindowsBackend) =
  if backend.wakeEvent != INVALID_HANDLE_VALUE:
    discard setEvent(backend.wakeEvent)

proc inputReady(backend: WindowsBackend, timeoutMs: int): bool =
  if inputPending(0): return true
  if backend.wakeEvent == INVALID_HANDLE_VALUE:
    if timeoutMs > 0: sleep(timeoutMs)
    return inputPending(0)

  if inputIsConsole():
    var handles: WOHandleArray
    handles[0] = inputConsoleHandle()
    handles[1] = backend.wakeEvent
    let waitMs = if timeoutMs < 0: DWORD(INFINITE) else: DWORD(timeoutMs)
    let status = waitForMultipleObjects(2, addr handles, 0, waitMs)
    return status == WAIT_OBJECT_0

  ## MSYS/mintty presents native Windows programs with a pipe. Pipe handles
  ## are not consistently waitable for readable bytes, so probe briefly and
  ## also wait on our event to keep UI posts responsive.
  let started = getMonoTime()
  while true:
    if inputPending(0): return true
    if timeoutMs >= 0:
      let elapsed = int((getMonoTime() - started).inMilliseconds)
      if elapsed >= timeoutMs: return false
      let waitMs = min(25, timeoutMs - elapsed)
      discard waitForSingleObject(backend.wakeEvent, DWORD(waitMs))
    else:
      discard waitForSingleObject(backend.wakeEvent, 25)

method size*(backend: WindowsBackend): Size =
  discard backend
  size(termWidth(), termHeight())

method readEvent*(backend: WindowsBackend, timeoutMs: int): UiEvent =
  let nowMs = getMonoTime().ticks div 1_000_000
  var input = backend.decoder.nextEvent(nowMs)
  if input.key == keyNone and input.mouse == mouseNone and
      input.scrollDelta == 0 and input.focus == focusNone:
    let escapeWait = backend.decoder.escapeWaitMs(nowMs)
    let wait = if escapeWait < 0: timeoutMs
               elif timeoutMs < 0: escapeWait
               else: min(timeoutMs, escapeWait)
    if backend.inputReady(wait): backend.decoder.feed(readAvailable())
    if consumeResize():
      return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
    input = backend.decoder.nextEvent(getMonoTime().ticks div 1_000_000)
  input.toUiEvent(termWidth(), termHeight())

proc sameCell(a, b: Cell): bool =
  a.glyph.int == b.glyph.int and a.combining == b.combining and
  a.continuation == b.continuation and a.style == b.style

proc colorParams(color: ColorValue, background: bool): string =
  case color.kind
  of colorDefault:
    return ""
  of colorAnsi16:
    let index = color.value
    if background:
      return $(if index < 8: 40 + index else: 100 + index - 8)
    return $(if index < 8: 30 + index else: 90 + index - 8)
  of colorAnsi256:
    return (if background: "48" else: "38") & ";5;" & $color.value
  of colorRgb:
    return (if background: "48" else: "38") & ";2;" & $color.r & ";" &
      $color.g & ";" & $color.b

proc sgr(style: Style): string =
  var params: seq[string]
  if attrBold in style.attributes: params.add "1"
  if attrDim in style.attributes: params.add "2"
  if attrItalic in style.attributes: params.add "3"
  if attrUnderline in style.attributes: params.add "4"
  if attrReverse in style.attributes: params.add "7"
  if attrStrikethrough in style.attributes: params.add "9"
  let foreground = colorParams(style.foreground, false)
  let background = colorParams(style.background, true)
  if foreground.len > 0: params.add foreground
  if background.len > 0: params.add background
  if params.len > 0: "\e[" & params.join(";") & "m" else: ""

proc frameOutput*(frame, previous: Canvas, force = false): string =
  let full = force or frame.size != previous.size
  var output = newStringOfCap(frame.size.w * frame.size.h * 2)
  var activeStyle = defaultStyle()
  var hasStyle = false
  for y in 0 ..< frame.size.h:
    var first = 0
    var last = frame.size.w - 1
    if not full:
      while first <= last and sameCell(frame.getCell(first, y),
          previous.getCell(first, y)): inc first
      while last >= first and sameCell(frame.getCell(last, y),
          previous.getCell(last, y)): dec last
      if first > last: continue
      if frame.getCell(first, y).continuation or
          previous.getCell(first, y).continuation: dec first
      if last + 1 < frame.size.w and
          (frame.getCell(last + 1, y).continuation or
           previous.getCell(last + 1, y).continuation): inc last
    output.add "\e[" & $(y + 1) & ";" & $(first + 1) & "H"
    for x in first .. last:
      let cell = frame.getCell(x, y)
      if not hasStyle or activeStyle != cell.style:
        output.add "\e[0m"
        output.add sgr(cell.style)
        activeStyle = cell.style
        hasStyle = true
      if not cell.continuation:
        output.add toUTF8(cell.glyph) & cell.combining
      if attrStrikethrough in cell.style.attributes and cell.glyph.int != 32:
        output.add "\u0336"
  if output.len > 0: output.add "\e[0m"
  output

method present*(backend: WindowsBackend, frame: Canvas) =
  let output = frame.frameOutput(backend.previous, not backend.hasPrevious)
  if output.len == 0: return
  backend.previous = frame.copy
  backend.hasPrevious = true
  stdout.write(output)
  stdout.flushFile()

method resetPresentation*(backend: WindowsBackend) =
  backend.hasPrevious = false
