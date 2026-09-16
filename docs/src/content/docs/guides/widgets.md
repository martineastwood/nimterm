---
title: Widgets
description: Compose terminal interfaces from retained widgets and semantic layout.
---

Widgets are retained objects that know how to lay out, paint, and handle events.
Build a UI tree by passing widgets to a container, then give the root to
`newApp`:

```nim
import nimterm

let input = newInput(prefix = "Prompt: ")
let root = newColumn(@[
  Widget(newPanel(newMarkdown("## Notes\n\nUse **Enter** to submit."), "Help")),
  Widget(input)])

var app = newApp(newPlatformBackend(fullscreen = false), root)
app.run()
```

Widgets are `ref` objects. When a constructor returns a concrete widget, use
`Widget(widget)` when putting it into a `seq[Widget]`.

## Choose a built-in widget

| Widget | Use it for | Constructor |
| --- | --- | --- |
| `TextWidget` | One line of styled text | `newText` |
| `Markdown` | The supported Markdown subset | `newMarkdown` |
| `Panel` | A bordered child area with an optional title | `newPanel` |
| `Card` | A bordered title and wrapped body | `newCard` |
| `Column` | Equal vertical composition | `newColumn` |
| `Stack` | Layering children in the same area | `newStack` |
| `InputWidget` | UTF-8-safe editable text | `newInput` |
| `Menu` | Selectable labels and descriptions | `newMenu` |
| `QuestionWidget` | A modal choice with optional free text | `newQuestion` |
| `DiffCard` | A file diff with line kinds | `newDiffCard` |
| `TranscriptWidget` | Streamed agent or model turns | `newTranscriptWidget` |

`ScrollView` is a state object rather than a widget. Use it when a custom
widget needs a vertical viewport, or use the built-in scrolling behavior in a
transcript.

## Compose areas

`Column` gives each child a share of the available height. `Stack` renders all
children into the same rectangle in order, so later children can draw over
earlier ones. Use a stack for overlays and a column for the usual header,
content, and footer arrangement.

`Panel` reserves one cell on each side for its border and gives the remaining
area to its child. `Card` draws a top border and wraps its body within the
available width. Both accept independent content and border styles.

## Handle widget actions

Interactive widgets return `EventResponse` values. `App` sends actions to
`onAction`:

```nim
let input = newInput()
input.id = "composer"
var app = newApp(newPlatformBackend(), input)

app.onAction = proc (app: var App, action: UiAction) =
  case action.kind
  of "submit":
    echo action.value
    input.clear()
  of "select":
    echo "selected " & $action.index & ": " & action.value
  of "answer":
    if action.cancelled: echo "cancelled"
    else: echo action.value
  else:
    discard

app.run()
```

The common fields are `sourceId`, `kind`, `value`, `index`, and `cancelled`.
`QuestionWidget` uses `index == -1` for a free-text answer. A menu selection
uses a zero-based index.

## Use layout constraints

`Size`, `Rect`, and `Constraints` describe terminal-cell geometry. A widget's
`measure` method can calculate its preferred size within min and max bounds;
`layout` assigns its final rectangle; and `paint` writes cells to the canvas.
Built-in containers call `render` on their children with the area they assign.

When you build a custom layout, use the helpers rather than constructing
negative dimensions:

```nim
let available = Constraints(
  minSize: size(20, 1),
  maxSize: size(80, 10))
let wanted = size(100, 4)
let actual = available.clamp(wanted)
let area = rect(0, 0, actual.w, actual.h)
```

`size` and `rect` clamp widths and heights to zero or greater. `unconstrained()`
uses zero minimums and `int.high` maximums.

## Create a custom widget

Subclass `Widget` and override only the behavior you need. This small widget
paints a label and remains compatible with the normal rendering path:

```nim
type Label = ref object of Widget
  text: string

method paint(widget: Label, canvas: var Canvas) =
  canvas.writeText(widget.area.x, widget.area.y, widget.text,
    defaultStyle(), widget.area.w)

let label = Label(text: "Status: ready")
```

Override `children` for composition, `focusable` for keyboard focus,
`measure` for preferred sizing, `handle` for events, and `paint` for cells.
Return `eventIgnored` when an event does not belong to the widget.

## Next steps

- [Input and events](/guides/input-and-events/) for focus, mouse capture, and modal questions.
- [Styling and themes](/guides/styling-and-themes/) for reusable styles.
- [Text and Markdown](/guides/text-and-markdown/) for width-aware output.
- [API reference](/reference/core-api/) for every widget field and procedure.
