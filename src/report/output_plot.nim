import std/[tables, algorithm, math, sequtils, strutils, strformat], ggplotnim, ginger/backends, parser
import ginger except Scale

type ExtractCallback = proc (m: Measurement): tuple[value, ratio: float]

const
  palette = [
   "#2A9D8F", "#E76F51", "#F4A261", "#264653", "#E9C46A", "#A8DADC", "#457B9D", "#1D3557"
  ]

  clippedKey = "(off scale)" ## Fill applied to bars that run off the top of a panel
  clippedFill = "#cccccc"

  micros = 1e6
  mebibytes = 1024.0 * 1024.0

  clipRatio = 100.0  ## How much slower than the winner a suite has to be to get clipped
  clipHeadroom = 1.2 ## How far past the tallest legible bar the axis is allowed to run

  columns = 2
  panelWidth = 560
  panelHeight = 380

proc colors(report: Report): Table[string, Color] =
  var names = report.suiteNames
  names.sort()
  for index, name in names:
    result[name] = parseHtmlHex(palette[index mod palette.len])
  result[clippedKey] = parseHtmlHex(clippedFill)

proc panel(report: Report, metric, label: string, entityCount: int, extract: ExtractCallback): GgPlot =
  ## One metric's bars
  var suites, labels, fills: seq[string]
  var values: seq[float]
  var cap = 0.0

  let key = (metric, entityCount)
  for suite in report.suites:
    if key notin suite.measurements:
      continue

    let (measured, ratio) = extract(suite.measurements[key])
    if measured == Inf:
      continue

    suites.add suite.name
    values.add measured

    if ratio > clipRatio:
      labels.add $ratio.round.int & "x"
      fills.add clippedKey
    else:
      labels.add ""
      fills.add suite.name
      cap = max(cap, measured)

  let clipped = cap > 0 and clippedKey in fills

  # Labels sit just above where the tallest legible bar can reach, which puts
  # them inside the clipped bars and out of everyone else's way
  let df = toDf({
    "suite": suites,
    "value": values,
    "fill": fills,
    "label": labels,
    "labelY": repeat(cap * 1.05, suites.len)
  })

  result = ggplot(df, aes(x = "suite", y = "value", fill = "fill")) +
    geom_bar(stat = "identity", position = "identity") +
    scale_fill_manual(report.colors) +
    ggtitle(fmt"{metric} at {entityCount} entities (lower is better)") +
    xlab(" ", rotate = -30.0, alignTo = "right") +
    ylab(label) +
    backgroundColor(white) +
    gridLines(color = grey92) +
    hideLegend()

  if clipped:
    result = result +
      geom_text(
        aes(x = "suite", y = "labelY", text = "label"),
        font = font(11.0, color = white, bold = true)
      ) +
      ylim(0.0, cap * clipHeadroom, outsideRange = "clip")

proc savePlot(report: Report, path, label: string, entityCount: int, extract: ExtractCallback) =
  let rows = (metricOrder.len + columns - 1) div columns

  let texOptions = toTeXOptions(false, false, false, "", "", "", "htbp")
  let fType = parseFilename(path)
  let backend = fType.toBackend(texOptions)

  var image = initViewport(
    wImg = float(panelWidth * columns),
    hImg = float(panelHeight * rows),
    backend = backend,
    fType = fType
  )
  image.layout(cols = columns, rows = rows)

  for index, metric in metricOrder:
    var plot = report.panel(metric, label, entityCount, extract)
    plot.backend = backend
    plot.fType = fType

    let drawn = plot.ggcreate(width = panelWidth, height = panelHeight)
    image.embedAt(index, drawn.view)

  image.draw(path, texOptions)

proc saveTimePlot*(report: Report, path: string) =
  for entityCount in report.entityCounts:
    report.savePlot(path % $entityCount, "median time (µs)", entityCount, proc (m: Measurement): (float, float) =
      (m.seconds * micros, m.timeRatio)
    )
