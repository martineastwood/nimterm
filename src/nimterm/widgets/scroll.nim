## Shared viewport state for vertically scrollable widgets.

type
  ScrollView* = object
    contentHeight*: int
    viewportHeight*: int
    offset*: int
    followTail*: bool

proc newScrollView*(followTail = true): ScrollView =
  ScrollView(followTail: followTail)

proc maxOffset*(view: ScrollView): int =
  max(0, view.contentHeight - view.viewportHeight)

proc clampOffset(view: var ScrollView) =
  view.offset = clamp(view.offset, 0, view.maxOffset)

proc update*(view: var ScrollView, contentHeight, viewportHeight: int) =
  view.contentHeight = max(0, contentHeight)
  view.viewportHeight = max(0, viewportHeight)
  if view.followTail: view.offset = view.maxOffset
  view.clampOffset()

proc scrollBy*(view: var ScrollView, lines: int) =
  view.offset += lines
  view.clampOffset()
  view.followTail = view.offset == view.maxOffset

proc pageBy*(view: var ScrollView, pages: int) =
  view.scrollBy(pages * max(1, view.viewportHeight - 1))

proc home*(view: var ScrollView) =
  view.offset = 0
  view.followTail = view.maxOffset == 0

proc tail*(view: var ScrollView) =
  view.offset = view.maxOffset
  view.followTail = true

proc visibleRange*(view: ScrollView): Slice[int] =
  view.offset ..< min(view.contentHeight, view.offset + view.viewportHeight)
