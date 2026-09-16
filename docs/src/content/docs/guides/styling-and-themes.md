---
title: Styling and themes
description: Style terminal cells and load color palettes for different terminals.
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

Themes expose named color tokens as both ANSI strings and semantic styles:

```nim
import nimterm

let error = applyTheme("light", detectDepth())
if error.len > 0:
  quit(error)

let heading = currentTheme.themedStyle(currentTheme.heading)
let screen = newText("A light heading", heading)
```

The built-in names are `dark`, `light`, and `auto`. `auto` chooses light when
`COLORFGBG` reports a bright background, otherwise it chooses dark.

`detectDepth()` returns `cdNone` for `NO_COLOR` or non-interactive output, then
selects `cd16`, `cd256`, or `cdTrue` from the terminal environment. Pass an
explicit depth to `applyTheme` or `compileNamedTheme` when your application
already knows the target.

## Use theme tokens

`currentTheme` includes `accent`, `success`, `error`, `warning`, `code`,
`muted`, `dim`, `text`, `heading`, `model`, `panelBg`, `selectedBg`, and
`selectedFg`. Use `paint` for a string or `themedStyle` for a widget:

```nim
echo currentTheme.paint(currentTheme.success, "Saved")

let selected = currentTheme.themedStyle(
  currentTheme.selectedFg,
  currentTheme.selectedBg,
  {attrBold})
let menu = newMenu(@[MenuItem(label: "Saved")], selectedStyle = selected)
```

`colorsOn()` tells you whether a compiled theme emits ANSI sequences. When
colors are off, `paint` returns the input text unchanged.

## Add a custom theme

Create a JSON file under either `~/.nimterm/themes/` or
`<workspace>/.nimterm/themes/`:

```json
{
  "name": "seafoam",
  "colors": {
    "accent": "#00afaf",
    "success": "#00af00",
    "error": "#af0000",
    "warning": "#afaf00",
    "code": "#d7af5f",
    "muted": "242",
    "dim": "dim",
    "text": "#c6c6c6",
    "heading": "#5f87ff",
    "model": "#af00af",
    "panelBg": "#303030",
    "selectedBg": "#5fd7ff",
    "selectedFg": "#000000"
  }
}
```

Every token is required. Values can be `#rrggbb`, an ANSI 256 index from
`0` through `255`, or `"dim"` for the dim attribute. Theme names cannot
contain `/`.

Workspace themes override global themes with the same name. Use custom roots
when your application stores its configuration elsewhere:

```nim
import std/os
import nimterm

let names = listThemeNames(
  workspace = getCurrentDir(),
  appDir = ".my-app",
  globalDir = getHomeDir() / ".my-app")
let error = applyTheme(
  "seafoam",
  workspace = getCurrentDir(),
  appDir = ".my-app",
  globalDir = getHomeDir() / ".my-app")
```

Theme discovery is cached. Call `clearThemeNameCache()` after adding or
removing files if the same process must see the new list. Themes are not hot
reloaded during rendering.

## Next steps

- [Text and Markdown](/guides/text-and-markdown/) for ANSI-aware rendering.
- [Widgets](/guides/widgets/) for passing styles through built-in widgets.
- [API reference](/reference/api/nimterm/theme/) for all theme procedures.
