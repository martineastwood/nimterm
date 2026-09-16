---
title: Core API
description: The small set of nimterm entry points used by most applications.
---

Most applications can start with the top-level import:

```nim
import nimterm
```

This exports the platform-neutral API and the platform backend for the target
operating system. Focused imports are available when you want a smaller module
boundary, for example `nimterm/app`, `nimterm/canvas`, `nimterm/events`, or
`nimterm/widgets`.

## Application

```nim
let backend = newPlatformBackend(fullscreen = false)
var app = newApp(backend, newText("Ready"))
app.run()
```

Use `step`, `render`, `flush`, `post`, `schedule`, `addSource`, and `focus` when
your application needs more control. See [Application loop](/guides/application-loop/).

## Geometry and rendering

| Module | Main entry points |
| --- | --- |
| `geometry` | `size`, `rect`, `unconstrained`, `clamp`, `contains` |
| `canvas` | `newCanvas`, `writeText`, `writeAnsiText`, `getCell`, `plainText` |
| `style` | `defaultStyle`, `ansi16`, `ansi256`, `rgb`, `withForeground`, `withBackground` |
| `text_width` | `cellWidth`, `displayWidth` |
| `ansi` | `stripAnsi`, `ansiVisibleWidth`, `wrapAnsi` |

## Widgets

Import `nimterm/widgets` for the built-in constructors:

```nim
let root = newColumn(@[
  Widget(newPanel(newText("Header"), "App")),
  Widget(newInput())])
```

The main constructors are `newText`, `newMarkdown`, `newPanel`, `newCard`,
`newColumn`, `newStack`, `newInput`, `newMenu`, `newQuestion`, `newDiffCard`,
and `newTranscriptWidget`. See [Widgets](/guides/widgets/) for how they fit
together.

## Events and actions

`UiEvent` covers key, mouse, focus, resize, timer, agent, quit, and error
events. `UiAction` carries a result from an interactive widget to your
application. Use `agentEvent` and `quitEvent` for the common wrapper events.

## Themes and terminal control

Use `detectDepth`, `applyTheme`, `listThemeNames`, and `currentTheme` for
palette selection. Use `termInit`, `termShutdown`, `terminalIsInteractive`,
`termWidth`, and `termHeight` when integrating terminal control directly.
Import `nimterm/term` for those terminal-control procedures. Most applications
should let `App` manage the terminal lifecycle.

## Agent transcripts

`Transcript` reduces `AgentUiEvent` values into retained items. `TranscriptWidget`
adds Markdown rendering, scrolling, compact tool and thinking views, selection,
copy actions, and search. See [Agent frontends](/guides/agent-frontends/).

## Generated API reference

The [generated API reference](/reference/api/nimterm/) includes every exported
module, type, procedure, method, argument, and source link. It is regenerated
from the Nim source when the documentation site is built.
