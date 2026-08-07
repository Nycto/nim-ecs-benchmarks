import std/[tables, algorithm, math, sequtils, strutils, strformat], ggplotnim, ginger/backends, parser
import ginger except Scale

type ExtractCallback = proc (m: Measurement): tuple[value, ratio: float]

const
  palette = [
   "#2A9D8F", "#E76F51", "#F4A261", "#264653", "#E9C46A", "#A8DADC", "#457B9D", "#1D3557"
  ]

  micros = 1e6
  mebibytes = 1024.0 * 1024.0

  groupWidth = 0.82 ## How much of each suite's slot its group of bars takes up
  headroom = 1.05   ## How far past the tallest bar the y axis runs
  clipRatio = 30.0  ## How many times slower than the winner a panel is allowed to show
  clipHeight = 1.02 ## How far up the panel a clipped bar is drawn
  clipFill = "#cccccc" ## Fill for bars that run off the top of a panel

  fillColumn = "Entity Count" ## Doubles as the legend title

  columns = 2
  panelWidth = 560
  panelHeight = 380

proc entityCountsSeq(report: Report): seq[int] =
  for entityCount in report.entityCounts:
    result.add entityCount

proc colors(report: Report): Table[int, Color] =
  ## Bars are grouped by suite and filled by entity count. Keyed by the raw count
  ## rather than a string so the legend sorts numerically and renders unquoted.
  for index, entityCount in report.entityCountsSeq:
    result[entityCount] = parseHtmlHex(palette[index mod palette.len])

proc ratioLabel(ratio: float): string =
  ratio.formatFloat(ffDecimal, precision = 1) & "x"

proc panel(report: Report, metric, label: string, extract: ExtractCallback): GgPlot =
  ## One metric's bars, grouped by suite and entity count.
  var names = report.suiteNames
  names.sort()

  var suiteIndexes: Table[string, int]
  for index, name in names:
    suiteIndexes[name] = index

  let counts = report.entityCountsSeq
  let barWidth = groupWidth / counts.len.float

  var xs, ratios: seq[float]
  var fills: seq[int]

  for suite in report.suites:
    for countIndex, entityCount in counts:
      let key = (metric, entityCount)
      if key notin suite.measurements:
        continue

      # A ratio of zero means the row had nothing to compare against
      let (_, ratio) = extract(suite.measurements[key])
      if ratio <= 0 or ratio == Inf:
        continue

      # Left edge of this bar: centre the group of bars on the suite's index, which
      # leaves the rest of the slot as a gap between neighbouring groups
      let left = suiteIndexes[suite.name].float - groupWidth / 2.0 +
        countIndex.float * barWidth

      xs.add left
      ratios.add ratio
      fills.add entityCount

  # Bars grow from zero, with 1.0x marking the fastest suite for the row
  let topY = if ratios.len > 0: min(max(ratios) * headroom, clipRatio) else: 1.0

  # Anything past the cap is drawn short of the top of the panel in grey, so one very
  # slow suite can't flatten the rest of the panel. Those bars are held in their own
  # frame because their fill has to ignore the entity count scale.
  var barXs, barHeights, clipXs, clipHeights: seq[float]
  var barFills, clipFills: seq[int]
  var labelYs: seq[float]
  var labels: seq[string]

  for index, ratio in ratios:
    if ratio > topY:
      clipXs.add xs[index]
      clipHeights.add topY * clipHeight
      clipFills.add fills[index]
      labelYs.add topY * (clipHeight + 1.0) / 2.0
      labels.add ratio.ratioLabel
    else:
      barXs.add xs[index]
      barHeights.add ratio
      barFills.add fills[index]

  proc frame(xs, heights: seq[float], fills: seq[int]): DataFrame =
    toDf({
      "x": xs,
      "base": newSeqWith(xs.len, 0.0),
      "width": newSeqWith(xs.len, barWidth),
      "height": heights,
      fillColumn: fills
    })

  let df = frame(barXs, barHeights, barFills)
  let clippedDf = frame(clipXs, clipHeights, clipFills)

  # Ticks sit at the centre of each group, one per suite
  var xBreaks: seq[float]
  for index in 0 ..< names.len:
    xBreaks.add index.float

  proc suiteLabel(x: float): string =
    let index = x.round.int
    if index >= 0 and index < names.len and abs(x - index.float) < 1e-6:
      names[index]
    else:
      ""

  result = ggplot(df, aes(x = "x", y = "base", width = "width", height = "height", fill = fillColumn)) +
    geom_tile() +
    scale_fill_manual(report.colors) +
    scale_x_continuous(breaks = xBreaks, labels = suiteLabel) +
    scale_y_continuous(labels = ratioLabel) +
    xlim(-0.5, names.len.float - 0.5) +
    ylim(0.0, topY) +
    ggtitle(fmt"{metric} (lower is better)") +
    xlab(" ", rotate = -30.0, alignTo = "right") +
    ylab(label) +
    backgroundColor(white) +
    gridLines(color = grey92)

  # Make any clipped bars grey
  if clippedDf.len > 0:
    result = result +
      geom_tile(
        data = clippedDf,
        color = parseHtmlHex(clipFill),
        fillColor = parseHtmlHex(clipFill)
      )

proc savePlot(report: Report, path, label: string, extract: ExtractCallback) =
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
    var plot = report.panel(metric, label, extract)
    plot.backend = backend
    plot.fType = fType

    let drawn = plot.ggcreate(width = panelWidth, height = panelHeight)
    image.embedAt(index, drawn.view)

  image.draw(path, texOptions)

proc saveTimePlot*(report: Report, path: string) =
  report.savePlot(path, "vs fastest", proc (m: Measurement): (float, float) =
    (m.seconds * micros, m.timeRatio)
  )
