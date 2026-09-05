# Nim ECS Benchmark Suite

A comprehensive performance benchmark suite for various Entity Component System (ECS) libraries in the Nim programming language. This project aims to provide objective, data-driven comparisons of entity lifecycle management, component mutations, and system iteration across different architectural approaches (Archetypes vs. Sparse Sets vs. Generative macros).

## Benchmark setup

- Compiled with `nim c -r -d:danger`, Nim pinned to 2.2.10
- Measured on a GitHub-hosted `ubuntu-latest` runner, regenerated on every push
- Every figure is a **median**, never a mean
- Most rows use `ENTITY_COUNT` (10,000) entities over `SAMPLE` (1,000) samples;
  the two churn rows use a million entities over 20 samples

The table below is rendered by CI from the CSVs the suites emit, so it always
describes the commit it was published from. The runner is a shared virtual
machine with no frequency pinning, which means the **absolute** microseconds are
indicative rather than authoritative — expect them to move between runs. What
survives that is the **comparison**: every library is measured back to back in a
single run on a single machine, so the ordering within a row, and the ratio
between two rows of the same library, are the parts worth reading.

## Results

[![Median time and memory for every benchmark across all eight ECS libraries](https://nycto.github.io/nim-ecs-benchmarks/benchmarks.svg)](https://nycto.github.io/nim-ecs-benchmarks/benchmarks.svg)

[![Median time for every benchmark, one panel per metric](https://nycto.github.io/nim-ecs-benchmarks/time.svg)](https://nycto.github.io/nim-ecs-benchmarks/time.svg)

---

## Detailed Metric Explanations

### iteration

Walks every entity carrying `Position` and `Velocity` and adds the second to the
first. Every entity in this world has the same shape, which is the friendliest
case an archetype engine will ever see; the loop is memory-bound, so contiguous
storage and cache locality are most of the answer. Usually the metric that
decides whether a library is usable at all.

### heterogeneous iter

The same loop against a world built to be awkward: ten components are each
attached to a given entity with probability `SELECTION_THRESHOLD` (10%), and
`Position` and `Velocity` are two of the ten, so roughly 1% of the world matches
the query and those matches are scattered across many distinct shapes. This is
where archetype fragmentation shows up, as many small and mostly empty tables to
visit, while sparse sets stay comparatively indifferent to shape.

### pristine iter

A million entities carrying `Position` and `Velocity`, spawned and then
iterated, with nothing deleted in between. On its own it is `iteration` at a
hundred times the size; it exists as the baseline that gives `churn iter` a
meaning.

### churn iter

The same million-entity world, but iterated after ten seeded rounds of
destroying a random fifth of it and respawning a fifth. Read as a ratio against
`pristine iter`, it measures whether a library's iteration speed survives change.

### create entity

Spawns `ENTITY_COUNT` entities, each carrying `Position` and `Velocity`.
Preallocated and archetype layouts tend to do well here, pushing entities into
contiguous memory with little bookkeeping per spawn, while sparse sets pay on
the way in for maintaining their sparse-to-dense index mappings.

### delete entity

Destroys that same population, one entity at a time. Swap-remove strategies are
cheap at this and stay cheap, since a delete is a move of the last element plus
a pair of index updates — at a cost to iteration order that `churn iter` is
built to charge them for later.

### add component

Attaches `Velocity` to ten thousand entities that already carry `Position`,
changing each entity's shape at runtime. Archetype engines are structurally
disadvantaged, because a shape change means physically moving that entity's data
into a different table, whereas bitset and preallocated-column designs mostly
flip a bit and leave the data where it is.

### remove component

The reverse: detaching `Velocity` from entities that carry both. It splits the
field the same way `add component` does and for the same reason, though removal
is often the cheaper direction, since nothing has to be initialised or copied
into place on arrival.

### add remove component

Adds `Velocity` and immediately removes it again, per entity, returning each one
to the shape it started in. It is close to the sum of the two rows above, and it
catches a library that buys a cheap add by making the matching remove expensive.

### read

Sums one field across every entity by handle, with no query involved. This is
the raw cost of the indirection from an entity handle to its component, with
none of the iteration machinery in the way: a direct index into a dense column
is about as fast as this gets, while a generational handle that has to be
validated, or a two-hop sparse lookup, shows up here as a multiple rather than a
percentage.

### write

The same handle-by-handle access, storing a component back instead of reading a
field out. For most libraries it tracks `read` closely, since it is the same
lookup with a store at the end; a library where the two rows diverge sharply is
doing work on assignment that it does not do on access.

---

## How to run benchmarks

The libraries under test are git submodules, so they have to be checked out
before anything will compile.

1.  **Clone the repository and fetch the libraries**:
    ```bash
    git clone https://github.com/Nycto/nim-ecs-benchmarks
    cd nim-ecs-benchmarks
    git submodule update --init
    ```
    Do not use `--recursive`. Cruise's `.gitmodules` points at
    `externalLibs/sdl3` while its gitlink is at `externalLib/sdl3`, so recursing
    fails; the direct submodules are all that is needed.

2.  **Install the reporting dependency**. The benchmarks themselves need
    nothing beyond the submodules, but the report draws its charts with
    [ggplotnim](https://github.com/Vindaar/ggplotnim), which renders through
    Cairo:
    ```bash
    sudo apt-get install -y libcairo2
    nimble install --depsOnly
    ```

3.  **Compile and run a specific benchmark**:
    ```bash
    nim c -r -d:danger src/cr_dense_bench.nim
    nim c -r -d:danger src/easy_bench.nim
    nim c -r -d:danger -p:libs/polymorph/src src/poly_bench.nim
    ```

4.  **Compile and run all benchmarks**:
    ```bash
    ./run_benchmarks.sh
    ```
    Extra arguments are handed to the compiler, so the suites can be tuned:
    ```bash
    ./run_benchmarks.sh -d:SAMPLE=10 -d:ENTITY_COUNT=100
    ```

5.  **Re-render the report** from CSVs that already exist:
    ```bash
    nim r src/report.nim results/*.csv
    ```
