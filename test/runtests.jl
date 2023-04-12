using PermaProgress
using Test
using PermaProgress: LogEntry, StageSpec

const PATH = joinpath(@__DIR__, "test.log")

####
#### utility functions
####

###
### flexible comparison for unit testing
###

function ≂(a::StageSpec, b::StageSpec)
    a.label == b.label || return false
    if b.total_steps > 0
        a.total_steps == b.total_steps
    else
        true
    end
end

function ≂(a::LogEntry, b::LogEntry)
    if b.step ≥ 0
        a.step == b.step || return false
    end
    if !isnan(b.distance)
        a.step == b.step || return false
    end
    true
end

≂(a::Vector, b::Vector) = length(a) == length(b) && all(a .≂ b)

@testset "logfile roundtrip" begin
    rm(PATH; force = true)
    add_stage(PATH; label = "stage 1", total_steps = 200)
    log_entry(PATH; step = 8)
    add_next_stage(PATH; label = "stage super α")
    l = PermaProgress.parse_file(PATH)
    @test l[1][1] ≂ StageSpec(; label = "stage 1", total_steps = 200)
    @test l[1][2] ≂ [LogEntry(; step = 8)]
    @test l[2][1] ≂ StageSpec(; label = "stage super α")
    @test l[2][2] ≂ [LogEntry(; step = 0)]
end

@testset "seconds/step estimate basic consistency" begin
    log_entries = [LogEntry(time_ns = exp10(9) * i, step = i) for i in 1:10]
    e = estimate_seconds_per_step(log_entries)
    @test e.seconds_per_step == 1.0
    @test e.last_step == 10
end
