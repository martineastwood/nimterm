## Small, deterministic application shell for widgets and event sources.

import ./backend
import ./canvas
import ./events
import ./geometry
import ./keys
import ./queue
import ./widget
import std/[monotimes, times]

type
  EventSource* = ref object of RootObj
    id*: string

  Timer = object
    id: string
    due: MonoTime
    intervalMs: int

method poll*(source: EventSource): seq[UiEvent] {.base.} = @[]
method close*(source: EventSource) {.base.} = discard
method needsPolling*(source: EventSource): bool {.base.} = true

type App* = object
  backend*: TerminalBackend
  root*: Widget
  queue*: EventQueue
  size*: Size
  frame*: Canvas
  running*: bool
  dirty*: bool
  focus*: Widget
  mouseCapture*: Widget
  onEvent*: proc (app: var App, event: UiEvent): EventResponse {.closure.}
  onAction*: proc (app: var App, action: UiAction) {.closure.}
  pollIntervalMs*: int
  minFrameIntervalMs*: int
  sources*: seq[EventSource]
  timers: seq[Timer]
  lastPresent: MonoTime

proc newApp*(backend: TerminalBackend, root: Widget = nil): App =
  result.backend = backend
  result.queue = newEventQueue()
  result.root = root
  result.size = if backend.isNil: size(80, 24) else: backend.size()
  result.frame = newCanvas(result.size)
  result.dirty = true
  result.pollIntervalMs = 16

proc addSource*(app: var App, source: EventSource) =
  if not source.isNil: app.sources.add source

proc schedule*(app: var App, id: string, delayMs: int, intervalMs = 0) =
  app.timers.add Timer(id: id, due: getMonoTime() +
    initDuration(milliseconds = max(0, delayMs)), intervalMs: intervalMs)

proc cancelTimer*(app: var App, id: string) =
  for i in countdown(app.timers.high, 0):
    if app.timers[i].id == id: app.timers.delete(i)

proc collectEvents(app: var App) =
  var i = 0
  while i < app.sources.len:
    let source = app.sources[i]
    try:
      for event in source.poll: app.queue.post(event)
      inc i
    except CatchableError as error:
      app.queue.post UiEvent(kind: uiError, sourceId: source.id,
        error: error.msg)
      try: source.close()
      except CatchableError: discard
      app.sources.delete(i)
  let now = getMonoTime()
  for i in countdown(app.timers.high, 0):
    if now < app.timers[i].due: continue
    app.queue.post UiEvent(kind: uiTimer, timerId: app.timers[i].id)
    if app.timers[i].intervalMs > 0:
      app.timers[i].due = now +
        initDuration(milliseconds = app.timers[i].intervalMs)
    else:
      app.timers.delete(i)

