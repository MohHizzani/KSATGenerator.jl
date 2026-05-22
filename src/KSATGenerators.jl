module KSATGenerators

using Random
using StatsBase   # pkg> add StatsBase

export Clause, CNF, random_assignment, write_dimacs, gen_uniform_kSAT, gen_scalefree_kSAT

struct Clause
    lits::Vector{Int}   # e.g. [-3, 17, 5]
end

struct CNF
    nvars::Int
    clauses::Vector{Clause}
end

"""
    random_assignment(n::Int; rng=Random.default_rng())

Generate a random Boolean assignment of length `n`.

This is mainly useful as a planted solution `σ` when calling
`gen_uniform_kSAT` or `gen_scalefree_kSAT` with `planted_solution=σ`.
Pass an explicit `rng` when you want reproducible experiments.
"""
random_assignment(n::Int; rng=Random.default_rng()) = rand(rng, Bool, n)

"""
    write_dimacs(io::IO, F::CNF)

Write a CNF formula in DIMACS format to an open `IO` stream.

Each clause is written as a space-separated list of signed integers, followed
by `0` on its own line. Variable indices are 1-based, and negative integers
represent negated literals.
"""
function write_dimacs(io::IO, F::CNF)
    println(io, "p cnf $(F.nvars) $(length(F.clauses))")
    for c in F.clauses
        println(io, join(c.lits, " "), " 0")
    end
end
"""
    write_dimacs(path::AbstractString, F::CNF)

Write a CNF formula to `path` in DIMACS format.
This is a convenience wrapper around `write_dimacs(io::IO, F::CNF)`.
"""
write_dimacs(path::AbstractString, F::CNF) = open(io->write_dimacs(io,F), path; write=true)

# -- canonicalization helper (no var duplicates within a clause) --
# Sort by |var|, then sign (neg before pos); return a compact, stable key.
function _canon_key!(lits::Vector{Int})
    sort!(lits, by = x -> (abs(x), x < 0 ? 0 : 1))
    return join(lits, ',')  # string key works well with Set{String}
end

function _validate_planted_solution(planted_solution, n::Int)
    if planted_solution === nothing
        return nothing
    end
    @assert length(planted_solution) == n "planted_solution length must equal n"
    return Bool.(planted_solution)
end

@inline function _lit_satisfied_by_planted_solution(lit::Int, planted_solution::AbstractVector{Bool})
    val = planted_solution[abs(lit)]
    return lit > 0 ? val : !val
end

function _choose_sign_for_var(v::Int, rng, pos_count, neg_count, balance::Bool)
    if !balance || pos_count === nothing || neg_count === nothing
        return rand(rng, Bool) ? v : -v
    end
    if pos_count[v] > neg_count[v]
        return rand(rng) < 0.75 ? -v : v
    elseif neg_count[v] > pos_count[v]
        return rand(rng) < 0.75 ? v : -v
    else
        return rand(rng, Bool) ? v : -v
    end
end

function _sample_lits!(buf::Vector{Int}, vars, rng, planted_solution;
                       pos_count=nothing, neg_count=nothing, balance::Bool=false)
    while true
        @inbounds for t in eachindex(buf)
            v = vars[t]
            buf[t] = _choose_sign_for_var(v, rng, pos_count, neg_count, balance)
        end
        planted_solution === nothing && return
        @inbounds for lit in buf
            _lit_satisfied_by_planted_solution(lit, planted_solution) && return
        end
    end
end

function _add_parity_clauses!(clauses::Vector{Clause}, vars_subset::Vector{Int}, parity_bit::Bool,
                              seen::Union{Set{String},Nothing}, unique_clauses::Bool)
    k = length(vars_subset)
    for a in 0:( (1<<k) - 1 )
        bitsum = count_ones(a)
        if (bitsum % 2 == 1) != parity_bit
            lits = Vector{Int}(undef, k)
            for i in 1:k
                v = vars_subset[i]
                bit = (a >> (i-1)) & 1
                lits[i] = bit == 1 ? -v : v
            end
            key = _canon_key!(lits)
            if unique_clauses
                if !(key in seen)
                    push!(seen, key)
                    push!(clauses, Clause(copy(lits)))
                end
            else
                push!(clauses, Clause(copy(lits)))
            end
        end
    end
