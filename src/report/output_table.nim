## Renders a report as a box-drawn table, one column per suite.

import std/[strutils, unicode, tables, sequtils]
import parser, data_table

proc getText(cell: TableCell, width: int, fill: string): string =
  return if cell == nil:
    fill.repeat(width)
  elif cell.alignRight:
    unicode.align(cell.text, width, fill.runeAt(0))
  else:
    unicode.alignLeft(cell.text, width, fill.runeAt(0))

proc line(left, right, join, fill: string, columnWidths: seq[int], values: seq[TableCell] = @[]): string =
  result = left
  var isFirst = true
  for i, columnWidth in columnWidths:
    if isFirst:
      isFirst = false
    else:
      result &= join

    let rowText = getText(if values.len > i: values[i] else: nil, columnWidth, fill)
    result &= fill & rowText & fill
  result &= right & "\n"

proc width(cell: TableCell): int = cell.text.len

proc renderTable*(report: Report): string =
  let rows = report.asTableCells()

  let widths = rows.columnWidths(width)
  result = line("╔", "╗", "╦", "═", widths)

  var previousLeftColumn = ""
  for row in rows:
    if row[0].text != previousLeftColumn and row[0].text != "":
      if previousLeftColumn != "":
        result &= line("╟", "╢", "╫", "─", widths)
      previousLeftColumn = row[0].text

    result &= line("║", "║", "║", " ", widths, row)

  result &= line("╚", "╝", "╩", "═", widths)
