## Minimal terminal control for Nim applications.
##
## Owns raw mode, alternate screen, cursor, size, and mouse tracking enable.
## Input decoding lives in input.nim.

when defined(windows):
  {.error: "nimterm does not support native Windows; use WSL.".}

import std/[os, posix, strutils, terminal]
import posix/termios

type
  TermError* = object of CatchableError

var
  gTermActive = false
  gLastW, gLastH: int

proc measureTerm(): tuple[w, h: int] =
  try:
    result.w = terminalWidth()
  except CatchableError:
    result.w = 80
  try:
    result.h = terminalHeight()
  except CatchableError:
    result.h = 24

proc termWidth*(): int =
  if gLastW <= 0:
    let s = measureTerm()
    gLastW = s.w
    gLastH = s.h
  gLastW

proc termHeight*(): int =
  if gLastH <= 0:
    discard termWidth()
  gLastH

proc termWrite(s: string) =
  stdout.write(s)

proc hideCursor() =
  termWrite("\e[?25l")

proc showCursor() =
  termWrite("\e[?25h")

proc clearScreen() =
  termWrite("\e[2J\e[H")

proc enableMouse() =
  ## Full SGR mouse like pi fullscreen: wheel scrolls our viewport; drag is
  ## app-owned selection (terminal native select cannot work under mouse
  ## tracking). 1002 reports motion while a button is held.
  termWrite("\e[?1000h\e[?1002h\e[?1006h")

proc disableMouse() =
  termWrite("\e[?1006l\e[?1002l\e[?1000l\e[?1007l")

proc enableModifyOtherKeys() =
  ## Ask the terminal to distinguish modified keys (Shift+Enter, etc.).
  ## Level 2 reports ESC [ 27 ; mod ; key ~
  termWrite("\e[>4;2m")
  ## Also request Alt-sends-ESC so Option+Enter becomes ESC CR on macOS.
  termWrite("\e[?1036h")

proc enableKittyKeyboard() =
  ## Ask Kitty-compatible terminals to report modifier-bearing keys as CSI-u.
  termWrite("\e[>1u")

proc disableModifyOtherKeys() =
  termWrite("\e[>4;0m")
  termWrite("\e[?1036l")

proc disableKittyKeyboard() =
  termWrite("\e[<u")

proc enableBracketedPaste() =
  termWrite("\e[?2004h")

proc disableBracketedPaste() =
  termWrite("\e[?2004l")

var
  gOldTermios: Termios
  gRawTermios: Termios

proc useAltScreen(): bool =
  let t = getEnv("TERM")
  t.len == 0 or "xterm" in t or "screen" in t or "tmux" in t or
    "alacritty" in t or "kitty" in t or "rxvt" in t or "vt100" in t

proc enterAltScreen() =
  if useAltScreen():
    termWrite("\e[?1049h")
  else:
    clearScreen()

proc leaveAltScreen() =
  if useAltScreen():
    termWrite("\e[?1049l")
  else:
    clearScreen()

proc termInit*() =
  if gTermActive:
    raise newException(TermError, "terminal already initialised")
  if tcGetAttr(STDIN_FILENO, gOldTermios.addr) != 0:
    raise newException(TermError, "tcgetattr failed")
  gRawTermios = gOldTermios
  # Raw-ish: no echo/canonical; disable ISIG so Ctrl-C arrives as byte 3.
  gRawTermios.c_lflag = gRawTermios.c_lflag and not Cflag(ICANON or ECHO or ISIG)
  gRawTermios.c_cc[VMIN] = 0.char
  gRawTermios.c_cc[VTIME] = 0.char
  if tcSetAttr(STDIN_FILENO, TCSANOW, gRawTermios.addr) != 0:
    raise newException(TermError, "tcsetattr failed")
  gLastW = termWidth()
  gLastH = termHeight()
  enterAltScreen()
  ## Do not inherit a scroll region or origin mode from the previous app.
  termWrite("\e[?6l\e[r")
  clearScreen()
  hideCursor()
  enableMouse()
  enableModifyOtherKeys()
  enableKittyKeyboard()
  enableBracketedPaste()
  gTermActive = true
  stdout.flushFile()

proc termShutdown*() =
  if not gTermActive: return
  disableBracketedPaste()
  disableKittyKeyboard()
  disableModifyOtherKeys()
  disableMouse()
  showCursor()
  leaveAltScreen()
  discard tcSetAttr(STDIN_FILENO, TCSANOW, gOldTermios.addr)
  gTermActive = false
  stdout.flushFile()

proc inputPending*(timeoutMs: int): bool =
  var fds: TFdSet
  FD_ZERO(fds)
  FD_SET(STDIN_FILENO, fds)
  if timeoutMs < 0:
    discard select(STDIN_FILENO + 1, fds.addr, nil, nil, nil)  # block forever
  else:
    var tv: Timeval
    tv.tv_sec = Time(timeoutMs div 1000)
    tv.tv_usec = Suseconds(1000 * (timeoutMs mod 1000))
    discard select(STDIN_FILENO + 1, fds.addr, nil, nil, tv.addr)
  FD_ISSET(STDIN_FILENO, fds) != 0

proc readByte*(): int =
  var ch: char
  if read(STDIN_FILENO, ch.addr, 1) > 0:
    return ord(ch)
  -1

proc consumeResize*(): bool =
  ## ioctl size — portable without SIGWINCH (missing on some Nim/mac builds).
  let s = measureTerm()
  if s.w != gLastW or s.h != gLastH:
    gLastW = s.w
    gLastH = s.h
    return true
  false