end

"""
    gen_uniform_kSAT(n::Int, k::Int, α::Real;
                     rng=Random.default_rng(),
                     unique_clauses::Bool=false,
                     planted_solution=nothing)

Generate a uniform random k-SAT formula with `m ≈ α*n` clauses.

Sampling rules:
- each clause picks `k` distinct variables uniformly from `1:n`;
- each literal sign is initially chosen with probability 1/2;
- if `planted_solution` is provided, each clause is resampled until it is
    satisfied by that assignment.

Optional knobs:
- `unique_clauses=true` rejects duplicate clauses;
- `planting_fraction < 1` mixes planted and unplanted clauses;
- `balance_signs=true` nudges literal signs toward per-variable balance;
- `parity_fraction > 0` adds XOR-like parity constraints by expanding them to CNF;
- `parity_consistent_with_planted=true` chooses parity constraints so the planted
    assignment satisfies them.

Important: setting `planting_fraction < 1` makes the formula easier to hide, but
it no longer guarantees satisfiability unless the unplanted clauses are also
conditioned or the formula is rejected when unsatisfiable.
"""
function gen_uniform_kSAT(n::Int, k::Int, α::Real;
                          rng=Random.default_rng(),
                          unique_clauses::Bool=false,
                          planted_solution=nothing,
                          planting_fraction::Real=1.0,
                          balance_signs::Bool=false,
                          parity_fraction::Real=0.0,
                          parity_k::Int=3,
                          parity_consistent_with_planted::Bool=true)
    @assert 1 ≤ k ≤ n "k must be in [1,n]"
    m = Int(round(α*n))
    planted = _validate_planted_solution(planted_solution, n)
    clauses = Vector{Clause}()
    sizehint!(clauses, m)

    seen = unique_clauses ? Set{String}() : nothing
    buf  = Vector{Int}(undef, k)
    pos_count = balance_signs ? zeros(Int, n) : nothing
    neg_count = balance_signs ? zeros(Int, n) : nothing

    while length(clauses) < m
        vars = sample(rng, 1:n, k; replace=false)      # no duplicate variables in a clause
        do_plant = rand(rng) < planting_fraction
        if do_plant
            _sample_lits!(buf, vars, rng, planted; pos_count=pos_count, neg_count=neg_count, balance=balance_signs)
        else
            _sample_lits!(buf, vars, rng, nothing; pos_count=pos_count, neg_count=neg_count, balance=balance_signs)
        end
        if unique_clauses
            key = _canon_key!(buf)
            if !(key in seen)
                push!(seen, key)
                push!(clauses, Clause(copy(buf)))
            end
        else
            push!(clauses, Clause(copy(buf)))
        end
        if balance_signs
            @inbounds for lit in buf
                v = abs(lit)
                lit > 0 ? (pos_count[v] += 1) : (neg_count[v] += 1)
            end
        end
    end

    # optionally add parity constraints
    if parity_fraction > 0.0
        parity_count = Int(round(parity_fraction * m))
        @assert 2 ≤ parity_k ≤ n "parity_k must be between 2 and n"
        @assert parity_k ≤ 6 "parity_k > 6 not supported for direct expansion"
        for i in 1:parity_count
            vars_p = sample(rng, 1:n, parity_k; replace=false)
            parity_bit = parity_consistent_with_planted && planted !== nothing ?
                (count(x->x, planted[vars_p]) % 2 == 1) : rand(rng, Bool)
            _add_parity_clauses!(clauses, vars_p, parity_bit, seen, unique_clauses)
            if balance_signs
                for c in clauses[end - ((1 << (parity_k-1)) - 1):end]
                    @inbounds for lit in c.lits
                        v = abs(lit)
                        lit > 0 ? (pos_count[v] += 1) : (neg_count[v] += 1)
                    end
                end
            end
        end
    end

    return CNF(n, clauses)
