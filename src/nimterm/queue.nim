## Thread-safe application event queue.

import std/[deques, locks]
import ./events

type EventQueue* = ref object
  lock: Lock
  events: Deque[UiEvent]

proc newEventQueue*(): EventQueue =
  new(result)
  initLock(result.lock)

proc post*(queue: EventQueue, event: UiEvent) =
  withLock queue.lock: queue.events.addLast(event)

proc tryPop*(queue: EventQueue, event: var UiEvent): bool =
  withLock queue.lock:
    if queue.events.len == 0: return false
    event = queue.events.popFirst()
    result = true
