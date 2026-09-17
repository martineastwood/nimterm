## Terminal control shared by the platform term modules.
##
## Cursor, screen, mouse, keyboard and paste sequences, the size cache, and the
## enter/leave screen handshake are identical on every platform. Only raw-mode
## setup, byte reading, interactivity probing, and the clipboard command differ,
## so those stay in the platform modules.

import std/[os, strutils, terminal]
import ./backend

var
  gTermActive* = false
  gCapabilities*: TerminalCapabilities
  gFullscreen*: bool
  gLastW, gLastH: int

const
  ## Origin mode off plus a reset scroll region, so cursor addressing stays in
  ## absolute screen coordinates.
  screenSetup = "\e[?6l\e[r"
  ## `metaSendsEscape` (DECSET 1036) is an xterm-mode setting that Windows
  ## Terminal does not implement.
  modifyOtherKeysOn = when defined(windows): "\e[>4;2m" else: "\e[>4;2m\e[?1036h"
  modifyOtherKeysOff = when defined(windows): "\e[>4;0m" else: "\e[>4;0m\e[?1036l"

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

proc consumeResize*(): bool =
  let s = measureTerm()
  if s.w != gLastW or s.h != gLastH:
    gLastW = s.w
    gLastH = s.h
    return true
  false

proc termWrite*(s: string) = stdout.write(s)

proc hideCursor() = termWrite("\e[?25l")
proc showCursor() = termWrite("\e[?25h")
proc clearScreen() = termWrite("\e[2J\e[H")

proc enableMouse(): string = "\e[?1000h\e[?1002h\e[?1006h"
proc disableMouse(): string = "\e[?1006l\e[?1002l\e[?1000l\e[?1007l"
proc enableKittyKeyboard(): string = "\e[>1u"
proc disableKittyKeyboard(): string = "\e[<u"
proc enableBracketedPaste(): string = "\e[?2004h"
proc disableBracketedPaste(): string = "\e[?2004l"

proc enableProtocols*(caps: TerminalCapabilities): string =
  if caps.mouse: result.add enableMouse()
  if caps.focusEvents: result.add "\e[?1004h"
  if caps.kittyKeyboard: result.add enableKittyKeyboard()
  elif caps.modifyOtherKeys: result.add modifyOtherKeysOn
  if caps.bracketedPaste: result.add enableBracketedPaste()

proc disableProtocols*(caps: TerminalCapabilities): string =
  if caps.bracketedPaste: result.add disableBracketedPaste()
  if caps.kittyKeyboard: result.add disableKittyKeyboard()
  elif caps.modifyOtherKeys: result.add modifyOtherKeysOff
  if caps.focusEvents: result.add "\e[?1004l"
  if caps.mouse: result.add disableMouse()

proc useAltScreen(): bool =
  let term = getEnv("TERM").toLowerAscii
  ## An empty TERM is normal in classic PowerShell/conhost and in minimal
  ## POSIX shells; both support the alternate-screen sequence.
  term.len == 0 or "xterm" in term or "screen" in term or "tmux" in term or
    "alacritty" in term or "kitty" in term or "rxvt" in term or "vt100" in term

proc enterAltScreen() =
  if useAltScreen(): termWrite("\e[?1049h")
  else: clearScreen()

proc leaveAltScreen() =
  if useAltScreen(): termWrite("\e[?1049l")
  else: clearScreen()

proc termEnterScreen*(capabilities: TerminalCapabilities, fullscreen: bool) =
  gCapabilities = capabilities
  gFullscreen = fullscreen
  gTermActive = true
  gLastW = termWidth()
  gLastH = termHeight()
  if fullscreen: enterAltScreen()
  else: termWrite("\n".repeat(gLastH) & "\e[H")
  termWrite(screenSetup)
  if fullscreen: clearScreen()
  hideCursor()
  termWrite(enableProtocols(capabilities))
  stdout.flushFile()

proc termLeaveScreen*() =
  termWrite(disableProtocols(gCapabilities))
  showCursor()
  if gFullscreen: leaveAltScreen()
  else: termWrite("\e[999B\r\n")
  stdout.flushFile()

proc terminalActive*(): bool = gTermActive
