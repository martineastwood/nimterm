## Minimal markdown-to-ANSI renderer.
##
## Stateless by design, so callers can re-render accumulated streaming text.
## Supports the subset that shows up regularly in coding-agent replies:
## headings, fenced code blocks, inline code, bold, italic, links, lists,
## blockquotes, horizontal rules, and tables.

import std/[strutils, sequtils]
import ./ansi
import ./text_width
import ./theme

type
  RenderState = enum
    rsNormal
    rsCodeBlock
    rsTable

proc renderInline(text: string, useColor: bool): string =
  ## Render inline markdown: `code`, ***bold italic***, **bold**, *italic*, links.
  result = text
  let t = currentTheme
  let color = useColor and t.colorsOn
  if not color:
    var i = 0
    var acc = ""
    while i < result.len:
      if result[i] == '`':
        let close = result.find('`', i + 1)
        if close > 0:
          acc.add result[i + 1 ..< close]
          i = close + 1
          continue
      if i + 2 < result.len and result[i] == '*' and result[i + 1] == '*' and result[i + 2] == '*':
        let close = result.find("***", i + 3)
        if close > 0:
          acc.add result[i + 3 ..< close]
          i = close + 3
          continue
      if i + 1 < result.len and result[i] == '~' and result[i + 1] == '~':
        let close = result.find("~~", i + 2)
        if close > 0:
          if useColor:
            acc.add "\e[9m" & result[i + 2 ..< close] &
              (if t.reset.len > 0: t.reset else: "\e[0m")
          else:
            acc.add result[i + 2 ..< close]
          i = close + 2
          continue
      if i + 1 < result.len and result[i] == '*' and result[i + 1] == '*':
        let close = result.find("**", i + 2)
        if close > 0:
          acc.add result[i + 2 ..< close]
          i = close + 2
          continue
      if i + 1 < result.len and result[i] == '*' and result[i + 1] != '*':
        let close = result.find('*', i + 1)
        if close > 0:
          acc.add result[i + 1 ..< close]
          i = close + 1
          continue
      if result[i] == '[':
        let closeBr = result.find(']', i + 1)
        if closeBr > 0 and closeBr + 1 < result.len and result[closeBr + 1] == '(':
          let closeParen = result.find(')', closeBr + 2)
          if closeParen > 0:
            let label = result[i + 1 ..< closeBr]
            let url = result[closeBr + 2 ..< closeParen]
            acc.add label & " (" & url & ")"
            i = closeParen + 1
            continue
      acc.add result[i]
      inc i
    result = acc
    return

  # Colored rendering — check *** before ** before *.
  var i = 0
  var acc = ""
  while i < result.len:
    if result[i] == '`':
      let close = result.find('`', i + 1)
      if close > 0:
        acc.add t.paint(t.code, result[i + 1 ..< close])
        i = close + 1
        continue
    if i + 2 < result.len and result[i] == '*' and result[i + 1] == '*' and result[i + 2] == '*':
      let close = result.find("***", i + 3)
      if close > 0:
        acc.add "\e[1;3m" & result[i + 3 ..< close] & t.reset
        i = close + 3
        continue
    if i + 1 < result.len and result[i] == '~' and result[i + 1] == '~':
      let close = result.find("~~", i + 2)
      if close > 0:
        acc.add "\e[9m" & result[i + 2 ..< close] & t.reset
        i = close + 2
        continue
    if i + 1 < result.len and result[i] == '*' and result[i + 1] == '*':
      let close = result.find("**", i + 2)
      if close > 0:
        acc.add "\e[1m" & result[i + 2 ..< close] & t.reset
        i = close + 2
        continue
    if i + 1 < result.len and result[i] == '*' and result[i + 1] != '*':
      let close = result.find('*', i + 1)
      if close > 0:
        acc.add "\e[3m" & result[i + 1 ..< close] & t.reset
        i = close + 1
        continue
    if result[i] == '[':
      let closeBr = result.find(']', i + 1)
      if closeBr > 0 and closeBr + 1 < result.len and result[closeBr + 1] == '(':
        let closeParen = result.find(')', closeBr + 2)
        if closeParen > 0:
          let label = result[i + 1 ..< closeBr]
          let url = result[closeBr + 2 ..< closeParen]
          acc.add "\e[4m" & label & t.reset & " " & t.paint(t.dim, url)
          i = closeParen + 1
          continue
    acc.add result[i]
    inc i
  result = acc

proc parseTableRow(line: string): seq[string] =
  ## Split a markdown table row into cells.
  let trimmed = line.strip
  var s = trimmed
  if s.startsWith("|"): s = s[1 .. ^1]
  if s.endsWith("|"): s = s[0 ..< s.high]
  for cell in s.split("|"):
    result.add cell.strip

proc isTableSeparator(line: string): bool =
  ## Check if a line is a table separator like |---|---|
  let cells = parseTableRow(line)
  if cells.len == 0: return false
  for cell in cells:
    if cell.len == 0: return false
    for ch in cell:
      if ch != '-' and ch != ':' and ch != ' ': return false
  true

