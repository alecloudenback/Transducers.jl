module TestExamplesTutorialMissings
include("../examples/tutorial_missings.jl")

using Test

@testset "outtype of xf_sum_columns" begin
    @test eltype(eduction(xf_sum_columns(Float64[]), Any[])) ===
        Vector{Float64}
    @test eltype(eduction(xf_sum_columns(Float64[]), Any[])) <: Vector
end

@testset "slow compilation" begin
    # Excluding `missing` from the input vector seems to slows down
    # compilation a lot.
    @info "Running slow compilation test with xf_fullextrema. ETA ~ 3 min."
    @time @test mapfoldl(xf_fullextrema(), right, [1.0, 3.0, -1.0, 2.0]) ==
        ((3, -1.0), (2, 3.0))
    @info "Running slow compilation test with xf_argextrema. ETA ~ 5 min."
    @time @test mapfoldl(xf_argextrema(), right, [1.0, 3.0, -1.0, 2.0]) ==
        (3, 2)
end

end  # module