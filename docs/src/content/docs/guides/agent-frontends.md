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

Call `view.apply(event)` for every lifecycle event. It updates the retained
transcript and invalidates the widget when the visible content changes.

## Feed a streamed run

The reducer groups deltas by `runId` and `step`:

```nim
view.apply AgentUiEvent(
  kind: ueRunStarted,
  runId: "run-1",
  prompt: "Explain this change")
view.apply AgentUiEvent(kind: ueStepStarted, runId: "run-1", step: 0)
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

`copy` is emitted after a mouse selection is released over transcript text.
`selectedText()` returns the selection without ANSI sequences or transcript
rails. `copySelection()` returns the same action response for an application
shortcut.

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

## Scroll, expand, and search

The transcript follows the tail while new content arrives. Page Up, Page Down,
Home, End, Ctrl-B, Ctrl-F, and mouse wheel input control the viewport. Ctrl-O
toggles thinking and tool details between compact and expanded forms.

Bind your own search input to the search procedures:

```nim
let matches = view.setSearch("parser")
discard view.nextSearch()
view.clearSearch()
```

`setSearch` returns the number of matching rendered lines. `nextSearch` moves
to the next match and returns `false` when there are none.

## Use the reducer without a widget

Use `Transcript` directly when you need to store or transform history before
rendering it:

```nim
var state = newTranscript()
state.appendUser("Show the status")
state.apply AgentUiEvent(kind: ueError, runId: "run-1", error: "Disconnected")
```

The retained item kinds are user, assistant, thinking, tool, error, and status.
Use `view.setTranscript(state)` to replace a view's state later.

## Next steps

- [Application loop](/guides/application-loop/) for event sources and wakeups.
- [Text and Markdown](/guides/text-and-markdown/) for assistant rendering.
- [Widgets](/guides/widgets/) for composing a transcript with an input or menu.
