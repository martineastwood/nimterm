## Small, deterministic application shell for widgets and event sources.

import ./backend
import ./canvas
import ./events
import ./geometry
import ./widget

type
  EventQueue* = object
    events: seq[UiEvent]

  App* = object
    backend*: TerminalBackend
    root*: Widget
    queue*: EventQueue
    size*: Size
    frame*: Canvas
    running*: bool
    dirty*: bool
    onEvent*: proc (app: var App, event: UiEvent) {.closure.}

proc post*(queue: var EventQueue, event: UiEvent) =
  queue.events.add event

proc tryPop*(queue: var EventQueue, event: var UiEvent): bool =
  if queue.events.len == 0:
    return false
  event = queue.events[0]
  queue.events.delete(0)
  true

proc pending*(queue: EventQueue): int = queue.events.len

proc newApp*(backend: TerminalBackend, root: Widget = nil): App =
  result.backend = backend
  result.root = root
  result.size = if backend.isNil: size(80, 24) else: backend.size()
  result.frame = newCanvas(result.size)
  result.running = false
  result.dirty = true

proc invalidate*(app: var App) =
  app.dirty = true

proc post*(app: var App, event: UiEvent) =
  app.queue.post(event)

proc dispatch*(app: var App, event: UiEvent) =
  if event.kind == uiQuit:
    app.running = false
  if not app.onEvent.isNil:
    app.onEvent(app, event)
  if not app.root.isNil:
    discard app.root.handle(event)
  app.invalidate()

proc render*(app: var App) =
  if app.backend.isNil:
    return
  let nextSize = app.backend.size()
  if nextSize != app.size:
    app.size = nextSize
    app.frame = newCanvas(app.size)
  else:
    app.frame.clear()
  if not app.root.isNil:
    app.root.render(app.frame, rect(0, 0, app.size.w, app.size.h))
  app.backend.present(app.frame)
  app.dirty = false

proc step*(app: var App, timeoutMs = 0): bool =
  ## Process one queued/backend event and render if invalidated.
  var event: UiEvent
  if not app.queue.tryPop(event):
    if app.backend.isNil:
      return false
    event = app.backend.readEvent(timeoutMs)
    if event.kind == uiNone:
      return false
  app.dispatch(event)
  if app.dirty:
    app.render()
  true

proc run*(app: var App) =
  if app.backend.isNil:
    raise newException(ValueError, "nimterm App requires a terminal backend")
  app.backend.init()
  defer: app.backend.shutdown()
  app.running = true
  app.render()
  while app.running:
    discard app.step(-1)
