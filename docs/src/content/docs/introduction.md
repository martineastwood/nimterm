---
title: Introduction
description: Build native terminal and console apps for agents in Nim with widgets, events, and a testable canvas.
---

nimterm gives you the terminal UI layer for apps that run an agent. You can
render a streamed conversation, show tool calls and their results, ask for
approval, collect a prompt, and keep everything in one interactive terminal
session.

The widgets follow from that focus: transcript, card, diff, input, menu, and
question. nimterm is a terminal UI library rather than a general-purpose widget
toolkit, so there are no tables, trees, tabs, or form builders to learn. If your
app displays agent output and collects the occasional decision, that set covers
the whole path from events to terminal cells.

nimterm is the UI layer only. It does not call models, run tools, or store
sessions. It does not depend on nimgent either, so adapt any AI SDK, subprocess,
or remote service to the event vocabulary and render it. nimlet, the Niminal
coding agent, uses that path for its interactive terminal app.

## Your first app

The quickest way to start is to create a backend, put a widget at the root of
an `App`, and run it:

```nim
import nimterm

let screen = newPanel(
  newText("Hello from nimterm"),
  title = "Welcome")
var app = newApp(newPlatformBackend(fullscreen = false), screen)
app.run()
```

Run this from an interactive terminal. The [Quickstart](/guides/quickstart/)
adds input and shows how to handle the action emitted when the user submits it.

## The small set of concepts

| Concept | What you use it for |
| --- | --- |
| `Canvas` | A testable grid of terminal cells with glyphs and semantic styles. |
| `Widget` | A retained piece of UI that can measure, lay out, paint, and handle events. |
| `App` | The application shell that polls events, routes them, and presents frames. |
| `TerminalBackend` | The platform-specific bridge for terminal size, input, and output. |
| `UiEvent` | A normalized keyboard, mouse, timer, resize, agent, or error event. |
| `UiAction` | A widget's user-facing result, such as `submit`, `select`, or `answer`. |

Most applications only need `newPlatformBackend`, `newApp`, one or more
widgets, and an `onAction` callback. Use the lower-level modules when you need
custom widgets, a host-owned loop, or deterministic rendering tests.

## What is included

- Layout primitives: `Size`, `Rect`, `Constraints`, `Column`, and `Stack`.
- Built-in widgets: text, Markdown, panels, cards, menus, questions, inputs,
  diffs, and transcripts.
- ANSI-aware text width, wrapping, slicing, and Markdown rendering.
- Semantic styles with ANSI 16, ANSI 256, and truecolor values.
- Built-in dark and light themes plus JSON theme files.
- POSIX and Windows platform backends with selectable terminal capabilities.
- An agent-neutral lifecycle vocabulary and retained transcript reducer.

## Next steps

- [Quickstart](/guides/quickstart/) to build an interactive app.
- [Agent frontends](/guides/agent-frontends/) to display streamed model or agent events.
- [Widgets](/guides/widgets/) to compose and style a UI tree.
- [Application loop](/guides/application-loop/) to integrate timers and event sources.
- [Core API](/reference/core-api/) for the entry points used most often.
