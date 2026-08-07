import std/[math, tables], parser

const Placeholder = "-"

type
  TableCell* = ref object
    text*: string
    bold*, small*, muted*, alignRight*: bool

  CellSize* = proc (cell: TableCell): int

proc asTableCells*(report: Report): seq[seq[TableCell]] =
  ## Two header lines, then a time line and a memory line per metric. Cells the
  ## table has nothing to say in are empty.
  var names = @[TableCell(text: "Metric", bold: true), TableCell(text: "Entity Count", bold: true)]

  var architectures = @[TableCell(small: true), TableCell(small: true)]

  for suite in report.suites:
    names.add TableCell(text: suite.name, bold: true, alignRight: true)
    architectures.add TableCell(
      text: suite.architecture, small: true, muted: true, alignRight: true
    )

  result.add names
  result.add architectures

  for metric in report.metrics:
    var isFirst = true
    for entityCount in report.entityCounts:
      let key = (metric, entityCount)

      var times = @[TableCell(text: if isFirst: metric else: ""), TableCell(text: $entityCount)]
      isFirst = false

      for suite in report.suites:
        if key in suite.measurements:
          let measured = suite.measurements[key]
          times.add TableCell(
            text: measured.time, bold: measured.timeWinner, alignRight: true
          )
        else:
          times.add TableCell(text: Placeholder, muted: true, alignRight: true)

      result.add times

proc columnWidths*(rows: seq[seq[TableCell]], width: CellSize): seq[int] =
  ## The widest cell in a column is what the whole column has to accommodate.
  for column in 0 ..< rows[0].len:
    var widest = 0
    for row in rows:
      if column < row.len:
        widest = max(widest, width(row[column]))
    result.add widest

proc rowHeights*(rows: seq[seq[TableCell]], height: CellSize): seq[int] =
  for row in rows:
    var tallest = 0
    for cell in row:
      tallest = max(tallest, height(cell))
    result.add tallest
