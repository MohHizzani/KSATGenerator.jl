using KSATGenerators
using Test
using Random

@testset "KSATGenerators.jl" begin
    function clause_satisfied(clause::KSATGenerators.Clause, sol::Vector{Bool})
        for lit in clause.lits
            v = abs(lit)
            lit_val = lit > 0 ? sol[v] : !sol[v]
            lit_val && return true
        end
        return false
    end

    @testset "planted solution - uniform" begin
        rng = MersenneTwister(1234)
        n, k, α = 50, 4, 6.0
        planted = rand(rng, Bool, n)

        F = KSATGenerators.gen_uniform_kSAT(n, k, α; rng, planted_solution=planted)
        @test F.nvars == n
        @test length(F.clauses) == Int(round(α * n))
        @test all(c -> clause_satisfied(c, planted), F.clauses)
    end

    @testset "planted solution - scale-free" begin
        rng = MersenneTwister(4321)
        n, k, α = 50, 4, 6.0
        planted = rand(rng, Bool, n)

        F = KSATGenerators.gen_scalefree_kSAT(n, k, α; β=2.5, rng, planted_solution=planted)
        @test F.nvars == n
        @test length(F.clauses) == Int(round(α * n))
        @test all(c -> clause_satisfied(c, planted), F.clauses)
    end

    @testset "power-law exponent convention" begin
        n = 10
        β = 2.5
        weights = KSATGenerators._powerlaw_variable_weights(n, β)

        @test weights[1] == n^(1 / (β - 1))
        @test weights[end] == 1.0
        @test issorted(weights; rev=true)
        @test_throws AssertionError KSATGenerators.gen_scalefree_kSAT(10, 3, 2.0; β=1.0)
    end

    @testset "planted solution validation" begin
        rng = MersenneTwister(1)
        @test_throws AssertionError KSATGenerators.gen_uniform_kSAT(10, 3, 2.0; rng, planted_solution=Bool[true, false])
        @test_throws AssertionError KSATGenerators.gen_scalefree_kSAT(10, 3, 2.0; rng, planted_solution=Bool[true, false])
    end
end
