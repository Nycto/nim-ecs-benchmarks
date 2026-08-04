## Renders a table to a standalone SVG: black text on white, nothing else.
##
## The output is embedded in the README by URL, which means GitHub's camo proxy
## serves it as an image and the reader's browser does the text shaping. That
## rules out a few things the format would otherwise allow:
##
## * No external references -- no webfonts, no `@import`, no linked stylesheets.
##   Camo fetches one file and nothing else, so anything not inline is missing.
## * No script and no animation. Camo serves static bytes.
## * No assumption about glyph widths. The font is whatever monospace the
##   reader's machine resolves, so columns are sized from an estimate with slack
##   and text is placed with `text-anchor` rather than at per-glyph offsets. A
##   font wider than the estimate makes a column look loose; it cannot make two
##   columns collide.
##
## This module knows nothing about benchmarks -- it takes headings and strings.

import strutils, sequtils, unicode

type
  Align* {.pure.} = enum
    ## Pure so that `Align.left` cannot be confused with `strutils.alignLeft`,
    ## which the caller uses to lay out its terminal table.
    left
    right
    center

  Column* = object
    heading*: string
    sub*: string ## Second header line, in smaller type. May be empty.
    align*: Align

  Cell* = object
    text*: string
    bold*: bool ## Used to mark the winning value on a line.

  Row* = object
    cells*: seq[Cell]
    ruleAbove*: bool

const
  Ink = "#000000"
  Paper = "#ffffff"
  Muted = "#555555"
  Rule = "#cccccc"

  FontStack = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

  FontSize = 14.0
  SubFontSize = 11.0

  # 0.6em is the advance width of every monospace face worth worrying about
  # (SF Mono 0.600, Menlo 0.602, DejaVu Sans Mono 0.602, Consolas 0.550), so
  # this over-estimates rather than under-estimates for the narrowest of them.
  CharWidth = FontSize * 0.6
  SubCharWidth = SubFontSize * 0.6

  CellPad = 12.0
  RowHeight = 24.0

proc escape(text: string): string =
  ## XML-escapes element content. Attribute values in this module are all
  ## generated, never caller-supplied, so quotes do not need handling.
  result = text.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))

proc width(column: Column, rows: seq[Row], index: int): float =
  ## Widest thing the column has to hold, plus padding on both sides. Measured
  ## in runes: the values carry `µ`, which is one glyph and two bytes.
  var widest = column.heading.runeLen.float * CharWidth
  widest = max(widest, column.sub.runeLen.float * SubCharWidth)

  for row in rows:
    if index < row.cells.len:
      widest = max(widest, row.cells[index].text.runeLen.float * CharWidth)

  result = widest + CellPad * 2

proc num(value: float): string =
  ## SVG coordinates. Fixed to two decimals, which is well past what a 14px grid
  ## can express but keeps the arithmetic from showing up as
  ## `123.00000000000001`.
  value.formatFloat(ffDecimal, 2)

proc text(
    x, y: float, anchor, fill, content: string, size = FontSize, bold = false
): string =
  result =
    "  <text x=\"" & num(x) & "\" y=\"" & num(y) & "\" text-anchor=\"" & anchor &
    "\" fill=\"" & fill & "\""
  if size != FontSize:
    result &= " font-size=\"" & num(size) & "\""
  if bold:
    result &= " font-weight=\"600\""
  result &= ">" & escape(content) & "</text>"

proc place(column: Column, x, columnWidth: float): (float, string) =
  ## Where the text goes within its column, and which anchor puts it there.
  case column.align
  of Align.left: (x + CellPad, "start")
  of Align.right: (x + columnWidth - CellPad, "end")
  of Align.center: (x + columnWidth / 2, "middle")

proc renderTable*(path: string, columns: seq[Column], rows: seq[Row]) =
  ## Writes the table to `path` as a standalone SVG.

  var widths: seq[float] = @[]
  for index, column in columns:
    widths.add column.width(rows, index)

  var offsets: seq[float] = @[]
  var total = 0.0
  for w in widths:
    offsets.add total
    total += w

  let hasSub = columns.anyIt(it.sub.len > 0)
  let headerHeight = if hasSub: 42.0 else: 30.0
  let height = headerHeight + rows.len.float * RowHeight

  var svg: seq[string] = @[]
  svg.add "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" & num(total) &
    "\" height=\"" & num(height) & "\" viewBox=\"0 0 " & num(total) & " " &
    num(height) & "\" font-family=\"" & FontStack & "\" font-size=\"" &
    num(FontSize) & "\">"
  svg.add "  <rect width=\"" & num(total) & "\" height=\"" & num(height) &
    "\" fill=\"" & Paper & "\"/>"

  # Header. The heading sits on the first line and the sub-heading, where a
  # column has one, on a smaller line below it.
  for index, column in columns:
    let (x, anchor) = column.place(offsets[index], widths[index])
    let baseline = if hasSub: 17.0 else: 20.0
    if column.heading.len > 0:
      svg.add text(x, baseline, anchor, Ink, column.heading, bold = true)
    if column.sub.len > 0:
      svg.add text(x, 33.0, anchor, Muted, column.sub, size = SubFontSize)

  svg.add "  <line x1=\"0\" y1=\"" & num(headerHeight) & "\" x2=\"" & num(total) &
    "\" y2=\"" & num(headerHeight) & "\" stroke=\"" & Rule & "\" stroke-width=\"1\"/>"

  for index, row in rows:
    let y = headerHeight + index.float * RowHeight

    if row.ruleAbove and index > 0:
      svg.add "  <line x1=\"0\" y1=\"" & num(y) & "\" x2=\"" & num(total) &
        "\" y2=\"" & num(y) & "\" stroke=\"" & Rule & "\" stroke-width=\"1\"/>"

    for column, cell in row.cells:
      if cell.text.len == 0:
        continue
      let (x, anchor) = columns[column].place(offsets[column], widths[column])
      let fill = if cell.text == "-": Muted else: Ink
      svg.add text(x, y + RowHeight / 2 + 5, anchor, fill, cell.text, bold = cell.bold)

  svg.add "  <line x1=\"0\" y1=\"" & num(height) & "\" x2=\"" & num(total) &
    "\" y2=\"" & num(height) & "\" stroke=\"" & Rule & "\" stroke-width=\"1\"/>"

  svg.add "</svg>"

  writeFile(path, svg.join("\n") & "\n")
