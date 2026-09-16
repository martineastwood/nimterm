---
title: Input and events
description: Handle keyboard, mouse, focus, timers, and application actions.
---

nimterm turns terminal input into a small `UiEvent` vocabulary. Your app can
handle those events globally, let the focused widget handle them, or post its
own events from another source.

## Handle an event globally

`onEvent` runs before the widget tree. Return `eventHandled` to stop routing the
event, or `eventIgnored` to let the normal widget dispatch continue:

```nim
import std/strutils
import nimterm

var app = newApp(newPlatformBackend(), newText("Press Q to quit"))
app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiKey and event.key == keyChar and
      event.text.toLowerAscii == "q":
    app.running = false
    return eventHandled
  eventIgnored
app.run()
```

`UiEvent` also represents `uiMouse`, `uiFocus`, `uiResize`, `uiTimer`,
`uiAgent`, `uiError`, and `uiQuit`. Keyboard text is in `event.text`; use
`event.key` for named keys.

## Focus and keyboard routing

Call `app.focus(widget)` to focus a widget that is visible, enabled, focusable,
and part of the root tree:

```nim
let input = newInput()
var app = newApp(newPlatformBackend(), input)
app.render()
app.focus(input)
```

When a keyboard event arrives, nimterm sends it from the focused widget toward
its parents until one returns a handled response. If no widget handles Tab or
Shift+Tab, focus moves through the visible, enabled, focusable widgets in tree
order.

Mouse events use the widget under the pointer. A widget can return
`captureHandled()` on press to receive later drag and release events even when
the pointer leaves its area. `releaseHandled()` releases the capture.

## Input widget editing

`InputWidget` keeps its cursor on UTF-8 boundaries and understands multiline
text. It emits a `change` action after an edit and a `submit` action on Enter:

```nim
let input = newInput(prefix = "> ")
input.setText("hello")
input.insert(" world")

let response = input.handle(UiEvent(kind: uiKey, key: keyEnter))
assert response.action.kind == "submit"
assert response.action.value == "hello world"
```

Useful editing keys include:

| Key | Effect |
| --- | --- |
| Left, Right, Ctrl-B, Ctrl-F | Move by one character |
| Alt-B, Alt-F | Move by one word |
| Backspace, Delete, Ctrl-D | Delete before or after the cursor |
| Ctrl-W, Alt-D | Delete the previous or next word |
| Home, End, Ctrl-A, Ctrl-E | Move to the text boundary |
| Ctrl-U, Ctrl-K | Delete to the start or end of the current line |
| Ctrl-Y, Ctrl-Z | Yank the last deletion or undo |
| Shift+Enter, Alt+J | Insert a newline |
| Enter | Emit `submit` |

`setText` replaces the text and moves the cursor to the end. `clear` removes
the text and resets the edit history.

## Work with actions

An `EventResponse` can request focus, capture or release the mouse, and return
a `UiAction`. Use the helpers in custom widgets:

```nim
return widget.actionHandled("refresh", value = "now")
```

`focusActionHandled` combines a focus request with an action. The application
receives the action through `onAction`; the widget's `sourceId` is available in
`action.sourceId`.

## Questions are modal

`QuestionWidget` is focusable and modal until it is answered or cancelled. Up
and Down move through its options, Enter answers, and Escape emits a cancelled
`answer` action. When `allowFreeText` is enabled, the last option opens the
embedded input and an empty free-text answer is not accepted.

Page Up, Page Down, and mouse wheel events can still reach the background while
a question is open. Other background input is blocked until the question is
resolved.

## Decode input yourself

The platform backends already use `InputDecoder`. Use it directly when you are
building a custom input source or testing terminal bytes:

```nim
var decoder: InputDecoder
decoder.feed("hello")
let event = decoder.nextEvent(0)
assert event.key == keyChar
assert event.text == "h"
```

It understands UTF-8 text, escape sequences, function keys, bracketed paste,
focus reports, SGR mouse input, and modified keys. `normalizePasteText` turns
CRLF and CR into LF so a paste does not submit an input accidentally.

## Next steps

- [Application loop](/guides/application-loop/) for timers, sources, and host-owned loops.
- [Widgets](/guides/widgets/) for menus, questions, and custom handlers.
- [Terminal backends](/guides/terminal-backends/) for capability selection.
