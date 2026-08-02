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

# Accumulator that outlives the benchmark so reads can't be optimised away
var readSink = 0'f32

# Handles captured while the world is built, so the random access benchmarks can
# index by entity the way every other suite does. The alternative — walking a
# `FullQuery` to discover the ids — folds a sequential scan into a benchmark that
# is supposed to measure a single indexed fetch.
var benchEntities: seq[EntityId]

# =========================
# Systems
# =========================
#
# Spawning happens in `startupSys` systems, which Necsus runs while the app
# state is being initialised. That keeps world construction and entity creation
# inside the untimed setup block, leaving `tick()` to run only the loop systems
# that are actually under test.

proc spawnPosVel(spawn: Spawn[(Position, Velocity)]) {.startupSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

proc spawnTrackedPos(spawn: FullSpawn[(Position, )]) {.startupSys.} =
  benchEntities.setLen(0)
  for _ in 0..<ENTITY_COUNT:
    benchEntities.add spawn.with(Position(x: 1.0, y: 1.0))

proc spawnPosVelAccel(spawn: Spawn[(Position, Velocity, Acceleration)]) {.startupSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(
      Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0), Acceleration(x: 1.0, y: 1.0)
    )

proc createEntities(spawn: Spawn[(Position, Velocity)]) {.loopSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

proc move(entities: Query[(ptr Position, Velocity)]) {.loopSys.} =
  for (pos, vel) in entities:
    pos.x += vel.x
    pos.y += vel.y

proc deleteEntities(query: FullQuery[(Position, )], delete: Delete) {.loopSys.} =
  for eid, comp in query:
    delete(eid)

proc readSystem(lookup: Lookup[(Position, )]) {.loopSys.} =
  for eid in benchEntities:
    let found = lookup(eid)
    if found.isSome:
      readSink += found.get()[0].x

proc writeSystem(lookup: Lookup[(ptr Position, )]) {.loopSys.} =
  for eid in benchEntities:
    let found = lookup(eid)
    if found.isSome:
      found.get()[0][] = Position(x: readSink, y: readSink)

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

# =========================
# Apps
# =========================
#
# These procs are never called directly. The `necsus` macro also generates an
# `initXxx()` proc returning the app state, plus a `tick()` on that state. The
# benchmarks below drive those manually so that only one tick is measured.

proc appCreate() {.necsus([~createEntities], newNecsusConf(entitySize = 100_000)).}
proc appIter() {.necsus([~spawnPosVel, ~move], newNecsusConf(entitySize = 100_000)).}
proc appDelete() {.necsus([~spawnPosVel, ~deleteEntities], newNecsusConf(entitySize = 100_000)).}
proc appRead() {.necsus([~spawnTrackedPos, ~readSystem], newNecsusConf(entitySize = 100_000)).}
proc appWrite() {.necsus([~spawnTrackedPos, ~writeSystem], newNecsusConf(entitySize = 100_000)).}
proc appAddComp() {.necsus([~spawnPosVel, ~addComponent], newNecsusConf(entitySize = 100_000)).}
proc appRemoveComp() {.necsus([~spawnPosVelAccel, ~removeComponent], newNecsusConf(entitySize = 100_000)).}
proc appAddRemoveComp() {.necsus([~spawnPosVel, ~addRemoveComponent], newNecsusConf(entitySize = 100_000)).}

# =========================
# Benchmarks
# =========================

proc runNecsusBenchmarks() =
  var suite = initSuite("Necsus")

  # 1. Create
  # A fresh, empty app per sample; the tick spawns ENTITY_COUNT entities.
  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var app = initAppCreate()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 2. Iterate
  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var app = initAppIter()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 3. Delete
  suite.add benchmarkWithSetup(
    "delete entity",
    SAMPLE,
    WARMUP,
    (
      var app = initAppDelete()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 4. Read
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (
      var app = initAppRead()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 5. Write
  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    WARMUP,
    (
      var app = initAppWrite()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 6. Add component
  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (
      var app = initAppAddComp()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 7. Remove component
  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var app = initAppRemoveComp()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # 8. Add + Remove component
  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var app = initAppAddRemoveComp()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  echo readSink

  suite.showSummary()
  suite.saveSummary("necsus")

if isMainModule:
  runNecsusBenchmarks()
