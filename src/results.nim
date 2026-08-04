## Renders the comparison table from the CSVs the benchmark suites produce.
##
## Pass CSV paths to compare a specific set of files; with no arguments every
## `*.csv` in the current directory is used.
##
## Two things come out of a run: the table below on stdout, and `site/`, which
## holds the same table as an SVG for CI to publish.

import os, strutils, unicode, tables, sets, math, algorithm
import report_svg

let metrics = @[
  "create entity",
  "delete entity",
  "add component",
  "remove component",
  "add remove component",
  "iteration",
  "heterogeneous iter",
  "pristine iter",
  "churn iter",
  "read",
  "write"
]

let metricWidth = 20
let labelWidth = 4
let valueWidth = 10
let winnerMark = "*"

# Named for what it holds rather than where it lands, so it does not collide
# with `report_svg.Cell`, which is a cell of a rendered table.
type Measurement = tuple[time, mem: string, seconds, bytes: float]

var comparisons = Table[string, Table[string, Measurement]]()
var suiteOrder: seq[string] = @[]

# The architecture each suite implements. This is editorial -- it is nowhere in
# the CSVs -- so it lives here rather than being inferred. Anything not listed
# renders without a sub-heading instead of guessing.
let architectures = {
  "Cruise Dense": "Archetype",
  "Cruise Sparse": "Sparse set",
  "Easyess": "Bitset/table",
  "MiniECS": "Sparse set",
  "Necsus": "Framework",
  "Pirata": "Preallocated",
  "Polymorph": "Generative",
  "Vecs": "Archetype",
}.toTable

# Time and memory are stacked
let firstColumnWidth = metricWidth + 1 + labelWidth

# Each value is rendered as " <value> <mark> ", where the mark is the winner
let columnWidth = valueWidth + 4

proc rule(left: string, right: string, join: string, fill: string, columnCount: int): string =
  result = left & fill.repeat(firstColumnWidth + 2) & join
  for i in 0 ..< columnCount:
    result &= fill.repeat(columnWidth) & (if i == columnCount - 1: right else: join)

proc header(infos: seq[string]): string =
  result = "║ " & " ".repeat(firstColumnWidth) & " ║"

  for info in infos:
    let name = if info.runeLen > columnWidth: info.runeSubStr(0, columnWidth) else: info
    result &= name.center(columnWidth) & "║"

proc line(name, label: string, values: seq[tuple[value: string, won: bool]]): string =
  ## One half of a metric: every suite's time, or every suite's memory. `name`
  ## is blank on the memory line, which the label alone identifies.
  result = "║ " & name.alignLeft(metricWidth) & " " & label.alignLeft(labelWidth) & " ║"

  for (value, won) in values:
    let mark = if won: winnerMark else: " "
    result &= " " & unicode.align(value, valueWidth) & " " & mark & " ║"

proc toNumber(value: string): float =
  ## Reads one of the raw CSV columns. Anything unparseable sorts last.
  try:
    return parseFloat(value.strip())
  except ValueError:
    return Inf

proc winners(values: Table[string, float]): HashSet[string] =
  ## The suites tied for the lowest value. A metric only one suite reports is
  ## not a contest, so it has no winner to mark.
  result = initHashSet[string]()
  if values.len < 2:
    return

  var best = Inf
  for value in values.values:
    if value > 0:
      best = min(best, value)

  if best == Inf:
    return

  for suite, value in values:
    if value == best:
      result.incl(suite)

proc csvFiles(): seq[string] =
  ## The CSVs named on the command line, or every CSV in the working directory.
  result = commandLineParams()
  if result.len > 0:
    return

  for csvFile in walkFiles("*.csv"):
    result.add(csvFile)
  result.sort()

for metric in metrics:
  comparisons[metric] = Table[string, Measurement]()

