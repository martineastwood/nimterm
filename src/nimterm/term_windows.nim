## Native Windows terminal control for nimterm.
##
## Windows Terminal and modern ConPTY hosts accept the same ANSI byte stream
## as POSIX terminals. A classic console needs its input/output modes adjusted
## first; MSYS/Git Bash commonly exposes a pipe instead, so the byte-stream
## path also handles that case.

import std/[base64, os, osproc, strutils, terminal, winlean]
import ./backend

type
  TermError* = object of CatchableError

var
  gTermActive = false
  gLastW, gLastH: int
  gCapabilities: TerminalCapabilities
  gFullscreen: bool
  gInputHandle: Handle
  gOutputHandle: Handle
  gInputMode: DWORD
  gOutputMode: DWORD
  gInputModeSaved = false
  gOutputModeSaved = false
  gInputIsConsole = false

const
  fileTypeDisk = 1.DWORD
  fileTypeChar = 2.DWORD
  fileTypePipe = 3.DWORD

proc getFileType(handle: Handle): DWORD {.importc: "GetFileType", stdcall,
    dynlib: "kernel32", sideEffect.}

proc validHandle(handle: Handle): bool =
  handle != INVALID_HANDLE_VALUE and handle != 0

proc winConsoleMode(handle: Handle, mode: var DWORD): bool =
  validHandle(handle) and getConsoleMode(handle, addr mode) != 0

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
  ## OSC 52 is understood by Windows Terminal and most modern Git Bash hosts.
  termWrite("\e]52;c;" & encode(text) & "\a")
  stdout.flushFile()
  ## Keep a reliable fallback for classic PowerShell/conhost sessions.
  discard execCmdEx("clip.exe", input = text)

proc hideCursor() = termWrite("\e[?25l")
proc showCursor() = termWrite("\e[?25h")
proc clearScreen() = termWrite("\e[2J\e[H")

proc enableMouse(): string = "\e[?1000h\e[?1002h\e[?1006h"
proc disableMouse(): string = "\e[?1006l\e[?1002l\e[?1000l\e[?1007l"
proc enableKittyKeyboard(): string = "\e[>1u"
proc disableKittyKeyboard(): string = "\e[<u"
proc enableModifyOtherKeys(): string = "\e[>4;2m"
proc disableModifyOtherKeys(): string = "\e[>4;0m"
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
  let term = getEnv("TERM").toLowerAscii
  ## An empty TERM is normal in classic PowerShell/conhost and still supports
  ## the Windows alternate-screen sequence once VT processing is enabled.
  term.len == 0 or "xterm" in term or "screen" in term or "tmux" in term or
    "alacritty" in term or "kitty" in term or "rxvt" in term or
    "vt100" in term

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

  gInputHandle = getStdHandle(STD_INPUT_HANDLE)
  gOutputHandle = getStdHandle(STD_OUTPUT_HANDLE)
  gInputModeSaved = false
  gOutputModeSaved = false
  gInputIsConsole = winConsoleMode(gInputHandle, gInputMode)
  if gInputIsConsole:
    ## Read UTF-8/ANSI bytes from the console. Disabling processed input lets
    ## Ctrl-C reach the shared decoder as byte 3 instead of terminating Nimlet.
    var mode = gInputMode and not (ENABLE_ECHO_INPUT or ENABLE_LINE_INPUT or
      ENABLE_PROCESSED_INPUT)
    mode = mode or ENABLE_VIRTUAL_TERMINAL_INPUT
    if setConsoleMode(gInputHandle, mode) == 0:
      raiseOSError(osLastError())
    gInputModeSaved = true
  if winConsoleMode(gOutputHandle, gOutputMode):
    let mode = gOutputMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING or
      DISABLE_NEWLINE_AUTO_RETURN
    if setConsoleMode(gOutputHandle, mode) == 0:
      if gInputModeSaved:
        discard setConsoleMode(gInputHandle, gInputMode)
        gInputModeSaved = false
      raiseOSError(osLastError())
    gOutputModeSaved = true

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
    if gInputModeSaved:
      discard setConsoleMode(gInputHandle, gInputMode)
      gInputModeSaved = false
    if gOutputModeSaved:
      discard setConsoleMode(gOutputHandle, gOutputMode)
      gOutputModeSaved = false
    gInputIsConsole = false
    gTermActive = false

proc terminalActive*(): bool = gTermActive
proc suspendTerminal*() = termShutdown()
proc resumeTerminal*() =
  if not gTermActive: termInit(gCapabilities, gFullscreen)

proc inputConsoleHandle*(): Handle = gInputHandle
proc inputIsConsole*(): bool = gInputIsConsole

proc terminalInputIsInteractive*(): bool =
  if stdin.isatty: return true
  var mode: DWORD
  if winConsoleMode(getStdHandle(STD_INPUT_HANDLE), mode): return true
  ## A native binary launched from mintty may see an MSYS pipe rather than a
  ## console. Treat an idle pipe as the terminal, but preserve piped stdin
  ## when data is already available.
  if getEnv("MSYSTEM").len > 0 and getEnv("TERM").len > 0 and
      getEnv("TERM").toLowerAscii != "dumb":
    let handle = getStdHandle(STD_INPUT_HANDLE)
    let fileType = getFileType(handle)
    if fileType == fileTypeDisk or fileType == fileTypeChar: return false
    if fileType != fileTypePipe: return false
    var available: int32
    if peekNamedPipe(handle, nil, 0, nil, addr available, nil) and
        available > 0:
      return false
    return true
  false

proc terminalOutputIsInteractive*(): bool =
  if stdout.isatty: return true
  var mode: DWORD
  if winConsoleMode(getStdHandle(STD_OUTPUT_HANDLE), mode): return true
  if getFileType(getStdHandle(STD_OUTPUT_HANDLE)) == fileTypeDisk:
    return false
  getEnv("MSYSTEM").len > 0 and getEnv("TERM").len > 0 and
    getEnv("TERM").toLowerAscii != "dumb"

proc terminalIsInteractive*(): bool =
  terminalInputIsInteractive() and terminalOutputIsInteractive()

proc inputPending*(timeoutMs: int): bool =
  ## The Windows backend performs the timed wait because it also has to wake
  ## for application events. This proc intentionally only probes input.
  discard timeoutMs
  if not validHandle(gInputHandle): return false
  if gInputIsConsole:
    return waitForSingleObject(gInputHandle, 0) == WAIT_OBJECT_0
  var available: int32
  if peekNamedPipe(gInputHandle, nil, 0, nil, addr available, nil):
    return available > 0
  ## Regular files are immediately readable; EOF is handled by readByte().
  waitForSingleObject(gInputHandle, 0) == WAIT_OBJECT_0

proc readByte*(): int =
  if not validHandle(gInputHandle): return -1
  var ch: char
  var count: int32
  if readFile(gInputHandle, addr ch, 1, addr count, nil) != 0 and count > 0:
    return ord(ch)
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
