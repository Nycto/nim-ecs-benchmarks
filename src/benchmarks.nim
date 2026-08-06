########################################################################################################################################
######################################################## CRUISE PROFILER ###############################################################
########################################################################################################################################

import times, math, algorithm, strutils, tables, unicode, std/monotimes

const
  SAMPLE* {.intDefine.} = 1000
  WARMUP* {.intDefine.} = 1
  ENTITY_COUNT* {.intDefine.} = 10_000
  SELECTION_THRESHOLD* = 0.1
  CAPACITY* = ENTITY_COUNT * 3

type
  Parameters* = object
    samples*: int
    warmup*: int
    maxTime*: float
    maxMem*: float

  Statistics* = object
    min*: float
    max*: float
    mean*: float
    median*: float
    stddev*: float
    q1*: float
    q3*: float
    iqr*: float

  Benchmark* = object
    name*: string
    params*: Parameters
    times*: seq[float]
    mems*: seq[float]
    timeStats*: Statistics
    memStats*: Statistics
    totalTime*: float
    totalMem*: float

  BenchmarkSuite* = object
    name*: string
    benchmarks*: seq[Benchmark]

  Comparison* = object
    baseline*: string
    candidate*: string
    timeRatio*: float      # candidate / baseline
    memRatio*: float
    timeImprovement*: float  # (baseline - candidate) / baseline
    memImprovement*: float
    isFaster*: bool
    usesLessMem*: bool



# ==================== Formatage ====================

proc prettyTime*(t: float): string =
  var fac = 1.0
  var suffix = "s"

  if t < 1e-6:
    fac = 1e9
    suffix = "ns"
  elif t < 1e-3:
    fac = 1e6
    suffix = "µs"
  elif t < 1:
    fac = 1e3
    suffix = "ms"

  let v = t * fac

  # Format avec précision adaptée
  result = v.formatFloat(ffDecimal, 2) & " " & suffix

proc prettyMem*(m: float): string =
  let sign = if m < 0: "-" else: ""
  let a = abs(m)
  if a < 1024:
    return sign & a.formatFloat(ffDecimal, 2) & " B "
  elif a < 1024 * 1024:
    return sign & (a / 1024).formatFloat(ffDecimal, 2) & " KB"
  else:
    return sign & (a / (1024 * 1024)).formatFloat(ffDecimal, 2) & " MB"

proc prettyPercent*(p: float): string =
  let sign = if p >= 0: "+" else: ""
  return sign & (p * 100).formatFloat(ffDecimal, 1) & "%"

# ==================== Calcul de statistiques ====================

proc calculateStatistics*(values: seq[float]): Statistics =
  if values.len == 0:
    return

  var sorted = values
  sorted.sort()

  result.min = sorted[0]
  result.max = sorted[^1]

  var sum = 0.0
  var variance = 0.0
  for v in sorted:
    sum += v

  result.mean = sum / sorted.len.float

  for v in sorted:
    let diff = v - result.mean
    variance += diff * diff

  if sorted.len > 1:
    result.stddev = sqrt(variance / (sorted.len - 1).float)

  let mid = sorted.len div 2
  if sorted.len mod 2 == 0:
    result.median = (sorted[mid - 1] + sorted[mid]) / 2.0
  else:
    result.median = sorted[mid]

  # Quartiles
  let q1Idx = sorted.len div 4
  let q3Idx = (3 * sorted.len) div 4
  result.q1 = sorted[q1Idx]
  result.q3 = sorted[q3Idx]
  result.iqr = result.q3 - result.q1

proc finalize*(b: var Benchmark) =
  b.timeStats = calculateStatistics(b.times)
  b.memStats = calculateStatistics(b.mems)

  b.totalTime = 0.0
  for t in b.times:
    b.totalTime += t

  b.totalMem = 0.0
  for m in b.mems:
    b.totalMem += m

# ==================== Affichage ====================