proc waitTimeout(app: App, requested: int): int =
  result = requested
  let now = getMonoTime()
  for timer in app.timers:
    let remaining = max(0'i64, (timer.due - now).inMilliseconds).int
    if result < 0 or remaining < result: result = remaining

proc idleTimeout(app: App): int =
  for source in app.sources:
    if source.needsPolling: return app.pollIntervalMs
  -1

proc invalidate*(app: var App) =
  app.dirty = true

proc post*(app: var App, event: UiEvent) =
  app.queue.post(event)
  if not app.backend.isNil: app.backend.wake()

proc focus*(app: var App, widget: Widget) =
  app.focus = if not widget.isNil and widget.focusable and
      widget.visible and widget.enabled and not app.root.isNil and
      app.root.contains(widget): widget else: nil

proc focusables(widget: Widget, result: var seq[Widget]) =
  if widget.isNil or not widget.visible or not widget.enabled: return
  if widget.focusable: result.add widget
  for child in widget.children: child.focusables(result)

proc moveFocus(app: var App, root: Widget, delta: int) =
  var candidates: seq[Widget]
  root.focusables(candidates)
  if candidates.len == 0: return
  let current = candidates.find(app.focus)
  app.focus = candidates[(if current < 0: 0 else:
    (current + delta + candidates.len) mod candidates.len)]

proc pathTo(widget, target: Widget, path: var seq[Widget]): bool =
  if widget.isNil or not widget.visible or not widget.enabled: return false
  path.add widget
  if widget == target: return true
  for child in widget.children:
    if child.pathTo(target, path): return true
  path.setLen(path.len - 1)

proc hitPath(widget: Widget, x, y: int, path: var seq[Widget]): bool =
  if widget.isNil or not widget.visible or not widget.enabled or
      not widget.area.contains(x, y): return false
  path.add widget
  let kids = widget.children
  for i in countdown(kids.high, 0):
    if kids[i].hitPath(x, y, path): return true
  true

proc route(path: seq[Widget], event: UiEvent): tuple[result: EventResponse,
                                                    target: Widget] =
  for i in countdown(path.high, 0):
    let response = path[i].handle(event)
    if response.handled: return (response, path[i])
  (eventIgnored, nil)

proc modalRoot(widget: Widget): Widget =
  if widget.isNil or not widget.visible or not widget.enabled: return nil
  let kids = widget.children
  for i in countdown(kids.high, 0):
    let nested = kids[i].modalRoot
    if not nested.isNil: return nested
  if widget.modal: widget else: nil

proc applyResponse(app: var App, routed: tuple[result: EventResponse,
                                               target: Widget]) =
  if routed.result.requestFocus: app.focus(routed.target)
  if routed.result.captureMouse: app.mouseCapture = routed.target
  if routed.result.releaseMouse: app.mouseCapture = nil
  if routed.result.action.kind.len > 0 and not app.onAction.isNil:
    app.onAction(app, routed.result.action)

proc dispatch*(app: var App, event: UiEvent) =
  if event.kind == uiQuit:
    app.running = false
  if not app.onEvent.isNil and app.onEvent(app, event).handled:
    app.invalidate()
    return
  if not app.root.isNil:
    let scope = block:
      let modal = app.root.modalRoot
      if modal.isNil: app.root else: modal
    if not app.focus.isNil and not scope.contains(app.focus): app.focus = nil
    if not app.mouseCapture.isNil and not scope.contains(app.mouseCapture):
      app.mouseCapture = nil
    var path: seq[Widget]
    if event.kind == uiMouse:
      if not app.mouseCapture.isNil:
        discard scope.pathTo(app.mouseCapture, path)
      else: discard scope.hitPath(event.x, event.y, path)
      let routed = path.route(event)
      app.applyResponse(routed)
      if event.mouse == umRelease: app.mouseCapture = nil
    else:
      if app.focus.isNil or not scope.pathTo(app.focus, path): path = @[scope]
      let routed = path.route(event)
      app.applyResponse(routed)
      if not routed.result.handled and event.kind == uiKey and
          event.key in {keyTab, keyShiftTab}:
        app.moveFocus(scope, if event.key == keyTab: 1 else: -1)
  app.invalidate()

proc render*(app: var App) =
  if app.backend.isNil: return
  let nextSize = app.backend.size()
  if nextSize != app.size:
    app.size = nextSize
    app.frame = newCanvas(app.size)
  else:
    app.frame.clear()
  if not app.root.isNil:
    app.root.render(app.frame, rect(0, 0, app.size.w, app.size.h))
  app.backend.present(app.frame)
  app.lastPresent = getMonoTime()
  app.dirty = false

proc flush*(app: var App, force = false) =
  if not app.dirty: return
  if force or app.minFrameIntervalMs <= 0 or
      (getMonoTime() - app.lastPresent).inMilliseconds >= app.minFrameIntervalMs:
    app.render()

proc step*(app: var App, timeoutMs = 0): bool =
  ## Process one queued/backend event and render if invalidated.
  var event: UiEvent
  var hasEvent = app.queue.tryPop(event)
  if not hasEvent:
    app.collectEvents()
    hasEvent = app.queue.tryPop(event)
  if not hasEvent:
    if app.backend.isNil:
      return false
    event = app.backend.readEvent(app.waitTimeout(timeoutMs))
    if event.kind == uiNone:
      app.collectEvents()
      if not app.queue.tryPop(event): return false
  try:
    app.dispatch(event)
  except CatchableError as error:
    if event.kind != uiError:
      app.queue.post UiEvent(kind: uiError, sourceId: "dispatch",
        error: error.msg)
    app.invalidate()
  app.flush()
  true

proc pump*(app: var App, timeoutMs = 0): bool = app.step(timeoutMs)

proc run*(app: var App) =
  if app.backend.isNil:
    raise newException(ValueError, "nimterm App requires a terminal backend")
  defer:
    for source in app.sources:
      try: source.close()
      except CatchableError: discard
    app.backend.shutdown()
  app.backend.init()
  app.running = true
  app.render()
  while app.running:
    discard app.step(app.idleTimeout)
    app.flush()
