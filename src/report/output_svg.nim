## Renders a report as a standalone SVG, one column per suite.

import std/[math, unicode, tables, xmltree]
import parser, data_table

const
  Ink = "#000000"
  Paper = "#ffffff"
  Muted = "#555555"
  Rule = "#cccccc"

  FontStack = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

  FontSize = 14
  SubFontSize = 11

  Aspect = 0.6

  CellPad = 12
  LineHeight = 24
  SubLineHeight = 18
  Descent = 7

  Placeholder = "-"

proc width(cell: TableCell): int =
  ## The room this cell needs, padding included. Measured in runes: the values
  ## carry `µ`, which is one glyph and two bytes.
  assert cell != nil
  let size = if cell.small: SubFontSize else: FontSize
  ceil(cell.text.runeLen.float * size.float * Aspect).int + CellPad * 2

proc height(cell: TableCell): int =
  assert cell != nil
  if cell.small: SubLineHeight else: LineHeight

proc render(cell: TableCell, x, y: int): XmlNode =
  var attrs = @{
    "x": $x,
    "y": $y,
    "text-anchor": if cell.alignRight: "end" else: "start",
    "fill": if cell.muted: Muted else: Ink
  }

  if cell.small:
    attrs.add ("font-size", $SubFontSize)
  if cell.bold:
    attrs.add ("font-weight", "600")

  newXmlTree("text", [newText(cell.text)], attrs.toXmlAttributes)

proc divider(y, width: int): XmlNode =
  newXmlTree("line", [], {
    "x1": "0",
    "y1": $y,
    "x2": $width,
    "y2": $y,
    "stroke": Rule,
    "stroke-width": "1"
  }.toXmlAttributes)

proc offsets(sizes: seq[int]): seq[int] =
  var running = 0
  for size in sizes:
    result.add running
    running += size

proc renderSvg*(report: Report): string =
  let rows = report.asTableCells()

  let widths = rows.columnWidths(width)
  let heights = rows.rowHeights(height)
  let columnX = widths.offsets
  let rowY = heights.offsets

  let total = sum(widths)
  let height = sum(heights)

  var nodes = @[
    newXmlTree("rect", [], {
      "width": $total,
      "height": $height,
      "fill": Paper
    }.toXmlAttributes)
  ]

  for index, row in rows:
    let y = rowY[index]

    for column, cell in row:
      if cell.text.len == 0:
        continue

      let x =
        if cell.alignRight: columnX[column] + widths[column] - CellPad
        else: columnX[column] + CellPad

      nodes.add cell.render(x, y + heights[index] - Descent)

    if index mod 2 == 1:
      nodes.add divider(y + heights[index], total)

  let svg = newXmlTree("svg", nodes, {
    "xmlns": "http://www.w3.org/2000/svg",
    "width": $total,
    "height": $height,
    "viewBox": "0 0 " & $total & " " & $height,
    "font-family": FontStack,
    "font-size": $FontSize
  }.toXmlAttributes)

  return $svg
