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

The built-in set is shaped by agent frontends: show a streamed conversation,
expose tool calls and diffs, and collect a decision. That is why there is a
transcript and a diff card, and why there is no table, tree, or form widget. For
an interface outside that shape, build a [custom widget](#create-a-custom-widget)
or compose the containers below.

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
widget needs a vertical viewport, or rely on the built-in scrolling behavior in
a transcript.

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

The common fields are `sourceId`, `targetId`, `kind`, `value`, `index`, and
`cancelled`. `sourceId` identifies the widget that emitted the action.
`targetId` identifies a related item, such as a tool call in an approval
action. `QuestionWidget` uses `index == -1` for a free-text answer. A menu
selection uses a zero-based index.

## Show a diff

`DiffCard` renders a `DiffDocument` with added, removed, context, and header
lines:

```nim
let diff = newDiffCard(DiffDocument(
  path: "src/parser.nim",
  lines: @[
    DiffLine(kind: dlHeader, text: "@@ -1,3 +1,4 @@"),
    DiffLine(kind: dlRemoved, text: "old line"),
    DiffLine(kind: dlAdded, text: "new line")],
  additions: 1,
  removals: 1))
```

Pass independent styles for each line kind through `newDiffCard`. The card
measures itself from the document path and line text.

## Configure menus and inputs

`newMenu` accepts a title, border, and per-state styles. Menus scroll when
there are more items than visible rows, support Page Up and Page Down, and
respond to mouse clicks on a row:

```nim
let menu = newMenu(@[
  MenuItem(label: "Continue", description: "Keep working"),
  MenuItem(label: "Quit", description: "Close the app")],
  title = "Session",
  bordered = true)
```

`newInput` supports a continuation prefix for wrapped multiline text, padding,
and separate prefix and cursor styles. It emits a `change` action after each
edit and `submit` on Enter:

```nim
let input = newInput(
  prefix = "> ",
  continuationPrefix = "  ",
  paddingLeft = 1)
```

Up and Down move between wrapped visual lines when the text spans multiple
rows.

## Scroll with `ScrollView`

Use `ScrollView` in custom widgets that paint more lines than fit in the
viewport:

```nim
var view = newScrollView(followTail = true)
view.update(contentHeight = 120, viewportHeight = 20)
view.pageBy(1)
view.home()
view.tail()
let visible = view.visibleRange()
```

`followTail` keeps the viewport pinned to the end while new content arrives.
`scrollBy` and `pageBy` clear tail-following when the user scrolls away from
the bottom.

## Control visibility and modality

Override `visible`, `enabled`, `focusable`, and `modal` on custom widgets to
change how events reach them. A modal widget blocks background keyboard input
until it is resolved. Override `allowsBackgroundEvent` when a modal widget should
still receive scroll or page keys, as `QuestionWidget` does for background
scrolling.

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
