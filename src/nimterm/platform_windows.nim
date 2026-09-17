## Windows terminal backend.

import std/[monotimes, os, strutils, times, winlean]
import ./backend
import ./canvas
import ./events
import ./frame
import ./geometry
import ./input
import ./keys
import ./term

export frame

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
  size(termWidth(), termHeight())

method readEvent*(backend: WindowsBackend, timeoutMs: int): UiEvent =
  let nowMs = getMonoTime().ticks div 1_000_000
  var input = backend.decoder.nextEvent(nowMs)
  if input.noEvent:
    if backend.inputReady(backend.decoder.waitForInput(nowMs, timeoutMs)):
      backend.decoder.feed(readAvailable())
    if consumeResize():
      return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
    input = backend.decoder.nextEvent(getMonoTime().ticks div 1_000_000)
  input

method present*(backend: WindowsBackend, frame: Canvas) =
  presentFrame(backend.previous, backend.hasPrevious, frame)

method resetPresentation*(backend: WindowsBackend) =
  backend.hasPrevious = false
