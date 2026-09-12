## Shared terminal input decoder.
##
## Reads bytes from term (posix raw stdin) and turns them into keys /
## mouse events.

import std/strutils
import ./events
import ./keys

type
  ByteReader* = proc(timeoutMs: int): int {.closure.}

  InputDecoder* = object
    buffer: string
    escapeStartedMs: int64

  MouseKind* = enum
    mouseNone
    mousePress    ## left button down
    mouseRelease  ## left button up
    mouseDrag     ## motion while left button held

  FocusKind* = enum
    focusNone
    focusIn
    focusOut

  InputEvent* = object
    key*: Key
    ch*: char           ## ASCII keyChar; prefer `text` for insert
    text*: string       ## UTF-8 rune or a whole paste
    scrollDelta*: int   ## +N scroll up (older), -N scroll down (newer)
    resized*: bool
    mouse*: MouseKind
    button*: UiMouseButton
    shift*: bool
    alt*: bool
    ctrl*: bool
    mouseX*: int        ## 0-based column
    mouseY*: int        ## 0-based row
    focus*: FocusKind

proc normalizePasteText*(s: string): string =
  ## CR LF / CR → LF so a paste never submits.
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '\r':
      result.add '\n'
      if i + 1 < s.len and s[i + 1] == '\n':
        inc i
    else:
      result.add s[i]
    inc i

proc utf8SeqLen(b: int): int =
  if b <= 0x7F: 1
  elif (b and 0xE0) == 0xC0: 2
  elif (b and 0xF0) == 0xE0: 3
  elif (b and 0xF8) == 0xF0: 4
  else: 1

proc readUtf8Text(first: int, readNext: ByteReader): string =
  let n = utf8SeqLen(first)
  result = $char(first)
  for _ in 2 .. n:
    let b = readNext(50)
    if b < 0: return
    result.add char(b)

proc charEvent(s: string): InputEvent =
  result.key = keyChar
  result.text = s
  if s.len == 1:
    result.ch = s[0]

proc parseSgrMouse(params: string, press: bool): InputEvent =
  ## SGR mouse: ESC [ < btn ; x ; y M/m  (coords are 1-based).
  let parts = params.split(';')
  if parts.len < 3:
    return
  var btn, x, y: int
  try:
    btn = parseInt(parts[0])
    x = parseInt(parts[1])
    y = parseInt(parts[2])
  except ValueError:
    return
  result.mouseX = max(0, x - 1)
  result.mouseY = max(0, y - 1)
  result.shift = (btn and 4) != 0
  result.alt = (btn and 8) != 0
  result.ctrl = (btn and 16) != 0

  # Wheel: bit 6 set. Low bit selects direction (0=up, 1=down).
  if (btn and 64) != 0:
    if (btn and 1) != 0:
      result.scrollDelta = -3
    else:
      result.scrollDelta = 3
    return

  let button = btn and 3
  result.button = case button
    of 0: umbLeft
    of 1: umbMiddle
    of 2: umbRight
    else: umbNone

  if not press:
    result.mouse = mouseRelease
  elif (btn and 32) != 0:
    result.mouse = mouseDrag
  else:
    result.mouse = mousePress

proc ctrlKey(b: int): Key =
  case b
  of 1: keyCtrlA
  of 2: keyCtrlB
  of 3: keyCtrlC
  of 4: keyCtrlD
  of 5: keyCtrlE
  of 6: keyCtrlF
  of 7: keyCtrlG
  of 8: keyCtrlH
  of 9: keyTab
  of 11: keyCtrlK
  of 12: keyCtrlL
  of 14: keyCtrlN
  of 15: keyCtrlO
  of 16: keyCtrlP
  of 17: keyCtrlQ
  of 18: keyCtrlR
  of 19: keyCtrlS
  of 20: keyCtrlT
  of 21: keyCtrlU
  of 22: keyCtrlV
  of 23: keyCtrlW
  of 24: keyCtrlX
  of 25: keyCtrlY
  of 26: keyCtrlZ
  else: keyNone

proc modifiedKey(seq: string): tuple[code, mods: int] =
  if seq.startsWith("27;") and seq.endsWith("~"):
    let parts = seq[3 ..< seq.len - 1].split(';')
    if parts.len != 2: return
    try:
      result = (parseInt(parts[1]), parseInt(parts[0]))
    except ValueError:
      discard
  elif seq.endsWith("u") and ';' in seq:
    let parts = seq[0 ..< seq.len - 1].split(';')
    if parts.len != 2: return
    try:
      result = (parseInt(parts[0]), parseInt(parts[1]))
    except ValueError:
      discard

proc isModifiedPaste*(seq: string): bool =
  ## Ctrl/Cmd+V as xterm modifyOtherKeys (`27;5;118~`) or CSI-u (`118;5u`).
  let (code, mods) = modifiedKey(seq)
  if code notin {86, 118}: return false
  let bits = mods - 1
  bits > 0 and (bits and (4 or 8)) != 0  # ctrl and/or cmd/meta

