## POSIX terminal backend.

when defined(windows):
  {.error: "platform_posix is unavailable on Windows".}

import std/[monotimes, os, strutils]
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
  PosixBackend* = ref object of TerminalBackend
    capabilities*: TerminalCapabilities
    decoder: InputDecoder

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

proc sameColor(a, b: ColorValue): bool =
  a.kind == b.kind and a.value == b.value and a.r == b.r and a.g == b.g and
    a.b == b.b

proc sameStyle(a, b: Style): bool =
  sameColor(a.foreground, b.foreground) and sameColor(a.background, b.background) and
    a.attributes == b.attributes

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

proc newPosixBackend*(capabilities = detectTerminalCapabilities()): TerminalBackend =
  PosixBackend(capabilities: capabilities)

method init*(backend: PosixBackend) =
  termInit(backend.capabilities)

method shutdown*(backend: PosixBackend) =
  discard backend
  termShutdown()

method size*(backend: PosixBackend): Size =
  discard backend
  size(termWidth(), termHeight())

method readEvent*(backend: PosixBackend, timeoutMs: int): UiEvent =
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
    if inputPending(wait): backend.decoder.feed(readAvailable())
    elif consumeResize():
      return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
    input = backend.decoder.nextEvent(getMonoTime().ticks div 1_000_000)
  input.toUiEvent(termWidth(), termHeight())

method present*(backend: PosixBackend, frame: Canvas) =
  discard backend
  var output = newStringOfCap(frame.size.w * frame.size.h * 2)
  output.add "\e[H"
  var activeStyle = defaultStyle()
  var hasStyle = false
  for y in 0 ..< frame.size.h:
    output.add "\e["
    output.add $(y + 1)
    output.add ";1H"
    for x in 0 ..< frame.size.w:
      let cell = frame.getCell(x, y)
      if not hasStyle or not sameStyle(activeStyle, cell.style):
        output.add "\e[0m"
        output.add sgr(cell.style)
        activeStyle = cell.style
        hasStyle = true
      if not cell.continuation: output.add toUTF8(cell.glyph) & cell.combining
      if attrStrikethrough in cell.style.attributes and cell.glyph.int != 32:
        ## Some terminal emulators ignore SGR 9; draw a visible fallback.
        output.add "\u0336"
  output.add "\e[0m"
  stdout.write(output)
  stdout.flushFile()
