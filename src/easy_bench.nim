import times, math, tables, random
import ../libs/easyess/src/easyess

# =========================
# Benchmark template
# =========================
import benchmarks

# =========================
# Components
# =========================

comp:
  type
    Position = object
      x, y: float32

    Velocity = object
      x, y: float32

    Acceleration = object
      x, y: float32

    Tag = object

    Health = object
      hp: int

    Rotation = object
      angle: float32
    Scale = object
      sx, sy: float32
    Mass = object
      value: float32
    Force = object
      fx, fy: float32
    Torque = object
      value: float32
    Energy = object
      value: float32
    Friction = object
      coef: float32

sys [Position, Velocity], "movementHetero":
  proc moveHeteroSystem(item: Item) =
    position.x += velocity.x
    position.y += velocity.y

# =========================
# Systems
# =========================

sys [Position, Velocity], "movement":
  proc moveSystem(item: Item) =
    # item is (ecs, entity)
    # templates position and velocity are generated
    position.x += velocity.x
    position.y += velocity.y

# =========================
# World setup
# =========================

createECS(ECSConfig(maxEntities: CAPACITY))

# =========================
# Benchmarks
# =========================

proc runEasyBenchmarks() =
  var suite = initSuite("Easyess")

  # ------------------------------
  # Create entity
  # ------------------------------
  # Easyess doesn't have a direct "create multiple" without components in a single call like Cruise
  # But we can simulate it.

  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      var ents: seq[Entity]
    ),
    (
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        (ecs, e).addVelocity(Velocity(x: 1.0, y: 1.0))
        ents.add e
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Delete entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        (ecs, e).addVelocity(Velocity(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        ecs.removeEntity(e)
    )
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
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        (ecs, e).addComponent(Velocity(x: 1.0, y: 1.0))
    )
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
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        (ecs, e).addVelocity(Velocity(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        (ecs, e).removeComponent(Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add + Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        (ecs, e).addComponent(Velocity(x: 1.0, y: 1.0))
        (ecs, e).removeComponent(Velocity)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Iteration
  # ------------------------------
  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        (ecs, e).addVelocity(Velocity(x: 1.0, y: 1.0))
    ),
    (
      ecs.runMovement()
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Read
  # ------------------------------
  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        s += (ecs, e).position.x
    )
  )
  showDetailed(suite.benchmarks[^1])
  blackBox(s)

  # ------------------------------
  # Write
  # ------------------------------
  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    WARMUP,
    (
      var ecs = newECS()
      var ents: seq[Entity]
      for i in 0..<ENTITY_COUNT:
        let e = ecs.newEntity("bench")
        (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
        ents.add e
    ),
    (
      for e in ents:
        (ecs, e).position = Position(x: s, y: s)
    )
  )
  showDetailed(suite.benchmarks[^1])
  blackBox(s)

  var rng = initRand(42)

  suite.add benchmarkWithSetup(
  "heterogeneous iter",
  SAMPLE,
  WARMUP,
  (
    var ecs = newECS()
    for i in 0..<ENTITY_COUNT:
      let e = ecs.newEntity("bench")
      for j in 0..<10:
        if rng.rand(1.0) < SELECTION_THRESHOLD:
          case j
          of 0: (ecs, e).addPosition(Position(x: 1.0, y: 1.0))
          of 1: (ecs, e).addVelocity(Velocity(x: 1.0, y: 1.0))
          of 2: (ecs, e).addAcceleration(Acceleration(x: 1.0, y: 1.0))
          of 3: (ecs, e).addRotation(Rotation(angle: 0.5))
          of 4: (ecs, e).addScale(Scale(sx: 1.0, sy: 1.0))
          of 5: (ecs, e).addMass(Mass(value: 1.0))
          of 6: (ecs, e).addForce(Force(fx: 1.0, fy: 1.0))
          of 7: (ecs, e).addTorque(Torque(value: 1.0))
          of 8: (ecs, e).addEnergy(Energy(value: 1.0))
          of 9: (ecs, e).addFriction(Friction(coef: 0.5))
          else: discard
    ),
    (
      ecs.runMovementHetero()
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.showSummary()
  suite.saveSummary("easy")

if isMainModule:
  const maxSupportedEntities = int(high(Entity)) + 1
  if CAPACITY > maxSupportedEntities:
    echo "ERROR: CAPACITY (" & $CAPACITY & ") exceeds the maximum supported number of entities (" & $maxSupportedEntities & ") for this build of easyess."
    echo "Reduce ENTITY_COUNT or adjust the ECS library configuration."
  else:
    runEasyBenchmarks()
