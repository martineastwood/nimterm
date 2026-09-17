## Terminal theme colors and color-depth compilation.

import std/[os, strutils]
import std/terminal except Style
import ./style

type
  ColorDepth* = enum
    cdNone
    cd16
    cd256
    cdTrue

  ## Authored color before depth compile: "", "#rrggbb", or "0".."255".
  ## The dim token may also be the literal "dim" (SGR attribute 2).
  ThemeSpec* = object
    name*: string
    accent*, success*, error*, warning*, code*, muted*, dim*, text*: string
    heading*, model*, panelBg*, selectedBg*, selectedFg*: string

  Theme* = object
    name*: string
    colors*: bool
    accent*, success*, error*, warning*, code*, muted*, dim*, text*: Style
    heading*, model*, panelBg*, selectedBg*, selectedFg*: Style
    boldAccent*, boldError*: Style

const
  DarkSpec* = ThemeSpec(
    name: "dark",
    accent: "#00afaf",
    success: "#00af00",
    error: "#af0000",
    warning: "#afaf00",
    code: "#d7af5f",
    muted: "242",
    dim: "dim",
    text: "#c6c6c6",
    heading: "#5f87ff",
    model: "#af00af",
    panelBg: "#303030",
    selectedBg: "#5fd7ff",
    selectedFg: "#000000"
  )

  LightSpec* = ThemeSpec(
    name: "light",
    accent: "#005f87",
    success: "#008700",
    error: "#af0000",
    warning: "#af5f00",
    code: "#875f00",
    muted: "245",
    dim: "dim",
    text: "#262626",
    heading: "#5f00af",
    model: "#8700af",
    panelBg: "#e4e4e4",
    selectedBg: "#0087af",
    selectedFg: "#ffffff"
  )

var currentTheme*: Theme
var themeRevision* = 0

proc colorsOn*(t: Theme): bool =
  t.colors

proc paint*(t: Theme, style: Style, text: string): string =
  let code = style.ansi
  if not t.colors or code.len == 0: text else: code & text & "\e[0m"

proc detectDepth*(): ColorDepth =
  if getEnv("NO_COLOR").len > 0: return cdNone
  when defined(windows):
    ## Native binaries launched by mintty/Git Bash may see a pipe even though
    ## the pipe is the interactive terminal stream.
    if not stdout.isatty and getEnv("WT_SESSION").len == 0 and
        (getEnv("MSYSTEM").len == 0 or
         getEnv("TERM").toLowerAscii == "dumb"): return cdNone
  else:
    if not stdout.isatty: return cdNone
  let ct = getEnv("COLORTERM").toLowerAscii
  if ct == "truecolor" or ct == "24bit": return cdTrue
  let term = getEnv("TERM").toLowerAscii
  if term.len == 0 or term == "dumb": return cd16
  if "256color" in term or "truecolor" in term: return cd256
  if term.startsWith("xterm") or term.startsWith("screen") or
     term.startsWith("tmux") or "alacritty" in term or "kitty" in term or
     "rxvt" in term or "vt220" in term or "color" in term:
    return cd256
  cd16

proc prefersLightBackground(): bool =
  ## COLORFGBG is `fg;bg` with 0-15 ANSI indices. Bright bg (≥8) ⇒ light.
  let cfg = getEnv("COLORFGBG")
  if cfg.len == 0: return false
  let parts = cfg.split(';')
  if parts.len < 2: return false
  try:
    result = parseInt(parts[^1].strip) >= 8
  except ValueError:
    result = false

proc resolveThemeName*(name: string): string =
  let n = name.strip.toLowerAscii
  if n.len == 0 or n == "auto":
    if prefersLightBackground(): return "light"
    return "dark"
  n

proc parseHexRgb(s: string): tuple[ok: bool, r, g, b: int] =
  if s.len != 7 or s[0] != '#': return
  try:
    result.r = parseHexInt(s[1 .. 2])
    result.g = parseHexInt(s[3 .. 4])
    result.b = parseHexInt(s[5 .. 6])
    result.ok = result.r in 0 .. 255 and result.g in 0 .. 255 and
                result.b in 0 .. 255
  except ValueError:
    discard

