## POSIX terminal backend.

when defined(windows):
  {.error: "platform_posix is unavailable on Windows".}

import std/strutils
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

proc newPosixBackend*(): TerminalBackend =
  PosixBackend()

method init*(backend: PosixBackend) =
  discard backend
  termInit()

method shutdown*(backend: PosixBackend) =
  discard backend
  termShutdown()

method size*(backend: PosixBackend): Size =
  discard backend
  size(termWidth(), termHeight())

method readEvent*(backend: PosixBackend, timeoutMs: int): UiEvent =
  discard backend
  let input = readInputEvent(timeoutMs)
  if input.resized:
    return UiEvent(kind: uiResize, width: termWidth(), height: termHeight())
  if input.mouse != mouseNone or input.scrollDelta != 0:
    result.kind = uiMouse
    result.x = input.mouseX
    result.y = input.mouseY
    result.mouse = case input.mouse
      of mousePress: umPress
      of mouseRelease: umRelease
      of mouseDrag: umDrag
      of mouseNone: umScroll
    result.scrollDelta = input.scrollDelta
    return
  if input.key != keyNone:
    result.kind = uiKey
    result.key = input.key
    result.text = input.text

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
      output.add toUTF8(cell.glyph)
      if attrStrikethrough in cell.style.attributes and cell.glyph.int != 32:
        ## Some terminal emulators ignore SGR 9; draw a visible fallback.
        output.add "\u0336"
  output.add "\e[0m"
  stdout.write(output)
  stdout.flushFile()
