---
title: Application loop
description: Run a nimterm application, add timers, and connect event sources.
---

`App` owns the work that repeats while your interface is active: collecting
events, dispatching them to the application and widget tree, rendering when the
UI is dirty, and presenting the resulting canvas through the backend.

## Let `App` own the loop

For a standalone terminal program, `run` is the normal entry point:

```nim
import nimterm

var app = newApp(newPlatformBackend(), newText("Ready"))
app.run()
```

`run` requires a backend. It initializes the backend before the first frame and
shuts it down, along with registered event sources, when the loop ends.

## Add timers

Use `schedule` for one-shot or repeating `uiTimer` events. Timer identifiers are
application-defined strings:

```nim
var app = newApp(newPlatformBackend(), newText("Waiting..."))
app.schedule("refresh", delayMs = 1000, intervalMs = 1000)
app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiTimer and event.timerId == "refresh":
    app.invalidate()
  eventIgnored
app.run()
```

Call `cancelTimer("refresh")` to remove every timer with that identifier.
Timers are placed in the same queue as terminal and source events, so your
application sees them through one dispatch path.

## Post an event

Application code can enqueue an event and wake a blocked backend with `post`:

```nim
app.post agentEvent(AgentUiEvent(
  kind: ueTextDelta,
  runId: "run-1",
  step: 0,
  text: "Hello"))
```

`agentEvent` wraps an `AgentUiEvent` as a `uiAgent` event. Use other supported
`UiEventKind` values such as `uiTimer`, `uiError`, or `uiQuit` for application
events that fit those shapes.

## Integrate a host-owned loop

Use `init`, `step`, `flush`, and `shutdown` when another event loop owns the
process:

```nim
var app = newApp(newPlatformBackend(), newText("Ready"))
app.backend.init()
defer: app.backend.shutdown()

app.running = true
app.render()
while app.running:
  discard app.step(timeoutMs = 100)
  app.flush()
```

`step` processes at most one queued, source, or backend event. It returns
`false` when no event was available. `flush` presents only when the app is
dirty, unless you pass `force = true`.

Keyboard events flush immediately. For streamed or background updates, set
`minFrameIntervalMs` to limit presentation frequency, then call `flush` from
your host loop when the app has no event.

## Add an event source

Subclass `EventSource` when your application already has a pollable producer:

```nim
type MessageSource = ref object of EventSource
  messages: seq[string]

method poll(source: MessageSource): seq[UiEvent] =
  for message in source.messages:
    result.add agentEvent(AgentUiEvent(kind: ueTextDelta, text: message))
  source.messages.setLen(0)

let source = MessageSource(id: "messages", messages: @["one", "two"])
app.addSource(source)
```

`poll` can return zero or more events. `needsPolling` defaults to `true`, which
makes an idle app poll at `pollIntervalMs`, defaulting to 16 milliseconds. A
source can override it to return `false` while idle. If `poll` raises a
`CatchableError`, the app posts a `uiError`, closes the source, and removes it.

## Handle failures

An exception from `onEvent` or a widget handler becomes a `uiError` event on a
later step. Handle it in `onEvent` if you want to show a message or stop the
application:

```nim
app.onEvent = proc (app: var App, event: UiEvent): EventResponse =
  if event.kind == uiError:
    stderr.writeLine event.sourceId & ": " & event.error
    app.running = false
    return eventHandled
  eventIgnored
```

## Next steps

- [Input and events](/guides/input-and-events/) for dispatch and focus rules.
- [Terminal backends](/guides/terminal-backends/) for capabilities and screen modes.
- [Agent frontends](/guides/agent-frontends/) for feeding streamed events into a widget.
