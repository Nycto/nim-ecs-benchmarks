## Renders the comparison table from the CSVs the benchmark suites produce.
##
## Pass CSV paths to compare a specific set of files; with no arguments every
## `*.csv` in the current directory is used.

import os, strutils, unicode, tables, sets, math, algorithm

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

type Cell = tuple[time, mem: string, seconds, bytes: float]

var comparisons = Table[string, Table[string, Cell]]()
var suiteOrder: seq[string] = @[]

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
  comparisons[metric] = Table[string, Cell]()

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

echo ""
echo rule("╔", "╗", "╦", "═", suiteOrder.len)
echo header(suiteOrder)
echo rule("╠", "╣", "╬", "═", suiteOrder.len)

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
    echo rule("╟", "╢", "╫", "─", suiteOrder.len)

  echo line(metric, "time", times)
  echo line("", "mem", mems)

echo rule("╚", "╝", "╩", "═", suiteOrder.len)
echo ""
echo winnerMark & " marks the best value on the line, time and memory judged separately."
