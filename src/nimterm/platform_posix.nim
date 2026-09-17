## POSIX terminal backend.

when defined(windows):
  {.error: "platform_posix is unavailable on Windows".}

import std/[monotimes, os, posix, strutils]
import ./backend
import ./canvas
import ./events
import ./frame
import ./geometry
import ./input
import ./term

export frame

when not declared(SIGWINCH):
  var SIGWINCH {.importc: "SIGWINCH", header: "<signal.h>".}: cint

type
  PosixBackend* = ref object of TerminalBackend
    capabilities*: TerminalCapabilities
    fullscreen*: bool
    decoder: InputDecoder
    wakeRead, wakeWrite: cint
    previous: Canvas
    hasPrevious: bool
    oldWinch, oldTerm, oldHup, oldTstp, oldCont: Sigaction
    installedSignals: int
    pendingQuit: bool
    pendingSuspend: bool

var gSignalWrite = -1.cint

proc signalWake(signal: cint) {.noconv.} =
  if gSignalWrite >= 0:
    var byte = if signal == SIGWINCH: 'w'
      elif signal == SIGTSTP: 's'
      elif signal == SIGCONT: 'c'
      else: 'q'
    discard posix.write(gSignalWrite, byte.addr, 1)

proc installSignal(signal: cint, previous: var Sigaction) =
  var action: Sigaction
  action.sa_handler = signalWake
  discard sigemptyset(action.sa_mask)
  if sigaction(signal, action, previous) != 0: raiseOSError(osLastError())

proc restoreSignals(backend: PosixBackend) =
  gSignalWrite = -1
  if backend.installedSignals == 0: return
  if backend.installedSignals >= 1: discard sigaction(SIGWINCH, backend.oldWinch)
  if backend.installedSignals >= 2: discard sigaction(SIGTERM, backend.oldTerm)
  if backend.installedSignals >= 3: discard sigaction(SIGHUP, backend.oldHup)
  if backend.installedSignals >= 4: discard sigaction(SIGTSTP, backend.oldTstp)
  if backend.installedSignals >= 5: discard sigaction(SIGCONT, backend.oldCont)
  backend.installedSignals = 0

proc installSignals(backend: PosixBackend) =
  gSignalWrite = backend.wakeWrite
  installSignal(SIGWINCH, backend.oldWinch)
  backend.installedSignals = 1
  installSignal(SIGTERM, backend.oldTerm)
  backend.installedSignals = 2
  installSignal(SIGHUP, backend.oldHup)
  backend.installedSignals = 3
  installSignal(SIGTSTP, backend.oldTstp)
  backend.installedSignals = 4
  installSignal(SIGCONT, backend.oldCont)
  backend.installedSignals = 5

proc closeWakePipe(backend: PosixBackend) =
  if backend.wakeRead >= 0: discard posix.close(backend.wakeRead)
  if backend.wakeWrite >= 0: discard posix.close(backend.wakeWrite)
  backend.wakeRead = -1
  backend.wakeWrite = -1

proc detectTerminalCapabilities*(): TerminalCapabilities =
  let term = getEnv("TERM").toLowerAscii
  let program = getEnv("TERM_PROGRAM").toLowerAscii
  if term.len == 0 or term == "dumb": return
  result.mouse = true
  result.bracketedPaste = true
  result.focusEvents = true
  result.kittyKeyboard = getEnv("KITTY_WINDOW_ID").len > 0 or
    program in ["ghostty", "wezterm"]
  result.modifyOtherKeys = not result.kittyKeyboard and
    ("xterm" in term or program in ["iterm.app", "apple_terminal"])

proc newPosixBackend*(capabilities = detectTerminalCapabilities(),
                      fullscreen = true): TerminalBackend =
  PosixBackend(capabilities: capabilities, fullscreen: fullscreen,
    wakeRead: -1, wakeWrite: -1)

proc newPlatformBackend*(capabilities = detectTerminalCapabilities(),
                         fullscreen = true): TerminalBackend =
  newPosixBackend(capabilities, fullscreen)