proc isModifiedCopy(seq: string): bool =
  ## Ctrl/Cmd+Shift+C as xterm modifyOtherKeys or CSI-u.
  let (code, mods) = modifiedKey(seq)
  if code notin {67, 99}: return false
  let bits = mods - 1
  let commandCopy = (bits and 8) != 0 and (bits and 4) == 0
  let ctrlShiftCopy = (bits and 4) != 0 and (bits and 1) != 0
  commandCopy or ctrlShiftCopy

proc modifiedCtrlO(seq: string): bool =
  ## Ctrl-O under kitty keyboard / modifyOtherKeys.
  let (code, mods) = modifiedKey(seq)
  code == ord('o') and ((mods - 1) and 4) != 0

proc readBracketedPaste(readNext: ByteReader): InputEvent =
  ## Bytes between ESC [ 200 ~ and ESC [ 201 ~.
  var acc = ""
  while true:
    let b = readNext(500)
    if b < 0:
      break
    if b == 0x1b:
      let n1 = readNext(50)
      if n1 != ord('['):
        continue
      var seq = ""
      while true:
        let x = readNext(50)
        if x < 0: break
        seq.add char(x)
        if char(x) == '~': break
      if seq == "201~":
        break
      continue
    if b == 9 or b >= 32 or b == 10 or b == 13:
      acc.add char(b)
  let text = normalizePasteText(acc)
  # Cmd+V of an image often arrives as an empty bracketed paste.
  if text.strip.len == 0:
    result.key = keyCtrlV
    return
  result = charEvent(text)

proc readEscapeSequence(readNext: ByteReader): InputEvent =
  ## Called after ESC has already been consumed.
  let ch2 = readNext(50)
  if ch2 < 0:
    result.key = keyEscape
    return
  # Option/Alt+Enter (common on macOS): ESC then CR/LF → follow-up.
  if ch2 == ord('\r') or ch2 == ord('\n'):
    result.key = keyAltEnter
    return
  if ch2 == ord('b') or ch2 == ord('B'):
    result.key = keyAltB
    return
  if ch2 == ord('f') or ch2 == ord('F'):
    result.key = keyAltF
    return
  if ch2 == ord('d') or ch2 == ord('D'):
    result.key = keyAltD
    return
  if ch2 == ord('O'):
    let ch3 = readNext(50)
    if ch3 < 0: return
    case ch3.char
    of 'A': result.key = keyUp
    of 'B': result.key = keyDown
    of 'C': result.key = keyRight
    of 'D': result.key = keyLeft
    of 'H': result.key = keyHome
    of 'F': result.key = keyEnd
    of 'P': result.key = keyF1
    of 'Q': result.key = keyF2
    of 'R': result.key = keyF3
    of 'S': result.key = keyF4
    else: discard
    return
  if ch2 != ord('['):
    return
  let ch3 = readNext(50)
  if ch3 < 0: return
  if ch3 == ord('I'):
    result.focus = focusIn
    return
  if ch3 == ord('O'):
    result.focus = focusOut
    return
  # SGR mouse: ESC [ < btn ; x ; y M/m
  if ch3 == ord('<'):
    var params = ""
    while true:
      let b = readNext(50)
      if b < 0: return
      if b == ord('M') or b == ord('m'):
        return parseSgrMouse(params, press = b == ord('M'))
      params.add char(b)
    return
  case ch3.char
  of 'A': result.key = keyUp
  of 'B': result.key = keyDown
  of 'C': result.key = keyRight
  of 'D': result.key = keyLeft
  of 'H': result.key = keyHome
  of 'F': result.key = keyEnd
  of 'Z': result.key = keyShiftTab
  else:
    var seq = $ch3.char
    while true:
      let b = readNext(50)
      if b < 0: return
      let c = char(b)
      seq.add c
      if c in {'~', 'A'..'Z', 'a'..'z'}:
        break
    # Shift+Enter / modified Enter variants (xterm, kitty, modifyOtherKeys).
    if seq in ["13;3u", "27;3;13~", "13;3;13~"]:
      result.key = keyAltEnter
    elif seq in ["13;2~", "13;2u", "27;2;13~", "13;2;13~"]:
      result.key = keyShiftEnter
    elif seq.startsWith("27;") and seq.endsWith(";13~"):
      # ESC [ 27 ; <mods> ; 13 ~  — any modifier+Enter → newline (not bare Enter)
      result.key = keyShiftEnter
    elif seq in ["9;2u", "27;2;9~", "1;2Z"]:
      result.key = keyShiftTab
    elif isModifiedPaste(seq):
      result.key = keyCtrlV
    elif isModifiedCopy(seq):
      result.key = keyCopy
    elif modifiedCtrlO(seq):
      result.key = keyCtrlO
    elif seq == "200~":
      return readBracketedPaste(readNext)
    elif seq == "3~": result.key = keyDelete
    elif seq == "2~": result.key = keyInsert
    elif seq == "1~" or seq == "7~": result.key = keyHome
    elif seq == "4~" or seq == "8~": result.key = keyEnd
    elif seq == "5~": result.key = keyPageUp
    elif seq == "6~": result.key = keyPageDown
    elif seq in ["11~", "1P"]: result.key = keyF1
    elif seq in ["12~", "1Q"]: result.key = keyF2
    elif seq in ["13~", "1R"]: result.key = keyF3
    elif seq in ["14~", "1S"]: result.key = keyF4
    elif seq == "15~": result.key = keyF5
    elif seq == "17~": result.key = keyF6
    elif seq == "18~": result.key = keyF7
    elif seq == "19~": result.key = keyF8
    elif seq == "20~": result.key = keyF9
    elif seq == "21~": result.key = keyF10
    elif seq == "23~": result.key = keyF11
    elif seq == "24~": result.key = keyF12
    elif seq in ["1;3A"]: result.key = keyAltUp
    elif seq in ["1;3D", "1;5D"]: result.key = keyAltB
    elif seq in ["1;3C", "1;5C"]: result.key = keyAltF

