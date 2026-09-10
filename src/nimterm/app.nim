## Small, deterministic application shell for widgets and event sources.

import ./backend
import ./canvas
import ./events
import ./geometry
import ./keys
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
    focus*: Widget
    mouseCapture*: Widget
    onEvent*: proc (app: var App, event: UiEvent): EventResult {.closure.}
    onPoll*: proc (app: var App) {.closure.}
    pollIntervalMs*: int

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
  result.pollIntervalMs = 16

proc invalidate*(app: var App) =
  app.dirty = true

proc post*(app: var App, event: UiEvent) =
  app.queue.post(event)

proc focus*(app: var App, widget: Widget) =
  app.focus = if not widget.isNil and widget.focusable and
      not app.root.isNil and app.root.contains(widget): widget else: nil

proc focusables(widget: Widget, result: var seq[Widget]) =
  if widget.isNil: return
  if widget.focusable: result.add widget
  for child in widget.children: child.focusables(result)

proc moveFocus(app: var App, delta: int) =
  var candidates: seq[Widget]
  app.root.focusables(candidates)
  if candidates.len == 0: return
  let current = candidates.find(app.focus)
  app.focus = candidates[(if current < 0: 0 else:
    (current + delta + candidates.len) mod candidates.len)]

proc pathTo(widget, target: Widget, path: var seq[Widget]): bool =
  if widget.isNil: return false
  path.add widget
  if widget == target: return true
  for child in widget.children:
    if child.pathTo(target, path): return true
  path.setLen(path.len - 1)

proc hitPath(widget: Widget, x, y: int, path: var seq[Widget]): bool =
  if widget.isNil or not widget.area.contains(x, y): return false
  path.add widget
  let kids = widget.children
  for i in countdown(kids.high, 0):
    if kids[i].hitPath(x, y, path): return true
  true

proc route(path: seq[Widget], event: UiEvent): tuple[result: EventResult,
                                                    target: Widget] =
  for i in countdown(path.high, 0):
    if path[i].handle(event) == eventHandled:
      return (eventHandled, path[i])
  (eventIgnored, nil)

proc dispatch*(app: var App, event: UiEvent) =
  if event.kind == uiQuit:
    app.running = false
  if not app.onEvent.isNil and app.onEvent(app, event) == eventHandled:
    app.invalidate()
    return
  if not app.root.isNil:
    var path: seq[Widget]
    if event.kind == uiMouse:
      let target = if not app.mouseCapture.isNil: app.mouseCapture else: nil
      if not target.isNil: discard app.root.pathTo(target, path)
      else: discard app.root.hitPath(event.x, event.y, path)
      let routed = path.route(event)
      if event.mouse == umPress and routed.result == eventHandled:
        app.focus(routed.target)
        app.mouseCapture = routed.target
      elif event.mouse == umRelease:
        app.mouseCapture = nil
    else:
      if app.focus.isNil or not app.root.pathTo(app.focus, path): path = @[app.root]
      let routed = path.route(event)
      if routed.result == eventIgnored and event.kind == uiKey and
          event.key in {keyTab, keyShiftTab}:
        app.moveFocus(if event.key == keyTab: 1 else: -1)
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
    if not app.step(app.pollIntervalMs) and not app.onPoll.isNil:
      app.onPoll(app)
      if app.dirty: app.render()
