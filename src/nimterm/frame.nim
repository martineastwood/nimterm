## Serialize a Canvas into a differential ANSI byte stream.
##
## Every terminal backend presents the same way: compare against the previous
## frame, emit only the damaged rows, and reuse the active SGR run. The canvas
## stays platform-neutral; this is where cells become terminal bytes.

from std/unicode import toUTF8
import ./canvas
import ./style

proc sameCell(a, b: Cell): bool =
  a.glyph.int == b.glyph.int and a.combining == b.combining and
    a.continuation == b.continuation and a.style == b.style

proc frameOutput*(frame, previous: Canvas, force = false): string =
  ## Diff `frame` against `previous`, emitting a cursor move per changed row.
  let full = force or frame.size != previous.size
  var output = newStringOfCap(frame.size.w * frame.size.h * 2)
  var activeStyle = defaultStyle()
  var hasStyle = false
  for y in 0 ..< frame.size.h:
    var first = 0
    var last = frame.size.w - 1
    if not full:
      while first <= last and sameCell(frame.getCell(first, y),
          previous.getCell(first, y)): inc first
      while last >= first and sameCell(frame.getCell(last, y),
          previous.getCell(last, y)): dec last
      if first > last: continue
      ## A wide glyph and its continuation cell must travel together.
      if frame.getCell(first, y).continuation or
          previous.getCell(first, y).continuation: dec first
      if last + 1 < frame.size.w and (frame.getCell(last + 1, y).continuation or
          previous.getCell(last + 1, y).continuation): inc last
    output.add "\e[" & $(y + 1) & ";" & $(first + 1) & "H"
    for x in first .. last:
      let cell = frame.getCell(x, y)
      if not hasStyle or activeStyle != cell.style:
        output.add "\e[0m"
        output.add cell.style.ansi
        activeStyle = cell.style
        hasStyle = true
      if not cell.continuation: output.add toUTF8(cell.glyph) & cell.combining
      if attrStrikethrough in cell.style.attributes and cell.glyph.int != 32:
        ## Some terminal emulators ignore SGR 9; draw a visible fallback.
        output.add "\u0336"
  if output.len > 0: output.add "\e[0m"
  output

proc presentFrame*(previous: var Canvas, hasPrevious: var bool, frame: Canvas) =
  ## Write the diff to stdout and remember `frame` for the next comparison.
  let output = frame.frameOutput(previous, not hasPrevious)
  if output.len == 0: return
  previous = frame.copy
  hasPrevious = true
  stdout.write(output)
  stdout.flushFile()
