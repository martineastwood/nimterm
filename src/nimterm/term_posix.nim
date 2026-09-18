## POSIX terminal control for nimterm.

import std/[base64, osproc, terminal]
import posix
import posix/termios
import ./backend
import ./term_common

export term_common

type
  TermError* = object of CatchableError

var
  gOldTermios: Termios
  gRawTermios: Termios

proc copyToClipboard*(text: string) =
  if not gTermActive: return
  termWrite("\e]52;c;" & encode(text) & "\a")
  stdout.flushFile()
  when defined(macosx):
    discard execCmdEx("pbcopy", input = text)

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
  try:
    termEnterScreen(capabilities, fullscreen)
  except CatchableError:
    termShutdown()
    raise

proc termShutdown*() =
  if not gTermActive: return
  try:
    termLeaveScreen()
  finally:
    discard tcSetAttr(STDIN_FILENO, TCSANOW, gOldTermios.addr)
    gTermActive = false

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

proc terminalInputIsInteractive*(): bool = stdin.isatty
proc terminalOutputIsInteractive*(): bool = stdout.isatty
proc terminalIsInteractive*(): bool =
  terminalInputIsInteractive() and terminalOutputIsInteractive()

proc clearNonBlockingStdio*() =
  ## Pane managers (e.g. herdr) can leave the terminal non-blocking; stdio
  ## then fails with EAGAIN instead of blocking, which crashes any TUI write
  ## or read that races the host's drain. TUIs need a blocking terminal, so
  ## clear the flag on every TTY stdio descriptor. Pipes are left alone.
  for fd in [cint(STDIN_FILENO), cint(STDOUT_FILENO), cint(STDERR_FILENO)]:
    if posix.isatty(fd) != 0:
      let flags = fcntl(fd, F_GETFL, 0)
      if flags >= 0:
        discard fcntl(fd, F_SETFL, flags and not O_NONBLOCK)
