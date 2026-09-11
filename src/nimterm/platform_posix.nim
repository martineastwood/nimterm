## POSIX terminal backend.

when defined(windows):
  {.error: "platform_posix is unavailable on Windows".}

import std/[monotimes, os, posix, strutils]
from std/unicode import toUTF8
import ./backend
import ./canvas
import ./events
import ./geometry
import ./input
import ./keys
import ./style
import ./term

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
  discard backend
  size(termWidth(), termHeight())

method readEvent*(backend: PosixBackend, timeoutMs: int): UiEvent =
  if backend.pendingQuit:
    backend.pendingQuit = false
    return quitEvent()
  if backend.pendingSuspend:
    backend.pendingSuspend = false
    backend.suspend()
    return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
  if consumeResize():
    return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
  let nowMs = getMonoTime().ticks div 1_000_000
  var input = backend.decoder.nextEvent(nowMs)
  if input.key == keyNone and input.mouse == mouseNone and
      input.scrollDelta == 0 and input.focus == focusNone:
    let escapeWait = backend.decoder.escapeWaitMs(nowMs)
    let wait = if escapeWait < 0: timeoutMs
               elif timeoutMs < 0: escapeWait
               else: min(timeoutMs, escapeWait)
    if backend.inputReady(wait): backend.decoder.feed(readAvailable())
    if backend.pendingQuit:
      backend.pendingQuit = false
      return quitEvent()
    elif backend.pendingSuspend:
      backend.pendingSuspend = false
      backend.suspend()
      return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
    elif consumeResize():
      return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
    input = backend.decoder.nextEvent(getMonoTime().ticks div 1_000_000)
  input.toUiEvent(termWidth(), termHeight())

proc sameCell(a, b: Cell): bool =
  a.glyph.int == b.glyph.int and a.combining == b.combining and
    a.continuation == b.continuation and a.style == b.style

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
      if last + 1 < frame.size.w and (frame.getCell(last + 1, y).continuation or
          previous.getCell(last + 1, y).continuation): inc last
    output.add "\e[" & $(y + 1) & ";" & $(first + 1) & "H"
    for x in first .. last:
      let cell = frame.getCell(x, y)
      if not hasStyle or activeStyle != cell.style:
        output.add "\e[0m"
        output.add sgr(cell.style)
        activeStyle = cell.style
        hasStyle = true
      if not cell.continuation: output.add toUTF8(cell.glyph) & cell.combining
      if attrStrikethrough in cell.style.attributes and cell.glyph.int != 32:
        ## Some terminal emulators ignore SGR 9; draw a visible fallback.
        output.add "\u0336"
  if output.len > 0: output.add "\e[0m"
  output

method present*(backend: PosixBackend, frame: Canvas) =
  let output = frame.frameOutput(backend.previous, not backend.hasPrevious)
  if output.len == 0: return
  backend.previous = frame.copy
  backend.hasPrevious = true
  stdout.write(output)
  stdout.flushFile()
