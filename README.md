# nimterm

Terminal UI primitives for Nim applications and agent frontends. Compose a widget
tree, run it in the terminal, and ship it as a native binary.

nimterm is built for apps that stream model output, show tool calls, collect
approvals, and ask for the occasional decision. It does not call models or
depend on nimgent. Adapt any AI SDK, subprocess, or remote service to the
event vocabulary and render it.

## Install

You need Nim 2.0 or later:

```sh
nimble install nimterm
```

## Hello, terminal

Create `hello.nim`:

```nim
import nimterm

let screen = newPanel(
  newText("Hello from nimterm"),
  title = "Welcome")
var app = newApp(newPlatformBackend(fullscreen = false), screen)
app.run()
```

Compile and run from an interactive terminal:

```sh
nim c -r hello.nim
```

Use `fullscreen = false` to keep completed output in shell scrollback. Omit it
or set it to `true` for the alternate screen.

## Collect input

Stack widgets in a column and handle the action a widget emits:

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

## Pick from a menu

Menus emit a `select` action when the user presses Enter:

```nim
import nimterm

let menu = newMenu(@[
  MenuItem(label: "Continue", description: "Keep working"),
  MenuItem(label: "Quit", description: "Close the app")])

var app = newApp(newPlatformBackend(), menu)
app.onAction = proc (app: var App, action: UiAction) =
  if action.kind == "select" and action.index == 1:
    app.running = false
app.run()
```

## Stream an agent transcript

Feed lifecycle events into a retained transcript widget. No provider SDK
required:

```nim
import nimterm

let transcript = newTranscript()
let view = newTranscriptWidget(transcript)
var app = newApp(newPlatformBackend(fullscreen = false), view)

app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiAgent:
    view.apply(event.agent)
    app.invalidate()
    return eventHandled
  eventIgnored

app.run()
```

The transcript renders thinking, assistant text, tool calls, approvals, and
diffs as they arrive. [nimlet](https://github.com/martineastwood/nimlet) uses
this path for its interactive terminal app.

## What you get

- **Widgets for agent UIs:** transcripts, panels, cards, input, menus,
  questions, Markdown, and diffs.
- **A small application loop:** `newApp`, normalized `UiEvent` values, and
  `UiAction` results from widgets.
- **Testable rendering:** measure, lay out, and paint onto a canvas you can
  assert on without a live terminal.
- **Themes and text layout:** semantic styles, ANSI-aware width, wrapping, and
  built-in dark and light palettes.
- **POSIX and Windows backends:** `newPlatformBackend` selects the native
  terminal bridge at compile time.

## Documentation

Full documentation lives at **[nimterm.niminal.dev](https://nimterm.niminal.dev)**.

- [Introduction](https://nimterm.niminal.dev/introduction/)
- [Quickstart](https://nimterm.niminal.dev/guides/quickstart/)
- [Widgets](https://nimterm.niminal.dev/guides/widgets/)
- [Agent frontends](https://nimterm.niminal.dev/guides/agent-frontends/)
- [Input and events](https://nimterm.niminal.dev/guides/input-and-events/)
- [Styling and themes](https://nimterm.niminal.dev/guides/styling-and-themes/)
- [Testing](https://nimterm.niminal.dev/guides/testing/)
- [Core API](https://nimterm.niminal.dev/reference/core-api/)

## License

MIT. See [LICENSE](LICENSE).
