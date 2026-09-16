---
title: Testing
description: Test nimterm rendering and event handling without a live terminal.
---

The canvas and backend contracts make terminal UI tests deterministic. Render a
widget into a canvas, inspect its visible text or cells, and send `UiEvent`
values directly to exercise interactions.

## Test a widget on a canvas

```nim
import std/unittest
import nimterm

test "card renders its title and body":
  let card = newCard("Status", "Ready")
  var canvas = newCanvas(size(20, 3))
  card.render(canvas, rect(0, 0, 20, 3))
  check "Status" in canvas.plainText
  check "Ready" in canvas.plainText
```

`plainText` removes styles from the assertion path. Use `getCell(x, y)` when
you need to assert a glyph, continuation cell, color, or text attribute.

## Test input and actions

Widget handlers accept `UiEvent` values, so an input test needs no backend:

```nim
test "input submits its text":
  let input = newInput()
  input.setText("hello")
  let response = input.handle(UiEvent(kind: uiKey, key: keyEnter))
  check response.action.kind == "submit"
  check response.action.value == "hello"
```

Use `keyChar` with `text` for text input, and named `Key` values for control
keys. Test mouse behavior with `x`, `y`, `mouse`, and `scrollDelta` fields.

## Use a fake backend

Subclass `TerminalBackend` to control the size, events, and presented frame:

```nim
type FakeBackend = ref object of TerminalBackend
  events: seq[UiEvent]
  presented: Canvas

method size(backend: FakeBackend): Size = size(40, 10)

method readEvent(backend: FakeBackend, timeoutMs: int): UiEvent =
  if backend.events.len == 0: return UiEvent(kind: uiNone)
  result = backend.events[0]
  backend.events.delete(0)

method present(backend: FakeBackend, frame: Canvas) =
  backend.presented = frame.copy()
```

Use it with `newApp` and `step`:

```nim
let backend = FakeBackend(events: @[quitEvent()])
var app = newApp(backend, newText("ready"))
check app.step()
check not app.running
```

`newApp` does not initialize a backend. Constructing a platform backend is safe
in a test; raw terminal mode begins only when `init` or `run` is called.

## Test the application controller

Capture actions instead of printing them:

```nim
let input = newInput()
input.id = "composer"
var app = newApp(FakeBackend(), input)
var received: UiAction
app.onAction = proc (app: var App, action: UiAction) = received = action
app.render()
app.focus(input)
app.dispatch(UiEvent(kind: uiKey, key: keyEnter))
check received.sourceId == "composer"
```

Fake sources and timers enter the same queue as backend events, which lets you
test ordering and failure handling without sleeps or a real clock-driven UI.

## Run nimterm's tests

From the package root:

```sh
nim c -r --hints:off --path:src tests/all_tests.nim
```

The suite covers input decoding, Unicode widths, Markdown, themes, scrolling,
canvas damage, app dispatch, menus, questions, inputs, and transcripts.

## Next steps

- [Text and Markdown](/guides/text-and-markdown/) for canvas assertions.
- [Input and events](/guides/input-and-events/) for event-driven tests.
- [API reference](/reference/core-api/) for the backend and canvas contracts.
