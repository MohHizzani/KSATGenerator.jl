module KSATGenerators

using Random
using StatsBase   # pkg> add StatsBase

struct Clause
    lits::Vector{Int}   # e.g. [-3, 17, 5]
end

struct CNF
    nvars::Int
    clauses::Vector{Clause}
end

function write_dimacs(io::IO, F::CNF)
    println(io, "p cnf $(F.nvars) $(length(F.clauses))")
    for c in F.clauses
        println(io, join(c.lits, " "), " 0")
    end
end
write_dimacs(path::AbstractString, F::CNF) = open(io->write_dimacs(io,F), path; write=true)

# -- canonicalization helper (no var duplicates within a clause) --
# Sort by |var|, then sign (neg before pos); return a compact, stable key.
function _canon_key!(lits::Vector{Int})
    sort!(lits, by = x -> (abs(x), x < 0 ? 0 : 1))
    return join(lits, ',')  # string key works well with Set{String}
end

"""
    gen_uniform_kSAT(n::Int, k::Int, α::Real; rng=Random.default_rng(), unique_clauses::Bool=false)

Uniform random k-SAT: each clause picks k distinct variables uniformly; signs are ± with p=0.5.
If `unique_clauses=true`, reject and resample any clause that duplicates a previous one.
"""
function gen_uniform_kSAT(n::Int, k::Int, α::Real; rng=Random.default_rng(), unique_clauses::Bool=false)
    @assert 1 ≤ k ≤ n "k must be in [1,n]"
    m = Int(round(α*n))
    clauses = Vector{Clause}()
    sizehint!(clauses, m)

    seen = unique_clauses ? Set{String}() : nothing
    buf  = Vector{Int}(undef, k)

    while length(clauses) < m
        vars = sample(rng, 1:n, k; replace=false)      # no duplicate variables in a clause
        @inbounds for t in 1:k
            v = vars[t]
            buf[t] = rand(rng, Bool) ?  v : -v
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
    end
    return CNF(n, clauses)
end

"""
    gen_scalefree_kSAT(n::Int, k::Int, α::Real; β::Real=0.5, rng=Random.default_rng(), unique_clauses::Bool=false)

Scale-free k-SAT: variable i is chosen with probability ∝ i^{-β} (Zipf-like),
k distinct vars per clause; signs are ± with p=0.5. If `unique_clauses=true`,
duplicates are rejected and resampled.
"""
function gen_scalefree_kSAT(n::Int, k::Int, α::Real; β::Real=0.5, rng=Random.default_rng(), unique_clauses::Bool=false)
    @assert 0 < β ≤ 1 "β should be in (0,1]"
    @assert 1 ≤ k ≤ n
    m = Int(round(α*n))

    w = (1:n) .^ (-β)
    W = Weights(w)

    clauses = Vector{Clause}()
    sizehint!(clauses, m)

    seen = unique_clauses ? Set{String}() : nothing
    buf  = Vector{Int}(undef, k)

    while length(clauses) < m
        vars = sample(rng, 1:n, W, k; replace=false)
        @inbounds for t in 1:k
            v = vars[t]
            buf[t] = rand(rng, Bool) ?  v : -v
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
    end
    return CNF(n, clauses)
end

end # module
