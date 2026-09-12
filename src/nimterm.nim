## Terminal UI primitives for Nim applications.

import nimterm/[ansi, app, backend, canvas, events, geometry, input, keys,
  markdown, queue, style, text_width, theme, transcript, widget, widgets]

when not defined(windows):
  import nimterm/platform_posix
  export platform_posix
else:
  import nimterm/platform_windows
  export platform_windows

export ansi, app, backend, canvas, events, geometry, input, keys, markdown,
  queue, style, text_width, theme, transcript, widget, widgets