proc showSummary*(b: Benchmark) =
  echo "╭─ ", b.name, " (", b.params.samples, " samples)"
  echo "├─ Time  : ", prettyTime(b.timeStats.median),
       " (min: ", prettyTime(b.timeStats.min),
       ", max: ", prettyTime(b.timeStats.max), ")"
  echo "├─ Memory: ", prettyMem(b.memStats.median),
       " (min: ", prettyMem(b.memStats.min),
       ", max: ", prettyMem(b.memStats.max), ")"
  echo "╰─ Stddev: ±", prettyTime(b.timeStats.stddev)

proc showDetailed*(b: Benchmark) =
  echo "=" .repeat(70)
  echo "Benchmark: ", b.name
  echo "Samples: ", b.params.samples, " (warmup: ", b.params.warmup, ")"
  echo ""

  echo "Time Statistics:"
  echo "  Min     : ", prettyTime(b.timeStats.min)
  echo "  Q1      : ", prettyTime(b.timeStats.q1)
  echo "  Median  : ", prettyTime(b.timeStats.median)
  echo "  Mean    : ", prettyTime(b.timeStats.mean)
  echo "  Q3      : ", prettyTime(b.timeStats.q3)
  echo "  Max     : ", prettyTime(b.timeStats.max)
  echo "  Stddev  : ±", prettyTime(b.timeStats.stddev)
  echo "  IQR     : ", prettyTime(b.timeStats.iqr)
  echo ""

  echo "Memory Statistics:"
  echo "  Min     : ", prettyMem(b.memStats.min)
  echo "  Median  : ", prettyMem(b.memStats.median)
  echo "  Mean    : ", prettyMem(b.memStats.mean)
  echo "  Max     : ", prettyMem(b.memStats.max)
  echo "  Stddev  : ±", prettyMem(b.memStats.stddev)
  echo "=" .repeat(70)

proc notNaN(v:float):float =
  if v.isNaN or v.classify in {fcInf, fcNegInf}:
    return 0.0

  return v

proc compare*(baseline, candidate: Benchmark): Comparison =
  result.baseline = baseline.name
  result.candidate = candidate.name

  result.timeRatio = notNaN(candidate.timeStats.median / baseline.timeStats.median)
  result.memRatio = notNaN(candidate.memStats.median / baseline.memStats.median)

  result.timeImprovement = notNaN((baseline.timeStats.median - candidate.timeStats.median) / baseline.timeStats.median)
  result.memImprovement = notNaN((baseline.memStats.median - candidate.memStats.median) / baseline.memStats.median)

  result.isFaster = result.timeImprovement > 0
  result.usesLessMem = result.memImprovement > 0

proc showComparison*(cmp: Comparison) =
  echo ""
  echo "╔═", "═".repeat(66), "═╗"
  echo "║ ", "Comparison: ", cmp.baseline, " vs ", cmp.candidate, " ".repeat(max(0, 66 - 14 - cmp.baseline.len - cmp.candidate.len - 4)), "║"
  echo "╠═", "═".repeat(66), "═╣"

  # Time comparison
  let timeIcon = if cmp.isFaster: "✓" else: "✗"
  let timeColor = if cmp.isFaster: "" else: ""
  echo "║ Time   : ", timeIcon, " ",
       (if cmp.isFaster: "FASTER" else: "SLOWER"), " by ",
       prettyPercent(abs(cmp.timeImprovement)),
       " (", cmp.timeRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 48 - (if cmp.isFaster: 7 else: 6) - prettyPercent(abs(cmp.timeImprovement)).len - 3 - cmp.timeRatio.formatFloat(ffDecimal, 2).len)), "║"

  # Memory comparison
  let memIcon = if cmp.usesLessMem: "✓" else: "✗"
  echo "║ Memory : ", memIcon, " ",
       (if cmp.usesLessMem: "LESS" else: "MORE"), " by ",
       prettyPercent(abs(cmp.memImprovement)),
       " (", cmp.memRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 51 - (if cmp.usesLessMem: 4 else: 4) - prettyPercent(abs(cmp.memImprovement)).len - 3 - cmp.memRatio.formatFloat(ffDecimal, 2).len)), "║"

  echo "╚═", "═".repeat(66), "═╝"

