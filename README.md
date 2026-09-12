# nimterm

Generic terminal UI primitives for Nim applications and agent frontends.

The library currently provides:

- semantic terminal geometry, styles, cells, and a testable canvas;
- a backend contract and deterministic widget application loop;
- generic UI events plus an agent lifecycle event vocabulary;
- a retained transcript reducer for streamed turns;
- `Text`, `Panel`, `Input`, `Menu`, and multiple-choice `Question` widgets;
- ANSI-aware text layout, terminal input/control, themes, and Markdown.

nimterm does not depend on nimgent. Applications can adapt any agent or event
source to `AgentUiEvent`; nimlet's adapter is the first example.

The backend is platform-neutral at the widget and event layer. POSIX uses
termios and a signal wake pipe; native Windows uses Win32 console modes when
available and an ANSI byte-stream fallback for Git Bash/MSYS terminals.
Applications should construct `newPlatformBackend`; it selects the native
backend at compile time.

Use `newPlatformBackend(fullscreen = false)` to render in the normal terminal
screen and preserve the completed interface in shell scrollback. The
POSIX-specific `newPosixBackend` remains available for callers that need it.
