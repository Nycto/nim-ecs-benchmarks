# Nim ECS Benchmark Suite

A comprehensive performance benchmark suite for various Entity Component System (ECS) libraries in the Nim programming language. This project aims to provide objective, data-driven comparisons of entity lifecycle management, component mutations, and system iteration across different architectural approaches (Archetypes vs. Sparse Sets vs. Generative macros).

## Benchmark setup

- Compiled with `nim c -r -d:danger`, Nim pinned to 2.2.10
- Measured on a GitHub-hosted `ubuntu-latest` runner, regenerated on every push
  to `main`
- Every value is a **median**, not a mean

The tables below are produced by CI rather than typed by hand, so they always
describe the commit they are published from. The runner is a shared virtual
machine with no frequency pinning, which means the **absolute** milliseconds are
indicative rather than authoritative — expect them to move between runs. What
does survive that is the **comparison**: every library is measured back to back
in a single run on a single machine, so the ordering within a row, and the ratio
between two rows of the same library, are the parts worth reading. Each image
carries the runner, commit and date it came from.

## Comparison Overview (10,000 Entities)

<img alt="Median time and memory for every benchmark across all eight ECS libraries"
     src="https://nycto.github.io/nim-ecs-benchmarks/benchmarks.svg">

Memory is Nim's GC heap only. Pirata allocates its columns with `allocShared`
and Polymorph its entity storage with `alloc0`, neither of which
`getOccupiedMem` can see, so those two figures are a floor rather than a total.
Necsus reports very little for the same reason — its storage is sized once at
app-state initialisation, outside the window each sample measures.

A `-` means the suite does not report that metric.

---

## Detailed Metric Explanations

What each row measures, and what tends to drive the differences. The numbers
themselves live in the table above — this section deliberately does not repeat
them, because it is written by hand and the table is not.

### 1. Entity Creation
The time to spawn `ENTITY_COUNT` entities carrying two standard components
(`Position` and `Velocity`).
*   Preallocated and archetype layouts do well here: they push entities into
    contiguous memory with little bookkeeping per spawn.
*   Sparse sets pay for maintaining sparse-to-dense index mappings on the way in.

### 2. System Iteration
How long a system takes to walk every entity and update position by velocity.
Usually the metric that decides whether a library is usable.
*   Contiguous storage wins on cache locality; the loop is memory-bound and the
    layout is most of the answer.
*   Read this one together with **[Iteration after churn](#iteration-after-churn)**
    below. This row measures a world that was built once and never disturbed,
    which is the best case and not the case a running game is in.
*   Anything reporting an implausibly small number here is worth distrusting.
    Polymorph once measured under a microsecond for this row; that was the
    optimiser deleting the loop, and it disappeared when the harness grew a
    dead-code barrier (`blackBox` in `src/benchmarks.nim`).

### 3. Component Addition/Removal
How dynamic the library is — the cost of changing an entity's shape at runtime.
*   Archetype engines have to physically move the entity's data between tables
    when its shape changes, so they are structurally disadvantaged here.
*   Bitset and preallocated-column designs mostly flip a bit and leave the data
    where it is, which is much cheaper — though for a preallocated column that
    cheapness is exactly what the churn benchmark below charges for later.

### 4. Memory Footprint
Heap retained while handling the entities.
*   This is Nim's GC heap only. Pirata (`allocShared`) and Polymorph (`alloc0`)
    allocate outside it, so their figures are a floor, not a total, and should
    not be compared directly against the others.
*   Necsus sizes its storage once during app-state initialisation, before the
    measured window opens, so it under-reports for a different reason.

---

## Iteration after churn

`pristine iter` and `churn iter` are a matched pair, run at `ChurnEntityCount`
(`src/churn_common.nim`) rather than `ENTITY_COUNT`. Both walk a million
entities carrying `Position` and `Velocity` and add the second to the first;
they differ only in how the world was reached. `pristine iter` spawns and
iterates. `churn iter` spawns the same number, then runs ten rounds of *destroy
a random fifth, respawn a fifth*, and iterates the million that remain. The
schedule is seeded, so every library churns identically.

Every other iteration row measures a world that was built once and never
disturbed, which is not the state a running game is in. This pair asks whether a
library's iteration speed survives its own history.

Both rows are in the table above. **Read them as a ratio against each other, not
as milliseconds.** The two worlds are built before either is timed and the
sampling loop alternates between them, because at this size the rows are
memory-bound and what a build happens to get from the allocator matters as much
as its layout — measured one after the other, Vecs timed the same work at 45 ms
in the first position and 20 ms in the second. Both worlds being resident at
once also means both carry more cache pressure than either would alone.

**The split is not architecture.** Cruise Sparse and MiniECS are both sparse-set
engines and sit at opposite ends. What matters is whether the order a query
walks in stays correlated with the order components are stored in once entities
start dying, and that is a property of the individual library. Pirata stores a
component at an address fixed by the entity's *slot* index while `query` yields
*dense* order; the first delete swap-removes a dense entry and the correlation
is gone for good. MiniECS fails the same way one level down, in the second hop
of `allWith`.

**Two libraries show `-`.** Easyess's `BaseIDType` is `uint16`, so entity IDs
wrap at 65,536 regardless of `ECSConfig(maxEntities: …)`. Polymorph seals one
global ECS per module, so the two worlds cannot coexist and the alternating
sample needs both. Neither carries a number the method does not support.

**These rows are 20 samples, not `SAMPLE`.** A world of a million entities
cannot be rebuilt per sample, so it is built once and the loop only iterates it.
That also means the memory figure is the heap retained across world
construction, substituted once.

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

2.  **Compile and run a specific benchmark**:
    ```bash
    nim c -r -d:danger src/cr_dense_bench.nim
    nim c -r -d:danger src/easy_bench.nim
    nim c -r -d:danger -p:libs/polymorph/src src/poly_bench.nim
    ```

3.  **Compile and run all benchmarks**:
    ```bash
    ./run_benchmarks.sh
    ```
    Extra arguments are handed to the compiler, so the suites can be tuned:
    ```bash
    ./run_benchmarks.sh -d:SAMPLE=10 -d:ENTITY_COUNT=100
    ```

4.  **Re-render the comparison table** from CSVs that already exist:
    ```bash
    nim r src/results.nim          # every *.csv in the current directory
    nim r src/results.nim results/*.csv
    ```

Either of the last two also writes `site/`: `benchmarks.svg`, which is the table
the README embeds, and `summary.txt`. CI publishes that directory to GitHub
Pages, which is what keeps the table above current — a README cannot include a
file, only an image or committed text, and `raw.githubusercontent.com` serves
SVG as `text/plain`, so the image has to come from Pages rather than the repo.