var blackHole* {.volatile.}: uint64

proc blackBox*[T](value: T) {.noinline.} =
  ## Keeps `value` observable so the optimiser cannot delete the work that
  ## produced it. Under `-d:danger` a loop whose result is never read is dead code.
  ##
  ## Call this once per benchmark, after the sampling loop. The accumulator is
  ## then live across the whole benchmark, so the loop cannot be removed and no
  ## cost lands inside the timed region.
  var local = value
  let bytes = cast[ptr UncheckedArray[byte]](addr local)
  var acc = blackHole
  for i in 0 ..< sizeof(T):
    acc = acc xor (bytes[i].uint64 shl ((i and 7) * 8))
  blackHole = acc

proc initBenchmark*(benchmarkName: string, sample, warm: int): Benchmark =
  result.name = benchmarkName
  result.params = Parameters(samples: sample, warmup: warm)
  result.times = newSeqOfCap[float](sample)
  result.mems = newSeqOfCap[float](sample)

template measure*(bench: var Benchmark, memBaseline: int, code: untyped) =
  let t0 = getMonoTime()
  code
  let elapsed = (getMonoTime() - t0).inNanoseconds.float / 1e9

  bench.times.add(elapsed)
  bench.mems.add((getOccupiedMem() - memBaseline).float)

template benchmark*(benchmarkName: string, sample, code: untyped): untyped =
  benchmark(benchmarkName, sample, 1, code)

template benchmark*(benchmarkName: string, sample, warm, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0..<warm:
      code

    for i in 0..<sample:
      let memBaseline = getOccupiedMem()
      measure(bench, memBaseline):
        code

  finalize(bench)
  bench

template benchmarkWithSetup*(benchmarkName: string, sample,
                              setup, code: untyped): untyped =
  benchmarkWithSetup(benchmarkName, sample, 1, setup, code)

template benchmarkWithSetup*(benchmarkName: string, sample, warm,
                              setup, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0..<warm:
      setup
      code

    for i in 0..<sample:
      setup
      let memBaseline = getOccupiedMem()
      measure(bench, memBaseline):
        code

  finalize(bench)
  bench

proc initSuite*(name: string): BenchmarkSuite =
  result.name = name
  result.benchmarks = @[]

proc add*(suite: var BenchmarkSuite, bench: Benchmark) =
  suite.benchmarks.add(bench)

proc showSummary*(suite: BenchmarkSuite) =
  echo ""
  echo "╔═", "═".repeat(60), "═╗"
  echo "║ ", suite.name, " Operations", " ".repeat(max(0, 50 - suite.name.len)), "║"
  echo "╠═", "═".repeat(60), "═╣"

  for bench in suite.benchmarks:
    let timeStr = prettyTime(bench.timeStats.median).alignLeft(12)
    let memStr = prettyMem(bench.memStats.median).alignLeft(12)
    let nameStr = bench.name.alignLeft(30)
    echo "║ ", nameStr, " │ ", timeStr, " │ ", memStr, " ║"

  echo "╚═", "═".repeat(60), "═╝"

proc saveSummary*(suite: BenchmarkSuite, name: string) =
  var file = open(name & "_" & $ENTITY_COUNT & ".csv", fmWrite)
  defer: file.close()

  file.writeLine(suite.name & ",entity_count,time_median,mem_median,time_seconds,mem_bytes")

  for bench in suite.benchmarks:
    let mem = prettyMem(bench.memStats.median)
    let time = prettyTime(bench.timeStats.median)
    file.writeLine(
      bench.name & "," & $ENTITY_COUNT & "," & time & "," & mem & "," &
      bench.timeStats.median.formatFloat(ffScientific, 10) & "," &
      bench.memStats.median.formatFloat(ffScientific, 10)
    )
