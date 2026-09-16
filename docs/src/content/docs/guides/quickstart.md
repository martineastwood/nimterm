---
title: Quickstart
description: Build and run your first interactive terminal app with nimterm.
---

This guide takes you from an empty Nim file to an interactive terminal app. By
the end, you will have a panel, a text input, and a submit action handled by
your application.

## 1. Install nimterm

You need Nim 2.0 or later. Install nimterm with Nimble:

```sh
nimble install nimterm
```

To work from a checkout instead, run the commands below from the `nimterm`
directory:

```sh
nimble install
```

You can also compile directly from the checkout with `nim c -r --path:src
hello.nim`.

## 2. Create the app

Create `hello.nim`:

```nim
import nimterm

let input = newInput(prefix = "Say: ")
let screen = newColumn(@[
  Widget(newCard("nimterm", "Type a message, then press Enter.")),
  Widget(input)])

var app = newApp(newPlatformBackend(fullscreen = false), screen)
app.onAction = proc (app: var App, action: UiAction) =
  if action.kind == "submit":
    app.running = false
    echo "You entered: " & action.value

app.run()
```

`Column` divides its area between its children. The `InputWidget` is
focusable, so clicking it or moving focus to it lets it receive keyboard
events. Pressing Enter returns an action with `kind == "submit"` and the
submitted value in `action.value`.

## 3. Compile and run

Run the program from an interactive terminal:

```sh
nim c -r hello.nim
```

The example uses `fullscreen = false`, so the application keeps the normal
terminal screen and completed output remains in shell scrollback. Omit the
argument, or set it to `true`, when you want the alternate screen.

## What just happened

- `newPlatformBackend` selected the native backend for the target platform.
- `newApp` created the event queue and retained the widget root.
- `newColumn` arranged the card and input vertically.
- `onAction` received the input widget's `submit` action.
- `run` initialized the backend, rendered frames, processed events, and shut
  the backend down when `app.running` became `false`.

## Add a choice

Menus emit a `select` action when the user presses Enter:

```nim
let menu = newMenu(@[
  MenuItem(label: "Continue", description: "Keep working"),
  MenuItem(label: "Quit", description: "Close the app")])

var app = newApp(newPlatformBackend(), menu)
app.onAction = proc (app: var App, action: UiAction) =
  if action.kind == "select" and action.index == 1:
    app.running = false
app.run()
```

Use `action.value` for the selected label and `action.index` for its zero-based
position. See [Widgets](/guides/widgets/) for panels, questions, Markdown, and
custom composition.

## Next steps

- [Application loop](/guides/application-loop/) to own the loop yourself or add timers.
- [Input and events](/guides/input-and-events/) to handle focus, mouse input, and actions.
- [Styling and themes](/guides/styling-and-themes/) to give the interface a palette.
- [Testing](/guides/testing/) to test rendering without entering raw terminal mode.
