## Platform-neutral terminal backend contract.

import ./canvas
import ./events
import ./geometry

type
  TerminalBackend* = ref object of RootObj

method init*(backend: TerminalBackend) {.base.} =
  discard

method shutdown*(backend: TerminalBackend) {.base.} =
  discard

method size*(backend: TerminalBackend): Size {.base.} =
  size(80, 24)

method readEvent*(backend: TerminalBackend, timeoutMs: int): UiEvent {.base.} =
  discard timeoutMs
  UiEvent(kind: uiNone)

method present*(backend: TerminalBackend, frame: Canvas) {.base.} =
  discard frame
