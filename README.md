# KSATGenerators

[![Build Status](https://github.com/MohHizzani/KSATGenerators.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/MohHizzani/KSATGenerators.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/MohHizzani/KSATGenerators.jl/branch/main/graph/badge.svg?token=KSATGEN)](https://codecov.io/gh/MohHizzani/KSATGenerators.jl)

A lightweight Julia package to generate **random k‑SAT** formulas (uniform model) and **scale‑free ("industrial‑like") k‑SAT** where variable occurrences follow a power‑law distribution. It produces in‑memory CNF objects and **DIMACS CNF** files compatible with mainstream SAT solvers.

---

## Features

* **Uniform random k‑SAT** at a chosen clause density `α = m/n`.
* **Scale‑free k‑SAT** using the power-law exponent convention from Power-Law-Random-SAT-Generator: `p(i) ∝ (n / i)^(1 / (β - 1))`, with `β > 1`.
* **No duplicate variables within a clause** by construction; random literal polarity with `P(neg)=P(pos)=1/2`.
* **Optional uniqueness**: `unique_clauses=true` rejects duplicate clauses.
* **Optional planted assignment**: `planted_solution=...` enforces guaranteed satisfiability.
* **Write DIMACS CNF** directly to disk.
* **Reproducible** via `rng = MersenneTwister(seed)`.

---

## Table of Contents

* [Installation](#installation)
* [Quick start](#quick-start)
* [Batch generation](#batch-generation)
* [Models and parameters](#models-and-parameters)
* [API](#api)
* [Choosing α (clause/variable ratio)](#choosing-α-clausevariable-ratio)
* [Performance & tips](#performance--tips)
* [DIMACS reminder](#dimacs-reminder)
* [Contributing](#contributing)
* [License](#license)

---

## Installation

```julia
julia> ] add https://github.com/MohHizzani/KSATGenerators.jl
```


--

## Quick start

### Installation

```julia
julia> ] add https://github.com/MohHizzani/KSATGenerators.jl
```

### Generate your first formulas

```julia
using KSATGenerators, Random

# Parameters
n   = 5000             # number of variables
k   = 4                # clause length
α   = 9.9              # clause/variable ratio, m ≈ α * n
rng = MersenneTwister(42)

# 1) Uniform random k-SAT
F_uniform = KSATGenerators.gen_uniform_kSAT(n, k, α; rng, unique_clauses=true)

# 2) Scale-free ("industrial-like") k-SAT
β = 2.5                # matches the original generator's -p exponent convention
F_sf = KSATGenerators.gen_scalefree_kSAT(n, k, α; β, rng, unique_clauses=true)

# 3) Planted-solution instance (guaranteed satisfiable by `σ`)
σ = rand(rng, Bool, n)
F_planted = KSATGenerators.gen_uniform_kSAT(n, k, α; rng, planted_solution=σ)

# Write DIMACS CNF files
KSATGenerators.write_dimacs("k4_uniform.cnf", F_uniform)
KSATGenerators.write_dimacs("k4_scalefree_beta2p5.cnf", F_sf)
```

---

## Batch generation

```julia
using KSATGenerators, Random, Printf

n, k, β = 1000, 4, 2.5
alphas  = [9.6, 9.8, 10.0]      # sweep around a hard region for k=4
seeds   = 1:5

for α in alphas, s in seeds
    rng = MersenneTwister(s)
    F = KSATGenerators.gen_uniform_kSAT(n, k, α; rng, unique_clauses=true)
    KSATGenerators.write_dimacs(@sprintf("uniform_n%d_k%d_a%.1f_s%02d.cnf", n, k, α, s), F)

    Fsf = KSATGenerators.gen_scalefree_kSAT(n, k, α; β, rng, unique_clauses=true)
    KSATGenerators.write_dimacs(@sprintf("scalefree_n%d_k%d_a%.1f_b%.1f_s%02d.cnf", n, k, α, β, s), Fsf)
end
```

---

## Models and parameters

### Uniform random k‑SAT

* Each clause samples **k distinct variables uniformly** from `1:n` (without replacement).
* Each selected variable is negated with probability 1/2 (independently).
* This is the classical experimental model used in random k‑SAT studies.

### Scale‑free ("industrial‑like") k‑SAT

* Each clause samples **k distinct variables with weights** `w_i ∝ (n / i)^(1 / (β - 1))` for `i = 1..n`.
* This matches the variable-weight convention used by Power-Law-Random-SAT-Generator's `-p` option.
* Typical `β` values are greater than 1; for example, the original generator defaults to `2.75` and its README example uses `2.5`.

**Clause uniqueness option**
Set `unique_clauses=true` in either generator to **reject duplicate clauses** (canonicalized by absolute variable index and sign order). This slightly conditions the i.i.d. model but keeps datasets tidy.

---

## API

```julia
gen_uniform_kSAT(n::Int, k::Int, α::Real;
                 rng=Random.default_rng(),
                 unique_clauses::Bool=false,
                 planted_solution=nothing) -> CNF

gen_scalefree_kSAT(n::Int, k::Int, α::Real;
                   β::Real=2.75,
                   rng=Random.default_rng(),
                   unique_clauses::Bool=false,
                   planted_solution=nothing) -> CNF

write_dimacs(io::IO, F::CNF)
write_dimacs(path::AbstractString, F::CNF)
```

**Types**

```julia
struct Clause
    lits::Vector{Int}   # e.g. [-3, 17, 5]
end

struct CNF
    nvars::Int
    clauses::Vector{Clause}
end
```

---

## Choosing α (clause/variable ratio)

For uniform random k‑SAT, the peak hardness typically occurs near the satisfiability threshold `α_c(k)`. For example, for `k=4`, many studies explore `α ≈ 9.9`. For finite `n`, use a **small sweep around** `α_c` (e.g., ±0.2–0.5) to capture the hard region. In scale‑free models, the effective threshold shifts with `β`; consider exploring a grid `(α, β)` if your goal is hardness.

---

## Performance & tips

* **Speed**: generation is (O(mk)). The uniqueness option adds a hash‑set membership check per clause; for typical sizes and densities the overhead is small.
* **Memory**: uniqueness keeps a `Set` of canonicalized clauses; budget roughly `O(mk)` integers.
* **Reproducibility**: always pass an explicit RNG (e.g., `MersenneTwister(seed)`). Consider writing out a CSV manifest with `(n, k, α, β, seed, path)` for your benchmarks.
* **Planted model**: pass `planted_solution` as a `Bool` vector of length `n`; each clause is sampled until satisfied by that assignment.

---

## DIMACS reminder

A tiny CNF with three variables and two clauses:

```
p cnf 3 2
 1 -2  3 0
-1  2  0
```

* Variables are positive integers; negations are negative.
* Each clause terminates with `0`.

---

## Contributing

Issues and PRs are welcome! Please include a minimal example (parameters, RNG seed, and a small CNF if relevant). Style: follow standard Julia package conventions.

---

## License

**MIT** — see `LICENSE`.
