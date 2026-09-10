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
source to `AgentUiEvent`; niminal's adapter is the first example.

The POSIX backend is available now; a Windows backend will follow while
keeping the widget and event APIs platform-neutral.