proc rgbToAnsi16(r, g, b: int): int =
  ## Nearest of the 16 basic ANSI colors (0-15).
  ##
  ## A bit-mask conversion maps mid-tone greys to black, which makes the
  ## default muted colour disappear on dark 16-colour PowerShell consoles.
  ## Use the conventional console palette so xterm greys select dark grey
  ## (ANSI 90) instead.
  const palette: array[16, array[3, int]] = [
    [0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
    [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
    [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
    [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]
  ]
  var bestDistance = int.high
  for i in 0 ..< palette.len:
    let dr = r - palette[i][0]
    let dg = g - palette[i][1]
    let db = b - palette[i][2]
    let distance = dr * dr + dg * dg + db * db
    if distance < bestDistance:
      bestDistance = distance
      result = i

proc rgbTo256(r, g, b: int): int =
  ## Nearest xterm 256-color index (cube or grayscale).
  if r == g and g == b:
    if r < 8: return 16
    if r > 248: return 231
    return 232 + ((r - 8) * 24) div 247
  let ri = (r * 5) div 255
  let gi = (g * 5) div 255
  let bi = (b * 5) div 255
  16 + 36 * ri + 6 * gi + bi

proc colorStyle(color: ColorValue, background: bool): Style =
  if background: defaultStyle().withBackground(color)
  else: defaultStyle().withForeground(color)

proc compileColor(raw: string, depth: ColorDepth, background: bool): Style =
  if depth == cdNone: return defaultStyle()
  let v = raw.strip
  if v.len == 0: return defaultStyle()
  if v == "dim":
    return if background: defaultStyle() else: defaultStyle().withAttribute(attrDim)
  let hex = parseHexRgb(v)
  if hex.ok:
    case depth
    of cdNone: return defaultStyle()
    of cdTrue: return colorStyle(rgb(hex.r, hex.g, hex.b), background)
    of cd256: return colorStyle(ansi256(rgbTo256(hex.r, hex.g, hex.b)), background)
    of cd16: return colorStyle(ansi16(rgbToAnsi16(hex.r, hex.g, hex.b)), background)
  try:
    let idx = parseInt(v)
    if idx < 0 or idx > 255: return defaultStyle()
    case depth
    of cdNone: return defaultStyle()
    of cd16:
      var a = idx
      if idx >= 16:
        var r, g, b: int
        if idx >= 232:
          let gray = 8 + (idx - 232) * 10
          r = gray; g = gray; b = gray
        else:
          let c = idx - 16
          r = (c div 36) * 51
          g = ((c div 6) mod 6) * 51
          b = (c mod 6) * 51
        a = rgbToAnsi16(r, g, b)
      return colorStyle(ansi16(a), background)
    of cd256, cdTrue:
      return colorStyle(ansi256(idx), background)
  except ValueError:
    return defaultStyle()

proc compileTheme*(spec: ThemeSpec, depth: ColorDepth): Theme =
  if depth == cdNone:
    return Theme(name: spec.name)
  result.name = spec.name
  result.colors = true
  result.accent = compileColor(spec.accent, depth, false)
  result.success = compileColor(spec.success, depth, false)
  result.error = compileColor(spec.error, depth, false)
  result.warning = compileColor(spec.warning, depth, false)
  result.code = compileColor(spec.code, depth, false)
  result.muted = compileColor(spec.muted, depth, false)
  result.dim = compileColor(spec.dim, depth, false)
  result.text = compileColor(spec.text, depth, false)
  result.heading = compileColor(spec.heading, depth, false)
  result.heading.attributes.incl attrBold
  result.model = compileColor(spec.model, depth, false)
  if depth in {cd256, cdTrue}:
    result.panelBg = compileColor(spec.panelBg, depth, true)
    result.selectedBg = compileColor(spec.selectedBg, depth, true)
    result.selectedFg = compileColor(spec.selectedFg, depth, false)
  result.boldAccent = result.accent.withAttribute(attrBold)
  result.boldError = result.error.withAttribute(attrBold)

let Dark256* = Theme(
  name: "dark", colors: true,
  accent: defaultStyle().withForeground(ansi16(6)),
  success: defaultStyle().withForeground(ansi16(2)),
  error: defaultStyle().withForeground(ansi16(1)),
  warning: defaultStyle().withForeground(ansi16(3)),
  code: defaultStyle().withForeground(ansi256(179)),
  muted: defaultStyle().withForeground(ansi16(8)),
  dim: defaultStyle().withAttribute(attrDim),
  text: defaultStyle().withForeground(ansi16(7)),
  heading: defaultStyle().withForeground(ansi16(4)).withAttribute(attrBold),
  model: defaultStyle().withForeground(ansi16(5)),
  panelBg: defaultStyle().withBackground(ansi256(236)),
  selectedBg: defaultStyle().withBackground(ansi256(81)),
  selectedFg: defaultStyle().withForeground(ansi16(0)),
  boldAccent: defaultStyle().withForeground(ansi16(6)).withAttribute(attrBold),
  boldError: defaultStyle().withForeground(ansi16(1)).withAttribute(attrBold))

currentTheme = Dark256

proc compileBuiltinTheme*(name: string, depth: ColorDepth):
                          tuple[ok: bool, theme: Theme] =
  let resolved = resolveThemeName(name)
  case resolved
  of "dark":
    if depth == cdNone: (true, Theme(name: resolved))
    elif depth == cd256: (true, Dark256)
    else: (true, compileTheme(DarkSpec, depth))
  of "light": (true, compileTheme(LightSpec, depth))
  else: (false, Theme())

proc setTheme*(theme: Theme) =
  currentTheme = theme
  inc themeRevision
