import times, math, tables, options
import ../libs/Necsus/src/necsus

# =========================
# Benchmark template
# =========================
include "benchmarks.nim"

const SAMPLE = 1000
const WARMUP = 1
const ENTITY_COUNT = 10000

# =========================
# Components
# =========================

type
  Position = object
    x, y: float32
  Velocity = object
    x, y: float32
  Acceleration = object
    x, y: float32

# =========================
# Systems
# =========================

proc move(dt: TimeDelta, entities: Query[(ptr Position, Velocity)]) {.loopSys.} =
  for (pos, vel) in entities:
    pos.x += vel.x
    pos.y += vel.y

proc createEntities(spawn: Spawn[(Position, Velocity)]) {.startupSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

proc deleteEntities(query: FullQuery[(Position, )], delete: Delete) {.loopSys.} =
  for eid, comp in query:
    delete(eid)

proc createAccelEntities(spawn: Spawn[(Position, Velocity, Acceleration)]) {.startupSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0), Acceleration(x: 1.0, y: 1.0))

proc addComponent(
  query: FullQuery[(Position, Not[Acceleration])],
  attach: Attach[(Acceleration, )]
) {.loopSys.} =
  for eid, _ in query:
    eid.attach((Acceleration(x: 1.0, y: 1.0), ))

proc removeComponent(
  query: FullQuery[(Position, Acceleration)],
  detach: Detach[(Acceleration, )]
) {.loopSys.} =
  for eid, _ in query:
    detach(eid)

proc addRemoveComponent(
  query: FullQuery[(Position, Not[Acceleration])],
  attach: Attach[(Acceleration, )],
  detach: Detach[(Acceleration, )]
) {.loopSys.} =
  for eid, _ in query:
    eid.attach((Acceleration(x: 1.0, y: 1.0), ))
    detach(eid)

proc exitAfterOne(exit: Shared[NecsusRun]) {.loopSys.} =
  exit := ExitLoop

# =========================
# Apps
# =========================

proc appCreate() {.necsus([~createEntities, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}
proc appIter() {.necsus([~createEntities, ~move, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}
proc appDelete() {.necsus([~createEntities, ~deleteEntities, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}
proc appAddComp() {.necsus([~createEntities, ~addComponent, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}
proc appRemoveComp() {.necsus([~createAccelEntities, ~removeComponent, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}
proc appAddRemoveComp() {.necsus([~createEntities, ~addRemoveComponent, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}

proc readSystem(query: FullQuery[(Position, )], lookup: Lookup[(Position, )]) {.loopSys.} =
  var total = 0'f32
  for eid, _ in query:
     if lookup(eid).isSome:
       total += lookup(eid).get()[0].x

proc appRead() {.necsus([~createEntities, ~readSystem, ~exitAfterOne], newNecsusConf(entitySize = 100_000)).}

# =========================
# Benchmarks
# =========================

proc runNecsusBenchmarks() =
  var suite = initSuite("Necsus")

  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appCreate()
    )
  )
  showDetailed(suite.benchmarks[0])

  # 2. Iterate
  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appIter()
    )
  )
  showDetailed(suite.benchmarks[1])

  # 3. Delete
  suite.add benchmarkWithSetup(
    "delete entity",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appDelete()
    )
  )
  showDetailed(suite.benchmarks[2])

  # 4. Read
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appRead()
    )
  )
  showDetailed(suite.benchmarks[3])
  # Actually, the above necsus benchmarking might be very noisy due to setup costs.
  # But necsus IS the app.

  # 5. Add component
  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appAddComp()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 6. Remove component
  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appRemoveComp()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 7. Add + Remove component
  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (discard),
    (
      appAddRemoveComp()
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.showSummary()
  suite.saveSummary("necsus")

if isMainModule:
  runNecsusBenchmarks()