method init*(backend: PosixBackend) =
  var fds: array[2, cint]
  if posix.pipe(fds) != 0: raiseOSError(osLastError())
  backend.wakeRead = fds[0]
  backend.wakeWrite = fds[1]
  try:
    if fcntl(backend.wakeRead, F_SETFL, O_NONBLOCK) < 0 or
        fcntl(backend.wakeWrite, F_SETFL, O_NONBLOCK) < 0:
      raiseOSError(osLastError())
    backend.installSignals()
    termInit(backend.capabilities, backend.fullscreen)
    backend.hasPrevious = false
  except:
    backend.restoreSignals()
    backend.closeWakePipe()
    raise

method shutdown*(backend: PosixBackend) =
  try:
    termShutdown()
  finally:
    backend.restoreSignals()
    backend.closeWakePipe()
    backend.hasPrevious = false

method wake*(backend: PosixBackend) =
  if backend.wakeWrite >= 0:
    var byte = '\1'
    discard posix.write(backend.wakeWrite, byte.addr, 1)

proc inputReady(backend: PosixBackend, timeoutMs: int): bool =
  var fds: TFdSet
  FD_ZERO(fds)
  FD_SET(STDIN_FILENO, fds)
  if backend.wakeRead >= 0: FD_SET(backend.wakeRead, fds)
  let highest = max(STDIN_FILENO, backend.wakeRead)
  if timeoutMs < 0:
    discard select(highest + 1, fds.addr, nil, nil, nil)
  else:
    var timeout = Timeval(tv_sec: Time(timeoutMs div 1000),
      tv_usec: Suseconds(1000 * (timeoutMs mod 1000)))
    discard select(highest + 1, fds.addr, nil, nil, timeout.addr)
  if backend.wakeRead >= 0 and FD_ISSET(backend.wakeRead, fds) != 0:
    var bytes: array[64, char]
    while true:
      let count = posix.read(backend.wakeRead, bytes.addr, bytes.len)
      if count <= 0: break
      for i in 0 ..< count:
        if bytes[i] == 'q': backend.pendingQuit = true
        elif bytes[i] == 's': backend.pendingSuspend = true
  FD_ISSET(STDIN_FILENO, fds) != 0

proc suspend(backend: PosixBackend) =
  termShutdown()
  backend.restoreSignals()
  var action: Sigaction
  action.sa_handler = SIG_DFL
  discard sigemptyset(action.sa_mask)
  if sigaction(SIGTSTP, action) != 0: raiseOSError(osLastError())
  discard posix.raise(SIGTSTP)
  discard sigaction(SIGTSTP, backend.oldTstp)
  backend.installSignals()
  termInit(backend.capabilities, backend.fullscreen)
  backend.hasPrevious = false

method size*(backend: PosixBackend): Size =
  size(termWidth(), termHeight())

proc resizeEvent(): UiEvent =
  UiEvent(kind: uiResize, width: termWidth(), height: termHeight())

proc signalEvent(backend: PosixBackend, event: var UiEvent): bool =
  ## Map a signal that arrived while waiting onto the next UI event.
  if backend.pendingQuit:
    backend.pendingQuit = false
    event = quitEvent()
    return true
  if backend.pendingSuspend:
    backend.pendingSuspend = false
    backend.suspend()
    event = resizeEvent()
    return true
  if consumeResize():
    event = resizeEvent()
    return true

method readEvent*(backend: PosixBackend, timeoutMs: int): UiEvent =
  if backend.signalEvent(result): return
  let nowMs = getMonoTime().ticks div 1_000_000
  var input = backend.decoder.nextEvent(nowMs)
  if input.noEvent:
    if backend.inputReady(backend.decoder.waitForInput(nowMs, timeoutMs)):
      backend.decoder.feed(readAvailable())
    if backend.signalEvent(result): return
    input = backend.decoder.nextEvent(getMonoTime().ticks div 1_000_000)
  input

method present*(backend: PosixBackend, frame: Canvas) =
  presentFrame(backend.previous, backend.hasPrevious, frame)

method resetPresentation*(backend: PosixBackend) =
  backend.hasPrevious = false