for csvFile in csvFiles():
  let lines = readFile(csvFile).splitLines()
  if lines.len == 0:
    continue

  let bench = lines[0].split(',')[0]
  suiteOrder.add(bench)

  for line in lines[1..^1]:
    if line.len == 0:
      continue

    let parts = line.split(',')
    if parts.len < 5:
      continue

    let metric = parts[0]

    if metric in comparisons:
      comparisons[metric][bench] = (
        time: parts[1].strip(),
        mem: parts[2].strip(),
        seconds: parts[3].toNumber,
        bytes: parts[4].toNumber
      )

if suiteOrder.len == 0:
  echo "No benchmark CSVs found"
  quit(1)

# Collected as well as printed. `run_benchmarks.sh` sends every suite's own
# output to this same stdout first, so by the end the combined table is buried
# under thousands of lines of per-benchmark detail; CI needs it on its own to
# put in the job summary.
var report: seq[string] = @[]

proc emit(line: string) =
  echo line
  report.add line

emit ""
emit rule("╔", "╗", "╦", "═", suiteOrder.len)
emit header(suiteOrder)
emit rule("╠", "╣", "╬", "═", suiteOrder.len)

for index, metric in metrics:
  var timeValues = Table[string, float]()
  var memValues = Table[string, float]()

  for suite, results in comparisons[metric]:
    timeValues[suite] = results.seconds
    memValues[suite] = results.bytes

  let timeWinners = winners(timeValues)
  let memWinners = winners(memValues)

  var times: seq[tuple[value: string, won: bool]] = @[]
  var mems: seq[tuple[value: string, won: bool]] = @[]

  for suite in suiteOrder:
    if suite in comparisons[metric]:
      let results = comparisons[metric][suite]
      times.add((results.time, suite in timeWinners))
      mems.add((results.mem, suite in memWinners))
    else:
      times.add(("-", false))
      mems.add(("-", false))

  if index > 0:
    emit rule("╟", "╢", "╫", "─", suiteOrder.len)

  emit line(metric, "time", times)
  emit line("", "mem", mems)

emit rule("╚", "╝", "╩", "═", suiteOrder.len)
emit ""
emit winnerMark & " marks the best value on the line, time and memory judged separately."

# ============================================================================
# SVG report
# ============================================================================
#
# The same numbers as one image. CI publishes `site/` to GitHub Pages and the
# README embeds it by URL, which is the only way a README can show a table it
# does not itself contain -- and it has to come from Pages rather than from the
# repo, because raw.githubusercontent.com serves SVG as text/plain.

const SiteDir = "site"

createDir(SiteDir)

block svgReport:
  var columns = @[
    Column(heading: "Metric", align: Align.left),
    Column(heading: "", align: Align.left),
  ]
  for suite in suiteOrder:
    columns.add Column(
      heading: suite, sub: architectures.getOrDefault(suite, ""), align: Align.right
    )

  var rows: seq[Row] = @[]
  for index, metric in metrics:
    var timeValues = Table[string, float]()
    var memValues = Table[string, float]()

    for suite, results in comparisons[metric]:
      timeValues[suite] = results.seconds
      memValues[suite] = results.bytes

    let timeWinners = winners(timeValues)
    let memWinners = winners(memValues)

    var timeRow =
      Row(cells: @[Cell(text: metric), Cell(text: "time")], ruleAbove: true)
    var memRow = Row(cells: @[Cell(text: ""), Cell(text: "mem")])

    for suite in suiteOrder:
      if suite in comparisons[metric]:
        let results = comparisons[metric][suite]
        timeRow.cells.add Cell(text: results.time, bold: suite in timeWinners)
        memRow.cells.add Cell(text: results.mem, bold: suite in memWinners)
      else:
        timeRow.cells.add Cell(text: "-")
        memRow.cells.add Cell(text: "-")

    rows.add timeRow
    rows.add memRow

  renderTable(SiteDir / "benchmarks.svg", columns, rows)

writeFile(SiteDir / "summary.txt", report.join("\n") & "\n")

echo ""
echo "Wrote " & SiteDir & "/benchmarks.svg"
