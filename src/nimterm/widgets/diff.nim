## Generic diff document and renderer.

import std/[json, strutils]
import ../canvas
import ../geometry
import ../style
import ../widget

type
  DiffLineKind* = enum
    dlContext
    dlRemoved
    dlAdded
    dlHeader

  DiffLine* = object
    kind*: DiffLineKind
    oldNumber*: int
    newNumber*: int
    text*: string

  DiffDocument* = object
    path*: string
    lines*: seq[DiffLine]
    additions*: int
    removals*: int

  DiffCard* = ref object of Widget
    document*: DiffDocument
    contextStyle*: Style
    addedStyle*: Style
    removedStyle*: Style
    headerStyle*: Style

proc newDiffCard*(document: DiffDocument, contextStyle = defaultStyle(),
                  addedStyle = defaultStyle(), removedStyle = defaultStyle(),
                  headerStyle = defaultStyle()): DiffCard =
  DiffCard(document: document, contextStyle: contextStyle,
    addedStyle: addedStyle, removedStyle: removedStyle, headerStyle: headerStyle)

proc toolDiffDocument*(name: string, input: JsonNode): DiffDocument =
  ## Build the small diff shown for successful edit/write tool cards.
  if input.isNil or input.kind != JObject or name notin ["edit", "write"]:
    return
  result.path = input.getOrDefault("path").getStr
  if name == "write":
    for line in input.getOrDefault("content").getStr.splitLines:
      result.lines.add DiffLine(kind: dlAdded, newNumber: result.lines.len + 1,
        text: line)
  else:
    var replacements: seq[tuple[oldText, newText: string]]
    let many = input.getOrDefault("replacements")
    if not many.isNil and many.kind == JArray:
      for replacement in many:
        replacements.add (replacement.getOrDefault("old_text").getStr,
          replacement.getOrDefault("new_text").getStr)
    elif "old_text" in input:
      replacements.add (input["old_text"].getStr,
        input.getOrDefault("new_text").getStr)
    for replacement in replacements:
      for line in replacement.oldText.splitLines:
        result.lines.add DiffLine(kind: dlRemoved, oldNumber: result.removals + 1,
          text: line)
        inc result.removals
      for line in replacement.newText.splitLines:
        result.lines.add DiffLine(kind: dlAdded, newNumber: result.additions + 1,
          text: line)
        inc result.additions
  if name == "write": result.additions = result.lines.len

proc diffPrefix(line: DiffLine): string =
  case line.kind
  of dlContext: "  "
  of dlRemoved: "- "
  of dlAdded: "+ "
  of dlHeader: "@@ "

proc diffStyle(widget: DiffCard, kind: DiffLineKind): Style =
  case kind
  of dlContext: widget.contextStyle
  of dlRemoved: widget.removedStyle
  of dlAdded: widget.addedStyle
  of dlHeader: widget.headerStyle

method measure*(widget: DiffCard, constraints: Constraints): Size =
  var width = widget.document.path.len + 4
  var height = 1
  for line in widget.document.lines:
    width = max(width, line.text.len + 2)
    inc height
  constraints.clamp(size(width, height))

method paint*(widget: DiffCard, canvas: var Canvas) =
  if widget.area.h <= 0: return
  canvas.writeText(widget.area.x, widget.area.y, widget.document.path,
    widget.headerStyle, widget.area.w)
  for i, line in widget.document.lines:
    let y = widget.area.y + i + 1
    if y >= widget.area.y + widget.area.h: break
    canvas.writeText(widget.area.x, y, diffPrefix(line) & line.text,
      widget.diffStyle(line.kind), widget.area.w)
