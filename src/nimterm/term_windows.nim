## Native Windows terminal control for nimterm.
##
## Windows Terminal and modern ConPTY hosts accept the same ANSI byte stream
## as POSIX terminals. A classic console needs its input/output modes adjusted
## first; MSYS/Git Bash commonly exposes a pipe instead, so the byte-stream
## path also handles that case.

import std/[base64, os, osproc, strutils, terminal, winlean]
import ./backend
import ./term_common

export term_common

type
  TermError* = object of CatchableError

var
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

proc copyToClipboard*(text: string) =
  if not gTermActive: return
  ## OSC 52 is understood by Windows Terminal and most modern Git Bash hosts.
  termWrite("\e]52;c;" & encode(text) & "\a")
  stdout.flushFile()
  ## Keep a reliable fallback for classic PowerShell/conhost sessions.
  discard execCmdEx("clip.exe", input = text)

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
    if gInputModeSaved:
      discard setConsoleMode(gInputHandle, gInputMode)
      gInputModeSaved = false
    if gOutputModeSaved:
      discard setConsoleMode(gOutputHandle, gOutputMode)
      gOutputModeSaved = false
    gInputIsConsole = false
    gTermActive = false

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

proc clearNonBlockingStdio*() =
  ## POSIX pane managers can leave the terminal non-blocking; Windows console
  ## handles have no such flag, so this is a no-op here.
  discard

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
