import times, math, tables, options, random, common
import ../libs/Necsus/src/necsus

# =========================
# Benchmark template
# =========================
import benchmarks, churn_common

# =========================
# Components
# =========================
#
# Necsus keeps its own copies of the optional components so they can be marked
# `{.accessory.}`, which the heterogeneous benchmark relies on.

type
  Tag = object
  Rotation {.accessory.} = object
    angle: float32
  Scale {.accessory.} = object
    sx, sy: float32
  Mass {.accessory.} = object
    value: float32
  Force {.accessory.} = object
    fx, fy: float32
  Torque {.accessory.} = object
    value: float32
  Energy {.accessory.} = object
    value: float32
  Friction {.accessory.} = object
    coef: float32

var rng = initRand(42)

# Accumulator that outlives the benchmark so reads can't be optimised away
var readSink = 0'f32
var iterCount = 0

# Handles captured while the world is built, so the random access benchmarks can
# index by entity the way every other suite does
var benchEntities: seq[EntityId]

# =========================
# Systems
# =========================

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

proc spawnHetero(
  spawn: FullSpawn[(Tag, )],
  addPos: Attach[(Position, )],
  addVel: Attach[(Velocity, )],
  addAccel: Attach[(Acceleration, )],
  addRot: Attach[(Rotation, )],
  addScale: Attach[(Scale, )],
  addMass: Attach[(Mass, )],
  addForce: Attach[(Force, )],
  addTorque: Attach[(Torque, )],
  addEnergy: Attach[(Energy, )],
  addFriction: Attach[(Friction, )]
) {.startupSys.} =
  for _ in 0..<ENTITY_COUNT:
    let eid = spawn.with(Tag())
    for i in 0..<10:
      if rng.rand(1.0) < SELECTION_THRESHOLD:
        case i:
        of 0: addPos(eid, (Position(x: 1.0, y: 1.0), ))
        of 1: addVel(eid, (Velocity(x: 1.0, y: 1.0), ))
        of 2: addAccel(eid, (Acceleration(x: 1.0, y: 1.0), ))
        of 3: addRot(eid, (Rotation(angle: 0.5), ))
        of 4: addScale(eid, (Scale(sx: 1.0, sy: 1.0), ))
        of 5: addMass(eid, (Mass(value: 1.0), ))
        of 6: addForce(eid, (Force(fx: 1.0, fy: 1.0), ))
        of 7: addTorque(eid, (Torque(value: 1.0), ))
        of 8: addEnergy(eid, (Energy(value: 1.0), ))
        of 9: addFriction(eid, (Friction(coef: 0.5), ))
        else: continue

proc createEntities(spawn: Spawn[(Position, Velocity)]) {.loopSys.} =
  for _ in 0..<ENTITY_COUNT:
    spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

var churnThisApp = false

proc spawnChurnWorld(
  spawn: FullSpawn[(Position, Velocity)], delete: Delete
) {.startupSys.} =
  var handles = newSeq[EntityId](ENTITY_COUNT)
  for i in 0 ..< ENTITY_COUNT:
    handles[i] = spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

  if churnThisApp:
    for round in churnSchedule:
      for idx in round:
        delete(handles[idx])
      for idx in round:
        handles[idx] = spawn.with(Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0))

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

proc appCreate() {.necsus([~createEntities], newNecsusConf(entitySize = CAPACITY)).}
proc appIter() {.necsus([~spawnPosVel, ~move], newNecsusConf(entitySize = CAPACITY)).}
proc appDelete() {.necsus([~spawnPosVel, ~deleteEntities], newNecsusConf(entitySize = CAPACITY)).}
proc appRead() {.necsus([~spawnTrackedPos, ~readSystem], newNecsusConf(entitySize = CAPACITY)).}
proc appWrite() {.necsus([~spawnTrackedPos, ~writeSystem], newNecsusConf(entitySize = CAPACITY)).}
proc appAddComp() {.necsus([~spawnPosVel, ~addComponent], newNecsusConf(entitySize = CAPACITY)).}
proc appRemoveComp() {.necsus([~spawnPosVelAccel, ~removeComponent], newNecsusConf(entitySize = CAPACITY)).}
proc appAddRemoveComp() {.necsus([~spawnPosVel, ~addRemoveComponent], newNecsusConf(entitySize = CAPACITY)).}
proc appHetero() {.necsus([~spawnHetero, ~move], newNecsusConf(entitySize = CAPACITY)).}

proc appChurn() {.necsus(
  [~spawnChurnWorld, ~move],
  newNecsusConf(ChurnCapacity, ENTITY_COUNT, eagerAlloc = true)
).}

proc newChurnWorld(churned: bool): auto =
  churnThisApp = churned
  initAppChurn()

proc churnIterate[T](app: var T) =
  app.tick()

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

  # 9. Heterogeneous iteration
  suite.add benchmarkWithSetup(
    "heterogeneous iter",
    SAMPLE,
    WARMUP,
    (
      var app = initAppHetero()
    ),
    (
      app.tick()
    )
  )
  showDetailed(suite.benchmarks[^1])

  addChurnRows(suite, "Necsus")
  blackBox(readSink)

  suite.showSummary()
  suite.saveSummary("necsus")

if isMainModule:
  runNecsusBenchmarks()