proc renderTable(rows: seq[seq[string]], useColor: bool,
                 maxWidth: int): seq[string] =
  ## Render a markdown table with Unicode box-drawing characters.
  if rows.len == 0: return
  let t = currentTheme
  let color = useColor and t.colorsOn

  let numCols = rows[0].len
  # Calculate column widths
  var colWidths = newSeq[int](numCols)
  for row in rows:
    for c, cell in row:
      if c < numCols:
        let visible = renderInline(cell, false)
        colWidths[c] = max(colWidths[c], displayWidth(visible))

  if maxWidth > 0:
    var total = 0
    for width in colWidths: total += width
    let available = max(0, maxWidth - (3 * numCols + 1))
    while total > available:
      var widest = 0
      for i, width in colWidths:
        if width > colWidths[widest]: widest = i
      if colWidths[widest] <= 1: break
      dec colWidths[widest]
      dec total

  let topBorder = "┌" & colWidths.mapIt("─".repeat(it + 2)).join("┬") & "┐"
  let midBorder = "├" & colWidths.mapIt("─".repeat(it + 2)).join("┼") & "┤"
  let botBorder = "└" & colWidths.mapIt("─".repeat(it + 2)).join("┴") & "┘"

  if color:
    result.add t.paint(t.dim, topBorder)
  else:
    result.add topBorder

  for r, row in rows:
    var cellLines = newSeq[seq[string]](numCols)
    var rowHeight = 1
    for c in 0 ..< numCols:
      let cell = if c < row.len: row[c] else: ""
      cellLines[c] = wrapAnsi(renderInline(cell, color), max(1, colWidths[c]), true)
      rowHeight = max(rowHeight, cellLines[c].len)
    for lineIndex in 0 ..< rowHeight:
      var line = "│"
      for c in 0 ..< numCols:
        let content = if lineIndex < cellLines[c].len: cellLines[c][lineIndex] else: ""
        let pad = colWidths[c] - ansiVisibleWidth(content)
        let cellText = " " & content & " ".repeat(max(0, pad)) & " "
        if r == 0 and color:
          line.add t.heading & cellText & t.reset & "│"
        else:
          line.add cellText & "│"
      result.add line
    if r == 0:
      if color:
        result.add t.paint(t.dim, midBorder)
      else:
        result.add midBorder

  if color:
    result.add t.paint(t.dim, botBorder)
  else:
    result.add botBorder

proc renderMarkdown*(text: string, useColor: bool, maxWidth = 0): string =
  ## Render a markdown response to a string with optional ANSI colors.
  let t = currentTheme
  let color = useColor and t.colorsOn
  var lines = text.splitLines
  var rendered: seq[string] = @[]
  var state = rsNormal
  var codeLines: seq[string] = @[]
  var codeLang = ""
  var tableRows: seq[seq[string]]

  for i, line in lines:
    case state
    of rsNormal:
      if line.startsWith("```"):
        state = rsCodeBlock
        codeLang = line[3 .. ^1].strip
        codeLines = @[]
        continue
      # Detect a table only once its header separator has arrived.
      if line.strip.contains("|") and i + 1 < lines.len and
          isTableSeparator(lines[i + 1]):
        state = rsTable
        tableRows = @[parseTableRow(line)]
        continue
      if line.strip == "---" or line.strip == "***":
        if color:
          rendered.add t.paint(t.dim, "─".repeat(40))
        else:
          rendered.add "─".repeat(40)
        continue
      if line.startsWith("# "):
        let body = renderInline(line[2 .. ^1].strip, color)
        rendered.add (if color: t.paint(t.heading, body) else: body)
      elif line.startsWith("## "):
        let body = renderInline(line[3 .. ^1].strip, color)
        rendered.add (if color: t.paint(t.heading, body) else: body)
      elif line.startsWith("### "):
        let body = renderInline(line[4 .. ^1].strip, color)
        rendered.add (if color: t.paint(t.heading, body) else: body)
      elif line.startsWith("> "):
        let body = renderInline(line[2 .. ^1], color)
        rendered.add (if color: t.paint(t.dim, "│ " & body) else: "│ " & body)
      elif line.len >= 2 and line[0] in {'-', '*'} and line[1] == ' ':
        let body = renderInline(line[2 .. ^1], color)
        rendered.add "• " & body
      elif line.len >= 3 and line[0].isDigit and line[1] == '.' and line[2] == ' ':
        let dot = line.find(". ")
        let num = line[0 ..< dot]
        let body = renderInline(line[dot + 2 .. ^1], color)
        rendered.add num & ". " & body
      else:
        rendered.add renderInline(line, color)
    of rsCodeBlock:
      if line.startsWith("```"):
        if color:
          for codeLine in codeLines:
            rendered.add t.paint(t.dim, codeLine)
        else:
          rendered.add codeLines
        state = rsNormal
        codeLines = @[]
        codeLang = ""
      else:
        codeLines.add line
    of rsTable:
      if line.strip.contains("|"):
        if not (tableRows.len == 1 and isTableSeparator(line)):
          tableRows.add parseTableRow(line)
      else:
        # Table ended — render it
        rendered.add renderTable(tableRows, color, maxWidth)
        tableRows = @[]
        state = rsNormal
        # Re-process this line in normal mode
        if line.strip.len > 0:
          if line.startsWith("```"):
            state = rsCodeBlock
            codeLang = line[3 .. ^1].strip
            codeLines = @[]
          else:
            rendered.add renderInline(line, color)

  # Unterminated code block
  if state == rsCodeBlock and codeLines.len > 0:
    if color:
      for codeLine in codeLines:
        rendered.add t.paint(t.dim, codeLine)
    else:
      rendered.add codeLines

  # Unterminated table
  if state == rsTable and tableRows.len > 0:
    rendered.add renderTable(tableRows, color, maxWidth)

  result = rendered.join("\n")
