## Terminal-cell geometry and sizing constraints.

type
  Size* = object
    w*: int
    h*: int

  Rect* = object
    x*: int
    y*: int
    w*: int
    h*: int

  Constraints* = object
    minSize*: Size
    maxSize*: Size

proc size*(w, h: int): Size = Size(w: max(0, w), h: max(0, h))

proc rect*(x, y, w, h: int): Rect =
  Rect(x: x, y: y, w: max(0, w), h: max(0, h))

proc unconstrained*(): Constraints =
  Constraints(minSize: size(0, 0), maxSize: size(int.high, int.high))

proc clamp*(constraints: Constraints, wanted: Size): Size =
  Size(
    w: min(constraints.maxSize.w, max(constraints.minSize.w, wanted.w)),
    h: min(constraints.maxSize.h, max(constraints.minSize.h, wanted.h)))

proc contains*(area: Rect, x, y: int): bool =
  x >= area.x and y >= area.y and x < area.x + area.w and y < area.y + area.h
