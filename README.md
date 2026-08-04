# Nim ECS Benchmark Suite

A comprehensive performance benchmark suite for various Entity Component System (ECS) libraries in the Nim programming language. This project aims to provide objective, data-driven comparisons of entity lifecycle management, component mutations, and system iteration across different architectural approaches (Archetypes vs. Sparse Sets vs. Generative macros).

## Benchmark setup

- Intel core i7 4 core @2.8Ghz
- 16Go RAM
- Compiled with `nim c -r -d:danger`

## Comparison Overview (10,000 Entities)

The following table summarizes the mean execution times across all tested libraries.

| Library | Architecture | Creation | Iteration | Add Comp | Remove Comp | Memory |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Cruise Dense** | Archetype | **551 µs** | **12.5 µs** | N/A | N/A | 160 KB |
| **Cruise Sparse** | Sparse Set | 1.56 ms | **25 µs** | 1.16 ms | 833 µs | ~20 KB |
| **Easyess** | Bitset/Table | 852 µs | 123 µs | **484 µs** | **379 µs** | **36 KB** |
| **MiniECS** | Sparse Set | 6.47 ms | 84 µs | 2.73 ms | 4.94 ms | 1.8 MB |
| **Necsus** | Framework | 1.70 ms | 2.46 ms | N/A | N/A | < 1 KB* |
| **Polymorph** | Generative | 4.60 ms | < 1 µs | 7.06 ms | 3.28 ms | 132 KB |

*\*Note: Necsus memory reporting may be influenced by its unique app-state initialization.*

---

## Detailed Metric Explanations

### 1. Entity Creation
Measures the time to spawn 10,000 entities with two standard components (`Position` and `Velocity`).
*   **Winner**: **Cruise Dense**. Optimized archetype allocation allows it to push entities into contiguous memory blocks with minimal overhead.
*   **Observation**: Libraries using Sparse Sets (MiniECS) tend to be slower here due to the overhead of managing sparse-to-dense index mappings during initialization.

### 2. System Iteration
The most critical metric for performance. It measures how long it takes a system to process all 10,000 entities (e.g., updating position by velocity).
*   **Winner**: **Cruise Dense** & **Polymorph**. 
    *   Cruise Dense benefits from perfect CPU L1/L2 cache locality. 
    *   Polymorph uses compile-time code generation to eliminate runtime dispatch entirely.
*   **Observation**: Necsus is significantly slower here because it wraps logic in a full application framework, trading raw speed for high-level safety and organization.

### 3. Component Addition/Removal
Measures the "dynamism" of the ECS—how fast you can add or remove a component from an existing entity at runtime.
*   **Winner**: **Easyess**. Archetype-based engines (Cruise Dense, Necsus) have to physically move the entity's data between different tables when its "shape" changes. Easyess uses a flexible table/bitset approach that makes structural mutations very cheap.

### 4. Memory Footprint
Measures the heap overhead introduced by the ECS when handling 10,000 entities.
*   **Winner**: **Easyess**. Its bitset-driven approach is extremely lightweight.
*   **Observation**: **MiniECS** showed significant memory pressure and erratic allocation patterns at this scale, suggesting it may not be suitable for large-scale entity counts without further optimization.

---

## How to run benchmarks

Ensure you have Nim installed and the libraries located in the `libs/` folder.

1.  **Clone the repository**.
2.  **Compile and run a specific benchmark**:
    ```bash
    nim c -r -d:danger src/cr_dense.nim
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
