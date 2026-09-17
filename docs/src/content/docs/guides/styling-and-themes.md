---
title: Styling and themes
description: Style terminal cells and compile color palettes for different terminals.
---

nimterm keeps styles semantic until the backend presents a frame. You can use
the same widget styles with ANSI 16 colors, ANSI 256 colors, truecolor, or no
color output.

## Build a style

Use `withForeground`, `withBackground`, and `withAttribute` to derive a style:

```nim
import nimterm

let accent = defaultStyle()
  .withForeground(ansi256(81))
  .withAttribute(attrBold)
let panel = accent.withBackground(rgb(32, 36, 42))

let screen = newPanel(
  newText("Connected", panel),
  title = "Status",
  borderStyle = accent)
```

`defaultStyle` uses the terminal's default foreground and background. Color
values are clamped to their valid ranges: `ansi16` accepts 0 through 15,
`ansi256` accepts 0 through 255, and `rgb` accepts 0 through 255 per channel.

Available attributes are `attrBold`, `attrDim`, `attrItalic`, `attrUnderline`,
`attrReverse`, and `attrStrikethrough`.

## Use the built-in themes

Themes expose named semantic styles:

```nim
import nimterm

let compiled = compileBuiltinTheme("light", detectDepth())
if not compiled.ok: quit("unknown theme")
setTheme(compiled.theme)

let screen = newText("A light heading", currentTheme.heading)
```

The built-in names are `dark`, `light`, and `auto`. `auto` chooses light when
`COLORFGBG` reports a bright background, otherwise it chooses dark.

`detectDepth()` returns `cdNone` for `NO_COLOR` or non-interactive output, then
selects `cd16`, `cd256`, or `cdTrue` from the terminal environment. Pass an
explicit depth to `compileBuiltinTheme` when your application already knows
the target.

## Use theme tokens

`currentTheme` includes `accent`, `boldAccent`, `success`, `error`, `boldError`,
`warning`, `code`, `muted`, `dim`, `text`, `heading`, `model`, `panelBg`,
`selectedBg`, and `selectedFg`. Use `paint` for console text and styles
directly for widgets:

```nim
echo currentTheme.paint(currentTheme.success, "Saved")

let selected = currentTheme.selectedFg
  .overlay(currentTheme.selectedBg)
  .withAttribute(attrBold)
let menu = newMenu(@[MenuItem(label: "Saved")], selectedStyle = selected)
```

`colorsOn()` tells you whether a compiled theme emits ANSI sequences. When
colors are off, `paint` returns the input text unchanged. `themeRevision`
increments whenever `setTheme` installs a new palette, which is useful when
widgets cache compiled styles.

## Compile a custom theme

Define a `ThemeSpec`, compile it for the terminal, and install it:

```nim
import nimterm

let spec = ThemeSpec(
  name: "seafoam",
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
  selectedFg: "#000000")

setTheme(compileTheme(spec, detectDepth()))
```

Values can be `#rrggbb`, an ANSI 256 index from `0` through `255`, or `"dim"`
for the dim attribute. Your application decides where theme specifications
come from, so `nimterm` does not read configuration files or cache theme names.

## Next steps

- [Text and Markdown](/guides/text-and-markdown/) for styled rendering.
- [Widgets](/guides/widgets/) for passing styles through built-in widgets.
- [API reference](/reference/api/nimterm/theme/) for all theme procedures.
