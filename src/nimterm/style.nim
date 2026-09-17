## Semantic terminal styles.

import std/strutils

type
  ColorKind* = enum
    colorDefault
    colorAnsi16
    colorAnsi256
    colorRgb

  ColorValue* = object
    kind*: ColorKind
    value*: int
    r*: int
    g*: int
    b*: int

  TextAttribute* = enum
    attrBold
    attrDim
    attrItalic
    attrUnderline
    attrReverse
    attrStrikethrough

  Style* = object
    foreground*: ColorValue
    background*: ColorValue
    attributes*: set[TextAttribute]

proc defaultColor*(): ColorValue = ColorValue(kind: colorDefault)

proc ansi16*(index: int): ColorValue =
  ColorValue(kind: colorAnsi16, value: max(0, min(15, index)))

proc ansi256*(index: int): ColorValue =
  ColorValue(kind: colorAnsi256, value: max(0, min(255, index)))

proc rgb*(r, g, b: int): ColorValue =
  ColorValue(kind: colorRgb, r: max(0, min(255, r)),
    g: max(0, min(255, g)), b: max(0, min(255, b)))

proc defaultStyle*(): Style =
  Style(foreground: defaultColor(), background: defaultColor())

proc withForeground*(style: Style, color: ColorValue): Style =
  result = style
  result.foreground = color

proc withBackground*(style: Style, color: ColorValue): Style =
  result = style
  result.background = color

proc withAttribute*(style: Style, attribute: TextAttribute): Style =
  result = style
  result.attributes.incl attribute

proc overlay*(style, overlay: Style): Style =
  result = style
  if overlay.foreground.kind != colorDefault: result.foreground = overlay.foreground
  if overlay.background.kind != colorDefault: result.background = overlay.background
  result.attributes = result.attributes + overlay.attributes

proc addColor(params: var seq[string], color: ColorValue, base: int) =
  case color.kind
  of colorDefault: discard
  of colorAnsi16:
    params.add $(if color.value < 8: base + color.value
      else: base + 60 + color.value - 8)
  of colorAnsi256:
    params.add $(base + 8) & ";5;" & $color.value
  of colorRgb:
    params.add $(base + 8) & ";2;" & $color.r & ";" & $color.g & ";" & $color.b

proc ansi*(style: Style): string =
  var params: seq[string]
  if attrBold in style.attributes: params.add "1"
  if attrDim in style.attributes: params.add "2"
  if attrItalic in style.attributes: params.add "3"
  if attrUnderline in style.attributes: params.add "4"
  if attrReverse in style.attributes: params.add "7"
  if attrStrikethrough in style.attributes: params.add "9"
  params.addColor(style.foreground, 30)
  params.addColor(style.background, 40)
  if params.len > 0: "\e[" & params.join(";") & "m" else: ""

proc styleFromSgr*(code: string): Style =
  result = defaultStyle()
  if code.len < 4 or code[0] != '\e' or code[1] != '[' or code[^1] != 'm': return
  let parts = code[2 ..< code.high].split(';')
  var i = 0
  while i < parts.len:
    try:
      let value = parseInt(parts[i])
      case value
      of 1: result.attributes.incl attrBold
      of 2: result.attributes.incl attrDim
      of 3: result.attributes.incl attrItalic
      of 4: result.attributes.incl attrUnderline
      of 7: result.attributes.incl attrReverse
      of 9: result.attributes.incl attrStrikethrough
      of 30 .. 37: result.foreground = ansi16(value - 30)
      of 90 .. 97: result.foreground = ansi16(value - 82)
      of 40 .. 47: result.background = ansi16(value - 40)
      of 100 .. 107: result.background = ansi16(value - 92)
      of 38, 48:
        let background = value == 48
        if i + 2 < parts.len and parts[i + 1] == "5":
          let color = ansi256(parseInt(parts[i + 2]))
          if background: result.background = color else: result.foreground = color
          i += 2
        elif i + 4 < parts.len and parts[i + 1] == "2":
          let color = rgb(parseInt(parts[i + 2]), parseInt(parts[i + 3]),
            parseInt(parts[i + 4]))
          if background: result.background = color else: result.foreground = color
          i += 4
      else: discard
    except ValueError:
      discard
    inc i
