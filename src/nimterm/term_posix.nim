## POSIX terminal control for nimterm.

import std/[base64, os, posix, strutils, terminal]
when defined(macosx):
  import std/osproc
import posix/termios
import ./backend

type
  TermError* = object of CatchableError

var
  gTermActive = false
  gLastW, gLastH: int
  gOldTermios: Termios
  gRawTermios: Termios
  gCapabilities: TerminalCapabilities
  gFullscreen: bool

proc measureTerm(): tuple[w, h: int] =
  try:
    result.w = terminalWidth()
  except CatchableError:
    result.w = 80
  try:
    result.h = terminalHeight()
  except CatchableError:
    result.h = 24
  if result.w <= 0: result.w = 80
  if result.h <= 0: result.h = 24

proc termWidth*(): int =
  if gLastW <= 0:
    let s = measureTerm()
    gLastW = s.w
    gLastH = s.h
  gLastW

proc termHeight*(): int =
  if gLastH <= 0: discard termWidth()
  gLastH

proc termWrite(s: string) = stdout.write(s)

proc copyToClipboard*(text: string) =
  if not gTermActive: return
  termWrite("\e]52;c;" & encode(text) & "\a")
  stdout.flushFile()
  when defined(macosx):
    discard execCmdEx("pbcopy", input = text)

proc hideCursor() = termWrite("\e[?25l")
proc showCursor() = termWrite("\e[?25h")
proc clearScreen() = termWrite("\e[2J\e[H")

proc enableMouse(): string = "\e[?1000h\e[?1002h\e[?1006h"
proc disableMouse(): string = "\e[?1006l\e[?1002l\e[?1000l\e[?1007l"

proc enableModifyOtherKeys(): string =
  result = "\e[>4;2m"
  result.add "\e[?1036h"

proc enableKittyKeyboard(): string = "\e[>1u"
proc disableModifyOtherKeys(): string = "\e[>4;0m\e[?1036l"
proc disableKittyKeyboard(): string = "\e[<u"
proc enableBracketedPaste(): string = "\e[?2004h"
proc disableBracketedPaste(): string = "\e[?2004l"

proc enableProtocols*(caps: TerminalCapabilities): string =
  if caps.mouse: result.add enableMouse()
  if caps.focusEvents: result.add "\e[?1004h"
  if caps.kittyKeyboard: result.add enableKittyKeyboard()
  elif caps.modifyOtherKeys: result.add enableModifyOtherKeys()
  if caps.bracketedPaste: result.add enableBracketedPaste()

proc disableProtocols*(caps: TerminalCapabilities): string =
  if caps.bracketedPaste: result.add disableBracketedPaste()
  if caps.kittyKeyboard: result.add disableKittyKeyboard()
  elif caps.modifyOtherKeys: result.add disableModifyOtherKeys()
  if caps.focusEvents: result.add "\e[?1004l"
  if caps.mouse: result.add disableMouse()

proc useAltScreen(): bool =
  let t = getEnv("TERM")
  t.len == 0 or "xterm" in t or "screen" in t or "tmux" in t or
    "alacritty" in t or "kitty" in t or "rxvt" in t or "vt100" in t

proc enterAltScreen() =
  if useAltScreen(): termWrite("\e[?1049h")
  else: clearScreen()

proc leaveAltScreen() =
  if useAltScreen(): termWrite("\e[?1049l")
  else: clearScreen()

proc termShutdown*()

proc termInit*(capabilities = defaultCapabilities(), fullscreen = true) =
  if gTermActive:
    raise newException(TermError, "terminal already initialised")
  if tcGetAttr(STDIN_FILENO, gOldTermios.addr) != 0:
    raise newException(TermError, "tcgetattr failed")
  gRawTermios = gOldTermios
  ## Raw-ish: no echo/canonical/extended processing; disable ISIG so Ctrl-C
  ## arrives as byte 3 and Ctrl-O is not consumed by VDISCARD.
  gRawTermios.c_lflag = gRawTermios.c_lflag and
    not Cflag(ICANON or ECHO or ISIG or IEXTEN)
  gRawTermios.c_iflag = gRawTermios.c_iflag and not Cflag(IXON or IXOFF)
  gRawTermios.c_cc[VMIN] = 0.char
  gRawTermios.c_cc[VTIME] = 0.char
  if tcSetAttr(STDIN_FILENO, TCSANOW, gRawTermios.addr) != 0:
    raise newException(TermError, "tcsetattr failed")
  gCapabilities = capabilities
  gFullscreen = fullscreen
  gTermActive = true
  try:
    gLastW = termWidth()
    gLastH = termHeight()
    if fullscreen: enterAltScreen()
    else: termWrite("\n".repeat(gLastH) & "\e[H")
    termWrite("\e[?6l\e[r")
    if fullscreen: clearScreen()
    hideCursor()
    termWrite(enableProtocols(capabilities))
    stdout.flushFile()
  except CatchableError:
    termShutdown()
    raise

proc termShutdown*() =
  if not gTermActive: return
  try:
    termWrite(disableProtocols(gCapabilities))
    showCursor()
    if gFullscreen: leaveAltScreen()
    else: termWrite("\e[999B\r\n")
    stdout.flushFile()
  finally:
    discard tcSetAttr(STDIN_FILENO, TCSANOW, gOldTermios.addr)
    gTermActive = false

proc terminalActive*(): bool = gTermActive
proc suspendTerminal*() = termShutdown()
proc resumeTerminal*() =
  if not gTermActive: termInit(gCapabilities, gFullscreen)

proc inputPending*(timeoutMs: int): bool =
  var fds: TFdSet
  FD_ZERO(fds)
  FD_SET(STDIN_FILENO, fds)
  if timeoutMs < 0:
    discard select(STDIN_FILENO + 1, fds.addr, nil, nil, nil)
  else:
    var tv: Timeval
    tv.tv_sec = Time(timeoutMs div 1000)
    tv.tv_usec = Suseconds(1000 * (timeoutMs mod 1000))
    discard select(STDIN_FILENO + 1, fds.addr, nil, nil, tv.addr)
  FD_ISSET(STDIN_FILENO, fds) != 0

proc readByte*(): int =
  var ch: char
  if read(STDIN_FILENO, ch.addr, 1) > 0: return ord(ch)
  -1

proc readAvailable*(): string =
  while inputPending(0):
    let value = readByte()
    if value < 0: break
    result.add char(value)

proc consumeResize*(): bool =
  let s = measureTerm()
  if s.w != gLastW or s.h != gLastH:
    gLastW = s.w
    gLastH = s.h
    return true
  false

proc terminalInputIsInteractive*(): bool = stdin.isatty
proc terminalOutputIsInteractive*(): bool = stdout.isatty
proc terminalIsInteractive*(): bool =
  terminalInputIsInteractive() and terminalOutputIsInteractive()
