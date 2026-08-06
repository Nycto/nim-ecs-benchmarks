import std/[strutils, tables, sets, algorithm]

const architectures = {
  "Cruise Dense": "Archetype",
  "Cruise Sparse": "Sparse set",
  "Easyess": "Bitset/table",
  "MiniECS": "Sparse set",
  "Necsus": "Framework",
  "Pirata": "Preallocated",
  "Polymorph": "Generative",
  "Vecs": "Archetype",
}.toTable

const metricOrder* = [
  "iteration",
  "heterogeneous iter",
  "pristine iter",
  "churn iter",
  "create entity",
  "delete entity",
  "add component",
  "remove component",
  "add remove component",
  "read",
  "write"
]

type
  MetricKey* = tuple[metric: string, entityCount: int]

  Measurement* = object
    entityCount*: int ## The number of entities in the benchmark
    time*: string     ## Median time, formatted for display
    mem*: string      ## Median memory, formatted for display
    seconds*: float   ## Median time, for comparing against other suites
    bytes*: float     ## Median memory, for comparing against other suites
    timeWinner*: bool ## Whether this is the fastest time on its row
    memWinner*: bool  ## Whether this is the smallest memory on its row
    timeRatio*: float ## How many times slower this is than the fastest time on its row
    memRatio*: float  ## How many times larger this is than the smallest memory on its row

  Suite* = ref object
    name*: string
    architecture*: string ## How the library is built, where it is known
    measurements*: Table[MetricKey, Measurement]

  Report* = ref object
    entityCountCache: seq[int]
    suites*: seq[Suite]

proc toNumber(value: string): float =
  try:
    return parseFloat(value.strip())
  except ValueError:
    return Inf

proc parseSuite*(csv: string): Suite =
  let lines = csv.splitLines()

  result = Suite(name: lines[0].split(',')[0].strip())
  result.architecture = architectures.getOrDefault(result.name, "")

  for line in lines[1..^1]:
    let parts = line.split(',')
    if parts.len < 6:
      continue

    let metric = parts[0].strip()
    if metric notin metricOrder:
      continue

    let entityCount = parts[1].strip().parseInt()
    let bytes = parts[5].toNumber

    result.measurements[(metric, entityCount)] = Measurement(
      entityCount: entityCount,
      time: parts[2].strip(),
      mem: if bytes > 0: parts[3].strip() else: "-",
      seconds: parts[4].toNumber,
      bytes: bytes
    )

proc best(values: openArray[float]): float =
  result = Inf
  for value in values:
    if value > 0 and value < result:
      result = value

proc ratio(value, best: float): float =
  ## How many times bigger a value is than the best value, or 0 when unknown
  if best < Inf and value > 0 and value < Inf:
    value / best
  else:
    0.0

iterator entityCounts*(report: Report): int =
  if report.entityCountCache.len == 0:
    var seen = initHashSet[int]()
    for suite in report.suites:
      for key in suite.measurements.keys:
        if key.entityCount notin seen:
          seen.incl(key.entityCount)
          report.entityCountCache.add(key.entityCount)
    report.entityCountCache.sort()
  for count in report.entityCountCache:
    yield count

proc markWinners(report: Report) =
  for entityCount in entityCounts(report):
    for metric in metricOrder:
      var seconds, bytes: seq[float]

      let metricKey = (metric, entityCount)

      for suite in report.suites:
        if suite.measurements.hasKey(metricKey):
          seconds.add(suite.measurements[metricKey].seconds)
          bytes.add(suite.measurements[metricKey].bytes)

      let bestTime = best(seconds)
      let bestMem = best(bytes)

      for suite in report.suites.mitems:
        if suite.measurements.hasKey(metricKey):
          template measured: Measurement = suite.measurements[metricKey]
          measured.timeRatio = ratio(measured.seconds, bestTime)
          measured.memRatio = ratio(measured.bytes, bestMem)

          if seconds.len >= 2:
            measured.timeWinner = bestTime < Inf and measured.seconds == bestTime
            measured.memWinner = bestMem < Inf and measured.bytes == bestMem

proc parseFiles*(paths: openArray[string]): Report =
  result = Report()

  var suites = initTable[string, Suite]()
  for path in paths:
    let suite = parseSuite(readFile(path))
    assert(suite.name.len > 0)

    if suite.name notin suites:
      result.suites.add(suite)
      suites[suite.name] = suite
    else:
      for key, measures in suite.measurements:
        suites[suite.name].measurements[key] = measures

  result.markWinners()

proc suiteNames*(report: Report): seq[string] =
  for suite in report.suites:
    result.add(suite.name)

iterator metrics*(report: Report): string =
  for metric in metricOrder:
    yield metric
