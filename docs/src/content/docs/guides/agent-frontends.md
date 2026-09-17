---
title: Agent frontends
description: Turn streamed model or agent lifecycle events into a terminal transcript.
---

nimterm includes an agent-neutral event vocabulary. Adapt your model SDK,
subprocess, or remote service to `AgentUiEvent`, then feed those events to a
`TranscriptWidget`. No nimgent dependency is required.

## Create a transcript view

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

Call `view.apply(event.agent)` for every `uiAgent` event. It updates the
retained transcript and invalidates the widget when the visible content changes.

## Feed a streamed run

The reducer groups deltas by `runId` and `step`. A `ueRunStarted` event with a
`prompt` also appends a user item, so you do not need a separate user message
for the opening turn:

```nim
view.apply AgentUiEvent(
  kind: ueRunStarted,
  runId: "run-1",
  prompt: "Explain this change")
view.apply AgentUiEvent(kind: ueStepStarted, runId: "run-1", step: 0)
view.apply AgentUiEvent(
  kind: ueThinkingDelta,
  runId: "run-1",
  step: 0,
  text: "Checking the diff...")
view.apply AgentUiEvent(
  kind: ueTextDelta,
  runId: "run-1",
  step: 0,
  model: "assistant",
  text: "The change makes the parser safer.")
view.apply AgentUiEvent(
  kind: ueStepFinished,
  runId: "run-1",
  step: 0)
view.apply AgentUiEvent(kind: ueRunFinished, runId: "run-1")
```

Assistant text is rendered as Markdown. While a run is active, the assistant
item remains pending. `ueRunFinished` clears any pending items for that run.

Thinking text arrives through `ueThinkingDelta` and is shown in a compact
summary until the user presses Ctrl-O. While thinking is still pending and
collapsed, later thinking deltas update the item without rebuilding the whole
transcript layout.

## Show tools and approvals

Use tool events to show progress and results:

```nim
import std/json

view.apply AgentUiEvent(
  kind: ueToolCalled,
  runId: "run-1",
  step: 0,
  toolId: "call-1",
  toolName: "read",
  toolInput: %*{"path": "README.md"})
view.apply AgentUiEvent(
  kind: ueToolOutputDelta,
  runId: "run-1",
  toolId: "call-1",
  toolOutput: "1 | # nimterm")
view.apply AgentUiEvent(
  kind: ueToolResult,
  runId: "run-1",
  step: 0,
  toolId: "call-1",
  toolName: "read",
  toolOutput: "1 | # nimterm",
  durationMs: 12)
```

Set `isError = true` on `ueToolResult` when the tool failed. For an approval,
send `ueApprovalRequired` with `approvalChoices` and `cancelChoiceId`:

```nim
view.apply AgentUiEvent(
  kind: ueApprovalRequired,
  runId: "run-1",
  step: 0,
  toolId: "call-2",
  toolName: "write",
  approvalChoices: @[
    ApprovalChoice(id: "allow", key: "y", label: "Allow"),
    ApprovalChoice(id: "deny", key: "n", label: "Deny")],
  cancelChoiceId: "deny")
```

The widget displays the choices. A matching character, Enter for a choice with
key `enter`, or Escape for cancellation emits an `approval` action. The action
value is the choice ID and `targetId` identifies the tool item.

## Handle transcript actions

Connect the actions to your application controller:

```nim
import nimterm/term

app.onAction = proc (app: var App, action: UiAction) =
  case action.kind
  of "approval":
    echo "approval for " & action.targetId & ": " & action.value
  of "copy":
    copyToClipboard(action.value)
  else:
    discard
```

Drag with the mouse to select transcript text. `copy` is emitted when the
selection is released. `selectedText()` returns the selection without ANSI
sequences or transcript rails. `copySelection()` returns the same action
response for an application shortcut, such as a Ctrl-C binding.

## Add tool details

Set `toolDetails` when the tool output has useful structured summary lines:

```nim
import std/json

view.toolDetails = proc (name: string, input: JsonNode,
                         output: string): seq[string] =
  if name == "read":
    return @[input["path"].getStr, $output.splitLines.len & " lines"]
```

Completed tools show up to three detail lines until expanded. The widget uses
the tool output and your detail lines when rendering the compact view.

Set `formatToolLine` when you want to transform each line of tool output before
it is painted:

```nim
view.formatToolLine = proc (name, line: string): string =
  if name == "grep": return "  " & line
  line
```

## Add local messages

Use `appendUser` and `appendStatus` when your application needs to show text
outside the agent event stream:

```nim
view.appendUser("Show the status")
view.appendStatus("Connected to local model")
```

Status lines use a neutral dot prefix and do not participate in approvals or
tool expansion.

## Check for pending approvals

`awaitingApproval` returns `true` while any tool item still needs a choice. Use
it to pause background work or show a status indicator:

```nim
if view.awaitingApproval:
  app.invalidate()
```

## Scroll, expand, and search

The transcript follows the tail while new content arrives. Page Up, Page Down,
Home, End, Ctrl-B, Ctrl-F, and mouse wheel input control the viewport. Ctrl-O
toggles thinking and tool details between compact and expanded forms.

Bind your own search input to the search procedures:

```nim
let matches = view.setSearch("parser")
discard view.nextSearch()
discard view.nextSearch(backwards = true)
view.clearSearch()
```

`setSearch` returns the number of matching rendered lines and scrolls to the
first match. `nextSearch` moves to the next or previous match and returns
`false` when there are none. Call `scrollBy` to move the viewport by a number
of lines without changing the search state.

## Use the reducer without a widget

Use `Transcript` directly when you need to store or transform history before
rendering it:

```nim
var state = newTranscript()
state.appendUser("Show the status")
state.apply AgentUiEvent(kind: ueError, runId: "run-1", error: "Disconnected")
```

The retained item kinds are user, assistant, thinking, tool, error, and status.
Use `view.setTranscript(state)` to replace a view's state later. If you mutate
items in place, call `view.invalidateLines()` so the widget rebuilds its cached
layout.

## Event reference

| Event | Effect |
| --- | --- |
| `ueRunStarted` | Starts a run; appends a user item when `prompt` is set |
| `ueStepStarted` | Records the active step |
| `ueThinkingDelta` | Appends thinking text for the step |
| `ueTextDelta` | Appends assistant text for the step |
| `ueToolCalled` | Adds a pending tool item |
| `ueApprovalRequired` | Marks a tool item as awaiting approval |
| `ueToolOutputDelta` | Streams partial tool output |
| `ueToolResult` | Completes a tool item |
| `ueStepFinished` | Clears pending state for the step |
| `ueRunFinished` | Clears pending items for the run |
| `ueError` | Clears pending items and appends an error item |

## Next steps

- [Application loop](/guides/application-loop/) for event sources and wakeups.
- [Text and Markdown](/guides/text-and-markdown/) for assistant rendering.
- [Widgets](/guides/widgets/) for composing a transcript with an input or menu.