proc decodeInput*(b: int, readNext: ByteReader): InputEvent =
  if b < 0:
    result.key = keyNone
    return
  if b == 0x1b:
    return readEscapeSequence(readNext)
  # Enter is CR and/or LF depending on the terminal — both submit.
  # Newlines come only from Shift+Enter or bracketed paste.
  if b == ord('\r') or b == ord('\n'):
    result.key = keyEnter
    return
  if b == 127 or b == 8:
    result.key = keyBackspace
    return
  if b == 9:
    result.key = keyTab
    return
  if b >= 1 and b <= 26:
    result.key = ctrlKey(b)
    return
  if b >= 32 and b <= 126:
    return charEvent($char(b))
  if b >= 0x80:
    return charEvent(readUtf8Text(b, readNext))
  result.key = keyNone

proc feed*(decoder: var InputDecoder, bytes: string) =
  decoder.buffer.add bytes

proc pending*(decoder: InputDecoder): bool = decoder.buffer.len > 0

proc escapeWaitMs*(decoder: InputDecoder, nowMs: int64,
                   timeoutMs = 15): int =
  if decoder.buffer.len == 0 or decoder.buffer[0] != '\e': return -1
  if decoder.escapeStartedMs <= 0: return timeoutMs
  max(0, timeoutMs - int(nowMs - decoder.escapeStartedMs))

proc sequenceLength(decoder: var InputDecoder, nowMs: int64,
                    escapeTimeoutMs: int): int =
  let bytes = decoder.buffer
  if bytes.len == 0: return 0
  let first = bytes[0].ord
  if first != 0x1b:
    let needed = utf8SeqLen(first)
    return if bytes.len >= needed: needed else: 0
  if decoder.escapeStartedMs <= 0: decoder.escapeStartedMs = nowMs
  if bytes.len == 1: return if nowMs - decoder.escapeStartedMs >= escapeTimeoutMs: 1 else: 0
  if bytes[1] == 'O':
    if bytes.len >= 3: return 3
  elif bytes[1] == '[':
    if bytes.startsWith("\e[200~"):
      let finish = bytes.find("\e[201~", 6)
      if finish >= 0: return finish + 6
    elif bytes.len >= 3:
      for i in 2 ..< bytes.len:
        if bytes[i].ord in 0x40 .. 0x7e: return i + 1
  else:
    return 2
  if nowMs - decoder.escapeStartedMs >= escapeTimeoutMs: return 1

proc nextEvent*(decoder: var InputDecoder, nowMs: int64,
                escapeTimeoutMs = 15): InputEvent =
  let length = decoder.sequenceLength(nowMs, escapeTimeoutMs)
  if length == 0: return InputEvent(key: keyNone)
  let bytes = decoder.buffer[0 ..< length]
  decoder.buffer.delete(0 ..< length)
  decoder.escapeStartedMs = 0
  var index = 1
  proc nextByte(timeoutMs: int): int =
    discard timeoutMs
    if index >= bytes.len: return -1
    result = bytes[index].ord
    inc index
  decodeInput(bytes[0].ord, nextByte)

proc toUiEvent*(input: InputEvent, width = 0, height = 0): UiEvent =
  if input.resized:
    return UiEvent(kind: uiResize, width: width, height: height)
  if input.focus != focusNone:
    return UiEvent(kind: uiFocus, focused: input.focus == focusIn)
  if input.mouse != mouseNone or input.scrollDelta != 0:
    return UiEvent(kind: uiMouse, x: input.mouseX, y: input.mouseY,
      mouse: case input.mouse
        of mousePress: umPress
        of mouseRelease: umRelease
        of mouseDrag: umDrag
        of mouseNone: umScroll,
      scrollDelta: input.scrollDelta, button: input.button,
      shift: input.shift, alt: input.alt, ctrl: input.ctrl)
  if input.key != keyNone:
    return UiEvent(kind: uiKey, key: input.key, text: input.text)
