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
  var world = newECSWorld(max_entities=ENTITY_COUNT)

  let posID = world.registerComponent(Position)
  let velID = world.registerComponent(Velocity)
  let accID = world.registerComponent(Acceleration)
  let hpID = world.registerComponent(Heal)

  return world

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

      var ents: seq[SparseHandle] = w.createSparseEntities(ENTITY_COUNT)

      for e in ents.mitems:
        for i in 0..<10:
          if rng.rand(1.0) < SELECTION_THRESHOLD:
            case i
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
              else: discard

      var posc = w.get(Position)
      let velc = w.get(Velocity)
    ),
    (
      for (sid, r) in w.sparseQuery(query(w, Position and Velocity)):
        let bid = posc.toSparse[sid]-1
        var x = addr posc.sparse[bid].data.x
        let dx = addr velc.sparse[bid].data.x
        var y = addr posc.sparse[bid].data.y
        let dy = addr velc.sparse[bid].data.y

        for i in r:
          x[i] += dx[i]
          y[i] += dy[i]
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
      var w = setupWorld()
      var ents:seq[SparseHandle]
      for i in 0..<ENTITY_COUNT:
        ents.add w.createSparseEntity(Position, Velocity)
      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        discard w.createSparseEntity(Position, Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Create sparse entities batch
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entities batch 1k",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(ENTITY_COUNT, Position, Velocity)

      for e in ents.mitems:
        w.deleteEntity(e)
    ),
    (discard w.createSparseEntities(ENTITY_COUNT, Position, Velocity))
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Delete sparse entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorld()
      var ents:seq[SparseHandle] = w.createSparseEntities(ENTITY_COUNT, Position, Velocity)
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
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT,Position)
      for e in ents.mitems:
        w.addComponent(e, Velocity)
      for e in ents.mitems:
        w.removeComponent(e, Velocity)),
    for e in ents.mitems:
      w.addComponent(e, Velocity)
  )

  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add component batch
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add component batch",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    w.addComponent(ents, Velocity)
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorld()
      var e = w.createSparseEntity(Position, Velocity)),
    for i in 0..<ENTITY_COUNT:
      w.removeComponent(e, Velocity)
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add + Remove (stress mask ops)
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var w = setupWorld()
      var ents = w.createSparseEntities(ENTITY_COUNT,Position)
      for e in ents.mitems:
        w.addComponent(e, Velocity)
      for e in ents.mitems:
        w.removeComponent(e, Velocity)),
    for e in ents.mitems:
      w.addComponent(e, Velocity)
      w.removeComponent(e, Velocity),
  )

  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var velc = w.get(Velocity)
      discard w.createSparseEntities(ENTITY_COUNT, Position, Velocity)),
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
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    (
      for e in ents:
        s += posc[e].x
    )
  )
  showDetailed(suite.benchmarks[^1])
  echo s

  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    Warmup,
    (
      var w = setupWorld()
      var posc = w.get(Position)
      var ents = w.createSparseEntities(ENTITY_COUNT, Position)),
    (
      for e in ents:
        posc[e] = Position()
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
