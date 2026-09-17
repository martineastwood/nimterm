## Small Markdown renderer for terminal text and widgets.

import std/[sequtils, strutils]
import ./style
import ./styled_text
import ./theme

type RenderState = enum normal, codeBlock, table

proc inline(text: string): StyledLine =
  let t = currentTheme
  var i = 0
  while i < text.len:
    var marker = ""
    var style = defaultStyle()
    if text.continuesWith("***", i):
      marker = "***"; style = style.withAttribute(attrBold).withAttribute(attrItalic)
    elif text.continuesWith("~~", i):
      marker = "~~"; style = style.withAttribute(attrStrikethrough)
    elif text.continuesWith("**", i):
      marker = "**"; style = style.withAttribute(attrBold)
    elif text[i] == '*': marker = "*"; style = style.withAttribute(attrItalic)
    elif text[i] == '`': marker = "`"; style = t.code
    if marker.len > 0:
      let close = text.find(marker, i + marker.len)
      if close >= 0:
        result.add(text[i + marker.len ..< close], style)
        i = close + marker.len
        continue
    if text[i] == '[':
      let close = text.find(']', i + 1)
      if close > i and close + 1 < text.len and text[close + 1] == '(':
        let finish = text.find(')', close + 2)
        if finish > close:
          result.add(text[i + 1 ..< close], style.withAttribute(attrUnderline))
          result.add(" " & text[close + 2 ..< finish], t.dim)
          i = finish + 1
          continue
    result.add($text[i])
    inc i

proc cells(line: string): seq[string] =
  var value = line.strip
  if value.startsWith("|"): value = value[1 .. ^1]
  if value.endsWith("|"): value = value[0 ..< value.high]
  for cell in value.split('|'): result.add cell.strip

proc tableSeparator(line: string): bool =
  let values = line.cells
  if values.len == 0: return false
  for cell in values:
    if cell.len == 0: return false
    for ch in cell:
      if ch notin {'-', ':', ' '}: return false
  true

proc renderTable(rows: seq[seq[string]], maxWidth: int): seq[StyledLine] =
  if rows.len == 0: return
  let count = rows[0].len
  var widths = newSeq[int](count)
  for row in rows:
    for i in 0 ..< min(count, row.len): widths[i] = max(widths[i], row[i].inline.width)
  if maxWidth > 0:
    var total = widths.foldl(a + b, 0)
    let available = max(0, maxWidth - 3 * count - 1)
    while total > available:
      var widest = 0
      for i in 1 ..< widths.len:
        if widths[i] > widths[widest]: widest = i
      if widths[widest] <= 1: break
      dec widths[widest]; dec total
  proc border(left, joiner, right: string): StyledLine =
    result.add(left & widths.mapIt("─".repeat(it + 2)).join(joiner) & right,
      currentTheme.dim)
  result.add border("┌", "┬", "┐")
  for rowIndex, row in rows:
    var wrapped = newSeq[seq[StyledLine]](count)
    var height = 1
    for column in 0 ..< count:
      let content: StyledLine = if column < row.len: row[column].inline else: @[]
      wrapped[column] = content.wrap(max(1, widths[column]))
      height = max(height, wrapped[column].len)
    for lineIndex in 0 ..< height:
      var line: StyledLine
      line.add("│")
      for column in 0 ..< count:
        line.add(" ")
        let content: StyledLine = if lineIndex < wrapped[column].len: wrapped[column][lineIndex] else: @[]
        let rowStyle = if rowIndex == 0: currentTheme.heading else: defaultStyle()
        for span in content: line.add(span.text, rowStyle.overlay(span.style))
        line.add(" ".repeat(max(0, widths[column] - content.width + 1)))
        line.add("│")
      result.add line
    if rowIndex == 0: result.add border("├", "┼", "┤")
  result.add border("└", "┴", "┘")

proc renderMarkdownLines*(text: string, maxWidth = 0): seq[StyledLine] =
  let lines = text.splitLines
  var state = normal
  var code: seq[string]
  var rows: seq[seq[string]]
  for i, source in lines:
    case state
    of normal:
      if source.startsWith("```"): state = codeBlock; code = @[]
      elif source.strip.contains("|") and i + 1 < lines.len and lines[i + 1].tableSeparator:
        state = table; rows = @[source.cells]
      elif source.strip in ["---", "***"]:
        var line: StyledLine; line.add("─".repeat(40), currentTheme.dim); result.add line
      else:
        var line: StyledLine
        if source.startsWith("### "): line = source[4 .. ^1].strip.inline
        elif source.startsWith("## "): line = source[3 .. ^1].strip.inline
        elif source.startsWith("# "): line = source[2 .. ^1].strip.inline
        elif source.startsWith("> "): line.add("│ ", currentTheme.dim); line.add(source[2 .. ^1])
        elif source.len >= 2 and source[0] in {'-', '*'} and source[1] == ' ':
          line.add("• "); for span in source[2 .. ^1].inline: line.add(span.text, span.style)
        elif source.len >= 3 and source[0].isDigit and source[1] == '.' and source[2] == ' ':
          line.add(source[0 .. 2]); for span in source[3 .. ^1].inline: line.add(span.text, span.style)
        else: line = source.inline
        if source.startsWith("#"):
          for span in line.mitems: span.style = currentTheme.heading.overlay(span.style)
        result.add line
    of codeBlock:
      if source.startsWith("```"):
        for value in code:
          var line: StyledLine; line.add(value, currentTheme.dim); result.add line
        state = normal
      else: code.add source
    of table:
      if source.strip.contains("|"):
        if not (rows.len == 1 and source.tableSeparator): rows.add source.cells
      else:
        result.add renderTable(rows, maxWidth)
        rows = @[]; state = normal
        if source.len > 0: result.add source.inline
  if state == codeBlock:
    for value in code:
      var line: StyledLine; line.add(value, currentTheme.dim); result.add line
  elif state == table: result.add renderTable(rows, maxWidth)

proc renderMarkdown*(text: string, useColor: bool, maxWidth = 0): string =
  renderMarkdownLines(text, maxWidth).mapIt(it.ansi(useColor and currentTheme.colorsOn)).join("\n")
