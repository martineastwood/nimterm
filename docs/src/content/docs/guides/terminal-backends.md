---
title: Terminal backends
description: Select a platform backend, screen mode, and terminal capabilities.
---

Most applications should create their backend with `newPlatformBackend`. It
selects the POSIX or Windows implementation at compile time and gives `App` a
common interface for terminal size, input, wakeups, and frame presentation.

## Start a platform backend

```nim
import nimterm

let backend = newPlatformBackend(fullscreen = false)
var app = newApp(backend, newText("Ready"))
app.run()
```

The default is `fullscreen = true`. In that mode nimterm uses the terminal's
alternate screen when supported. Use `fullscreen = false` when you want to
preserve the normal screen and shell scrollback.

## Choose capabilities

`TerminalCapabilities` controls which optional terminal protocols nimterm
requests:

```nim
let capabilities = TerminalCapabilities(
  mouse: true,
  bracketedPaste: true,
  focusEvents: false,
  modifyOtherKeys: true,
  kittyKeyboard: false)

let backend = newPlatformBackend(
  capabilities = capabilities,
  fullscreen = false)
```

`defaultCapabilities()` enables mouse, bracketed paste, focus events, and
modified-key support. Set `kittyKeyboard` to `true` when your terminal supports
the Kitty keyboard protocol. When both keyboard flags are enabled, the Kitty
protocol is preferred.

Disabling a capability makes nimterm omit that protocol's enable and disable
sequences. This is useful for a restricted terminal, a multiplexer with
limited support, or a test backend.

## Use the backend lifecycle directly

`App.run` calls `backend.init()` and `backend.shutdown()` for you. A host-owned
loop can call them explicitly:

```nim
import nimterm
import nimterm/term

let backend = newPlatformBackend()
backend.init()
defer: backend.shutdown()

echo backend.size.w, " x ", backend.size.h
```

Initialization puts the terminal into its input mode, hides the cursor, and
enables the selected protocols. Shutdown restores the terminal state and shows
the cursor. Always pair a successful `init` with `shutdown`, including when a
custom loop raises an exception.

For temporary shell interaction, `suspendTerminal()` shuts down the active
terminal state and `resumeTerminal()` initializes it again.

## Use platform-specific constructors

The top-level `nimterm` import exports the platform module for the target OS.
You can also import it explicitly when you need the concrete constructor:

```nim
when defined(windows):
  import nimterm/platform_windows
  let backend = newWindowsBackend(fullscreen = false)
else:
  import nimterm/platform_posix
  let backend = newPosixBackend(fullscreen = false)
```

POSIX uses termios input and a signal wake path. Native Windows console hosts
use Win32 console modes, while byte-stream hosts such as Git Bash/MSYS use the
ANSI input path. The widget and event APIs are the same on both platforms.

## Check whether a terminal is available

Before starting an interactive app, use `terminalIsInteractive()`:

```nim
import nimterm/term

if not terminalIsInteractive():
  quit("nimterm needs an interactive terminal")
```

You can check input and output separately with
`terminalInputIsInteractive()` and `terminalOutputIsInteractive()`.

## Troubleshooting

- If the terminal is left in raw mode after a crash, run `stty sane` on POSIX
  terminals, then start the program again.
- If colors are missing, check `NO_COLOR`, `TERM`, and `COLORTERM`. The theme
  system deliberately disables colors for non-interactive output.
- If input is missing in a multiplexer or remote terminal, reduce the enabled
  capabilities and verify that the host supports the requested protocols.
- Do not start `termInit` twice. It raises `TermError` while a terminal session
  is already active.

## Next steps

- [Application loop](/guides/application-loop/) to integrate the backend with your loop.
- [Styling and themes](/guides/styling-and-themes/) for color-depth behavior.
- [Testing](/guides/testing/) for fake backends that never touch the terminal.
