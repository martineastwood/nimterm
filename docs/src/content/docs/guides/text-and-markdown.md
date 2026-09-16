---
title: Text and Markdown
description: Render styled text, Unicode, ANSI sequences, and Markdown in terminal cells.
---

Terminal columns are not the same as string length. nimterm includes helpers
that account for ANSI escape sequences, wide Unicode characters, combining
marks, and semantic cell styles.

## Measure and wrap text

Use `displayWidth` for plain text and `ansiVisibleWidth` for text that may
contain ANSI escapes:

```nim
import nimterm

assert displayWidth("界") == 2
assert ansiVisibleWidth("\e[31mred\e[0m") == 3

let lines = wrapAnsi("\e[36mA long label\e[0m", 8, preferSpaces = true)
```

`wrapAnsi` keeps escape sequences with the text they style and wraps to the
requested visible width. `stripAnsi` removes escape sequences when you need
plain text for logs, search, or copied content.

## Paint a canvas

`Canvas` is a grid of `Cell` values. Write text at a coordinate, clear or fill
an area, then inspect the result or pass it to a backend:

```nim
let canvasSize = size(20, 2)
var canvas = newCanvas(canvasSize)
canvas.writeText(0, 0, "Ready")
canvas.writeText(0, 1, "界")

echo canvas.plainText
```

`writeText` assigns a semantic `Style` to each glyph. Wide glyphs reserve a
continuation cell. Combining marks are attached to the preceding cell.
Out-of-bounds writes are ignored, so a widget can write within its assigned
area without manually clipping every coordinate.

Use `writeAnsiText` when the input contains SGR escape sequences. The base
style supplies the background and any styles not overridden by the sequence:

```nim
let base = defaultStyle().withBackground(ansi256(236))
canvas.writeAnsiText(0, 0, "\e[1;36mConnected\e[0m", base, 20)
```

`lineText` returns one row as visible text, and `plainText` returns the full
canvas as newline-separated rows. These helpers are especially useful in
tests.

## Render Markdown

`renderMarkdown` returns a string that can be printed directly or written into
a canvas:

```nim
let output = renderMarkdown(
  "## Result\n\n**Done** in `nimterm`.",
  useColor = true)
canvas.writeAnsiText(0, 0, output, defaultStyle(), 20)
```

The renderer supports the Markdown commonly used in terminal responses:

- headings from `#` through `###`;
- fenced code blocks;
- inline code, bold, italic, and strikethrough;
- links, rendered with their label and URL;
- unordered and numbered lists;
- blockquotes and horizontal rules;
- tables with a Markdown separator row.

Pass `useColor = false` for plain output. Colors are only added when the active
theme has colors enabled. Set `maxWidth` to constrain table columns to a
terminal width. A table is recognized only after its separator row arrives,
which keeps partially streamed table text readable.

## Use the Markdown widget

`newMarkdown` wraps the renderer in a normal widget:

```nim
let help = newMarkdown("## Help\n\nUse **Enter** to continue.")
let screen = newPanel(help, title = "About")
```

If the text changes while a stream is active, update `help.text` and call
`app.invalidate()` before the next flush.

## Next steps

- [Styling and themes](/guides/styling-and-themes/) for semantic colors.
- [Widgets](/guides/widgets/) for panels, cards, and transcripts.
- [Testing](/guides/testing/) for canvas assertions with Unicode and ANSI text.
