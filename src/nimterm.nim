## Terminal UI primitives for Nim applications.

import nimterm/[ansi, app, backend, canvas, events, geometry, input, keys,
  markdown, style, theme, transcript, widget, widgets]

when not defined(windows):
  import nimterm/platform_posix
  export platform_posix

export ansi, app, backend, canvas, events, geometry, input, keys, markdown,
  style, theme, transcript, widget, widgets
