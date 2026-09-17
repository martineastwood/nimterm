---
title: Text and Markdown
description: Render styled text, Unicode, ANSI sequences, and Markdown in terminal cells.
---

Terminal columns are not the same as string length. nimterm includes helpers
that account for ANSI escape sequences, wide Unicode characters, combining
marks, and semantic cell styles.

## Measure and wrap text

Use `displayWidth` for plain text, `cellWidth` for a single rune, and
`ansiVisibleWidth` for text that may contain ANSI escapes:

```nim
import nimterm
from std/unicode import Rune

assert displayWidth("界") == 2
assert Rune(0x754C).cellWidth == 2
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

## Build styled lines

`StyledLine` groups text spans with semantic styles. Use it when you need to
measure, wrap, or paint multi-style output without going through a widget:

```nim
import nimterm
import nimterm/styled_text

var line: StyledLine
line.add("Status: ", defaultStyle())
line.add("ready", currentTheme.success)

assert line.width == 13
var canvas = newCanvas(size(20, 1))
canvas.write(line, 0, 0, 20)
for wrapped in line.wrap(12):
  echo wrapped.ansi()
```

`add` merges adjacent spans that share the same style. `ansi` turns a line into
terminal output, and `write` paints it into a canvas with optional width
clipping.

## Render Markdown

`renderMarkdown` returns a string that can be printed directly or written into
a canvas. `renderMarkdownLines` returns the same content as `seq[StyledLine]`
when you want to wrap or paint each line yourself:

```nim
let output = renderMarkdown(
  "## Result\n\n**Done** in `nimterm`.",
  useColor = true)
canvas.writeAnsiText(0, 0, output, defaultStyle(), 20)

var row = 0
for line in renderMarkdownLines("## Result\n\n**Done**"):
  for wrapped in line.wrap(40):
    canvas.write(wrapped, 0, row, 40)
    inc row
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
