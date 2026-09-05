include ../libs/Cruise/src/ecs/table

# =========================
# Benchmark template
# =========================
import benchmarks, churn_common
import random, common

# 1563
# =========================
# Components
# =========================

type
  Timer[T] = object
    remaining:T

proc newTimer[T](r:T):Timer[T] = Timer[T]()
proc newPosition(x,y:float32):Position = Position()
proc setComponent[T](blk: ptr T, i:uint, v:Position) =
  blk.data.x[i] = v.x*2
  blk.data.y[i] = v.y/2

# =========================
# World setup
# =========================

proc setupWorldHetero(): ECSWorld =
  var world = newECSWorld(max_entities=ENTITY_COUNT)
  discard world.registerComponent(Position)
  discard world.registerComponent(Velocity)
  discard world.registerComponent(Acceleration)
  discard world.registerComponent(Rotation)
  discard world.registerComponent(Scale)
  discard world.registerComponent(Mass)
  discard world.registerComponent(Friction)
  discard world.registerComponent(Bounce)
  discard world.registerComponent(Lifetime)
  discard world.registerComponent(Energy)
  return world

# =========================
# Benchmarks
# =========================

proc setupWorldNoEnt(): ECSWorld =
  var world = newECSWorld(max_entities=ENTITY_COUNT)

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)

  return world


# ---------------------------------
# Entity creation
# ---------------------------------

proc churnSpawn(w: var ECSWorld): DenseHandle =
  w.createEntity(Position, Velocity)

proc churnDestroy(w: var ECSWorld; entity: var DenseHandle) =
  w.deleteEntity(entity)

proc newChurnWorld(churned: bool): ECSWorld =
  result = setupWorldNoEnt()
  result.populateChurn(churned)

proc churnIterate(w: var ECSWorld) =
  var posc = w.get(Position)
  let velc = w.get(Velocity)

  for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
    var x = addr posc.blocks[bid].data.x
    let dx = addr velc.blocks[bid].data.x
    var y = addr posc.blocks[bid].data.y
    let dy = addr velc.blocks[bid].data.y

    for i in r:
      x[i] += dx[i]
      y[i] += dy[i]

proc runDenseBenchmarks() =
  var suite = initSuite("Cruise Dense")

  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createEntity(Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createEntity(Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "create entity batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      discard w.createEntities(ENTITY_COUNT, Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "rand create ents",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldHetero()
      var rng = initRand(42)

      var ents: seq[DenseHandle] = w.createEntities(ENTITY_COUNT)

      let optional = [
        Position.toComponentId,
        Velocity.toComponentId,
        Acceleration.toComponentId,
        Rotation.toComponentId,
        Scale.toComponentId,
        Mass.toComponentId,
        Friction.toComponentId,
        Bounce.toComponentId,
        Lifetime.toComponentId,
        Energy.toComponentId,
      ]
    ),
    (
      for e in ents:
        for compId in optional:
          if rng.rand(1.0) < SELECTION_THRESHOLD:
            case compId:
              of 0: w.addComponent(e, Position)
              of 1: w.addComponent(e, Velocity)
              of 2: w.addComponent(e, Acceleration)
              of 3: w.addComponent(e, Rotation)
              of 4: w.addComponent(e, Scale)
              of 5: w.addComponent(e, Mass)
              of 6: w.addComponent(e, Friction)
              of 7: w.addComponent(e, Bounce)
              of 8: w.addComponent(e, Lifetime)
              of 9: w.addComponent(e, Energy)
              else: continue
    )
  )
  # ------------------------------
  # Delete dense entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    Sample,
    Warmup,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    )
    ,
    for e in ents.mitems:
      w.deleteEntity(e)
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "query creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    ),
    (
      discard query(w, Position and Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "dense query creation",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
    ),
    (
      for (_,_) in w.denseQuery(query(w, Position and Velocity)):
        continue
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      let q2 = w.denseQueryCache(query(w, Position and Velocity))
      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        var x = addr posc.blocks[bid].data.x
        let dx = addr velc.blocks[bid].data.x
        var y = addr posc.blocks[bid].data.y
        let dy = addr velc.blocks[bid].data.y

        for i in r:
          x[i] += dx[i]
          y[i] += dy[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

  var ss = 0
  suite.add benchmarkWithSetup(
    "heterogeneous iter",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldHetero()
      var rng = initRand(42)

      var ents: seq[DenseHandle] = w.createEntities(ENTITY_COUNT)

      let optional = [
        Position.toComponentId,
        Velocity.toComponentId,
        Acceleration.toComponentId,
        Rotation.toComponentId,
        Scale.toComponentId,
        Mass.toComponentId,
        Friction.toComponentId,
        Bounce.toComponentId,
        Lifetime.toComponentId,
        Energy.toComponentId,
      ]

      for e in ents:
        for compId in optional:
          if rng.rand(1.0) < SELECTION_THRESHOLD:
            case compId:
              of 0: w.addComponent(e, Position)
              of 1: w.addComponent(e, Velocity)
              of 2: w.addComponent(e, Acceleration)
              of 3: w.addComponent(e, Rotation)
              of 4: w.addComponent(e, Scale)
              of 5: w.addComponent(e, Mass)
              of 6: w.addComponent(e, Friction)
              of 7: w.addComponent(e, Bounce)
              of 8: w.addComponent(e, Lifetime)
              of 9: w.addComponent(e, Energy)
              else: continue

      var posc = w.get(Position)
      let velc = w.get(Velocity)

      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        continue
    ),
    (
      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):

        var x = addr posc.blocks[bid].data.x
        let dx = addr velc.blocks[bid].data.x
        var y = addr posc.blocks[bid].data.y
        let dy = addr velc.blocks[bid].data.y

        for i in r:
          x[i] += dx[i]
          y[i] += dy[i]
    )
  )
  showDetailed(suite.benchmarks[^1])

  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position)
      var posc = w.get(Position)

    ),
    (
      for e in ents:
        s += posc[e].x
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position)
      var posc = w.get(Position)
    ),
    (
      for e in ents:
        posc[e] = Position(x:s)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)
      
      for e in ents:
        w.addComponent(e, Acceleration)
      for e in ents:
        w.removeComponent(e, Acceleration)
    ),
    (
      for e in ents:
        w.addComponent(e, Acceleration)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)

      for e in ents:
        w.addComponent(e, Velocity)
    ),
    (
      for e in ents:
        w.removeComponent(e, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)

      for e in ents:
        w.addComponent(e, Acceleration)
      for e in ents:
        w.removeComponent(e, Acceleration)
    ),
    (
      for e in ents:
        w.addComponent(e, Acceleration)
        w.removeComponent(e, Acceleration)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "migrate_dense_entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity)])
      var archDest = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity), toComponentId(Acceleration)])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)

      for e in ents:
        migrateEntity(w, e, archDest)
      for e in ents:
        migrateEntity(w, e, archBase)
    ),
    (
      for e in ents:
        migrateEntity(w, e, archDest)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "migrate dense entity batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var archBase = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity)])
      var archDest = w.archGraph.findArchetype([toComponentId(Position), toComponentId(Velocity), toComponentId(Acceleration)])
      var ents:seq[DenseHandle] = w.createEntities(ENTITY_COUNT, Position, Velocity)

      migrateEntity(w, ents, archDest)
      migrateEntity(w, ents, archBase)
    ),
    (
      migrateEntity(w, ents, archDest)
    )
  )
  showDetailed(suite.benchmarks[^1])
  addChurnRows(suite, "Cruise Dense")

  suite.showSummary()
  suite.saveSummary("cr_dense")

runDenseBenchmarks()
