## Semantic terminal styles. Backends decide how styles are serialized.

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
