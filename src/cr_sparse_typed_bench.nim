import common, times, math, random#, nimprof
include ../libs/Cruise/src/ecs/table

# =========================
# Benchmark template
# =========================
import benchmarks, churn_common

let
  Pos = 0
  Vel = 1
  Acc = 2
  Health = 3

# ==============================
# Setup helpers
# ==============================

proc setupWorld(): ECSWorld =
  var world = newECSWorld()

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)
  let hpID = world.registerComponent(Heal)

  return world

proc setupWorldHetero(): ECSWorld =
  var world = newECSWorld()
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


# ==============================
# Benchmarks
# ==============================

# ---------------------------------
# Entity creation
# ---------------------------------

proc churnSpawn(w: var ECSWorld): SparseHandle =
  w.createSparseEntity(Position, Velocity)

proc churnDestroy(w: var ECSWorld; entity: var SparseHandle) =
  w.deleteEntity(entity)

proc newChurnWorld(churned: bool): ECSWorld =
  result = setupWorld()
  result.populateChurn(churned)

proc churnIterate(w: var ECSWorld) =
  var posc = w.get(Position)
  let velc = w.get(Velocity)

  for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
    let bid = posc.toSparse[sid]-1
    var x = addr posc.sparse[bid].data.x
    let dx = addr velc.sparse[bid].data.x
    var y = addr posc.sparse[bid].data.y
    let dy = addr velc.sparse[bid].data.y

    for i in r:
      x[i] += dx[i]
      y[i] += dy[i]

proc runSparseBenchmarks() =
  var suite = initSuite("Cruise Sparse")

  var ss = 0
  suite.add benchmarkWithSetup(
    "heterogeneous iter",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldHetero()
      var rng = initRand(42)

      var ents = w.createTSparseEntities(ENTITY_COUNT)

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
              of 0: discard w.addComponent(e, Position)
              of 1: discard w.addComponent(e, Velocity)
              of 2: discard w.addComponent(e, Acceleration)
              of 3: discard w.addComponent(e, Rotation)
              of 4: discard w.addComponent(e, Scale)
              of 5: discard w.addComponent(e, Mass)
              of 6: discard w.addComponent(e, Friction)
              of 7: discard w.addComponent(e, Bounce)
              of 8: discard w.addComponent(e, Lifetime)
              of 9: discard w.addComponent(e, Energy)
              else: continue

      var posc = w.get(Position)
      let velc = w.get(Velocity)

      for (bid, r) in w.denseQuery(query(w, Position and Velocity)):
        continue
    ),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let bid = posc.toSparse[sid]-1
        var posbx = addr posc.sparse[bid].data.x
        let velbx = addr velc.sparse[bid].data.x
        var posby = addr posc.sparse[bid].data.y
        let velby = addr velc.sparse[bid].data.y

        for i in r:
          posbx[i] += velbx[i]+1
          posby[i] += velby[i]+1
          ss += 1
    )
  )
  showDetailed(suite.benchmarks[^1])
  echo ss
  # ------------------------------
  # Create single sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()

      var ents:seq[TSHandle[maskOf(Position,Velocity)]]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createTSparseEntity(Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createTSparseEntity(Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "create entity batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()

      var ents = w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      discard w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
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

      var ents = w.createTSparseEntities(ENTITY_COUNT)

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
              of 0: discard w.addComponent(e, Position)
              of 1: discard w.addComponent(e, Velocity)
              of 2: discard w.addComponent(e, Acceleration)
              of 3: discard w.addComponent(e, Rotation)
              of 4: discard w.addComponent(e, Scale)
              of 5: discard w.addComponent(e, Mass)
              of 6: discard w.addComponent(e, Friction)
              of 7: discard w.addComponent(e, Bounce)
              of 8: discard w.addComponent(e, Lifetime)
              of 9: discard w.addComponent(e, Energy)
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
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
    )
    ,
    for e in ents.mitems:
      w.deleteEntity(e)
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
      var ents2: seq[TSHandle[maskOf(Position, Velocity, Acceleration)]]
      for e in ents:
        ents2.add w.addComponent(e, Acceleration)
      for e in ents2:
        discard w.removeComponent(e, Acceleration)
    ),
    (
      for e in ents:
        discard w.addComponent(e, Acceleration)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position)
      var ents2: seq[TSHandle[maskOf(Position, Velocity)]]

      for e in ents:
        ents2.add w.addComponent(e, Velocity)
    ),
    (
      for e in ents2:
        discard w.removeComponent(e, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
      var ents2: seq[TSHandle[maskOf(Position, Velocity, Acceleration)]]
      
      for e in ents:
        ents2.add w.addComponent(e, Acceleration)
      for e in ents2:
        discard w.removeComponent(e, Acceleration)
    ),
    (
      for e in ents:
        let re = w.addComponent(e, Acceleration)
        discard w.removeComponent(re, Acceleration)
    )
  )

  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorldNoEnt()
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position, Velocity)
      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let bid = posc.toSparse[sid]-1
        var posbx = addr posc.sparse[bid].data.x
        let velbx = addr velc.sparse[bid].data.x
        var posby = addr posc.sparse[bid].data.y
        let velby = addr velc.sparse[bid].data.y

        for i in r:
          posbx[i] += velbx[i]+1
          posby[i] += velby[i]+1
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
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position)
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
      var ents = w.createTSparseEntities(ENTITY_COUNT, Position)
      var posc = w.get(Position)
    ),
    (
      for e in ents:
        posc[e] = Position(x:s)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ==============================
  # Results
  # ==============================
  addChurnRows(suite, "Cruise Sparse")

  suite.showSummary()
  suite.saveSummary("cr_sparse")

# ==============================
# Entry point
# ==============================

when isMainModule:
  runSparseBenchmarks()