end

"""
    gen_scalefree_kSAT(n::Int, k::Int, α::Real;
                       β::Real=2.75,
                       rng=Random.default_rng(),
                       unique_clauses::Bool=false,
                       planted_solution=nothing)

Generate a scale-free k-SAT formula with `m ≈ α*n` clauses.

Variable sampling follows the power-law convention from
Power-Law-Random-SAT-Generator: variable `i` is chosen with probability
proportional to `(n / i)^(1 / (β - 1))`, with `β > 1`.

All other options behave like `gen_uniform_kSAT`:
- clauses use `k` distinct variables;
- signs are random unless balancing or planting is enabled;
- `unique_clauses=true` rejects duplicate clauses;
- `planted_solution` enforces satisfiability clause-by-clause;
- `planting_fraction`, `balance_signs`, and parity options are shared with the
    uniform generator.

Use this model when you want a non-uniform, industrial-like occurrence pattern
instead of uniform variable sampling.
"""
function gen_scalefree_kSAT(n::Int, k::Int, α::Real;
                            β::Real=2.75,
                            rng=Random.default_rng(),
                            unique_clauses::Bool=false,
                            planted_solution=nothing,
                            planting_fraction::Real=1.0,
                            balance_signs::Bool=false,
                            parity_fraction::Real=0.0,
                            parity_k::Int=3,
                            parity_consistent_with_planted::Bool=true)
    @assert β > 1 "β must be greater than 1"
    @assert 1 ≤ k ≤ n
    m = Int(round(α*n))
    planted = _validate_planted_solution(planted_solution, n)

    w = _powerlaw_variable_weights(n, β)
    W = Weights(w)

    clauses = Vector{Clause}()
    sizehint!(clauses, m)

    seen = unique_clauses ? Set{String}() : nothing
    buf  = Vector{Int}(undef, k)
    pos_count = balance_signs ? zeros(Int, n) : nothing
    neg_count = balance_signs ? zeros(Int, n) : nothing

    while length(clauses) < m
        vars = sample(rng, 1:n, W, k; replace=false)
        do_plant = rand(rng) < planting_fraction
        if do_plant
            _sample_lits!(buf, vars, rng, planted; pos_count=pos_count, neg_count=neg_count, balance=balance_signs)
        else
            _sample_lits!(buf, vars, rng, nothing; pos_count=pos_count, neg_count=neg_count, balance=balance_signs)
        end
        if unique_clauses
            key = _canon_key!(buf)
            if !(key in seen)
                push!(seen, key)
                push!(clauses, Clause(copy(buf)))
            end
        else
            push!(clauses, Clause(copy(buf)))
        end
        if balance_signs
            @inbounds for lit in buf
                v = abs(lit)
                lit > 0 ? (pos_count[v] += 1) : (neg_count[v] += 1)
            end
        end
    end

    if parity_fraction > 0.0
        parity_count = Int(round(parity_fraction * m))
        @assert 2 ≤ parity_k ≤ n "parity_k must be between 2 and n"
        @assert parity_k ≤ 6 "parity_k > 6 not supported for direct expansion"
        for i in 1:parity_count
            vars_p = sample(rng, 1:n, parity_k; replace=false)
            parity_bit = parity_consistent_with_planted && planted !== nothing ?
                (count(x->x, planted[vars_p]) % 2 == 1) : rand(rng, Bool)
            _add_parity_clauses!(clauses, vars_p, parity_bit, seen, unique_clauses)
            if balance_signs
                for c in clauses[end - ((1 << (parity_k-1)) - 1):end]
                    @inbounds for lit in c.lits
                        v = abs(lit)
                        lit > 0 ? (pos_count[v] += 1) : (neg_count[v] += 1)
                    end
                end
            end
        end
    end
    return CNF(n, clauses)
end

function _powerlaw_variable_weights(n::Int, β::Real)
    exponent = inv(β - 1)
    return (n ./ (1:n)) .^ exponent
end

end # module
