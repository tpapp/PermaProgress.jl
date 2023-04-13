#####
##### parsing logfiles
#####

export add_stage, log_entry, next_stage, add_next_stage

####
#### logfile data
####

"Header string, all binary logfiles start with this."
const HEADER = "PermaProgress.jl logfile"

"""
Current version of logfile binary format.

!!! note
    Versioning will only be taken seriously after the 1.0 release of this library, until then, format changes freely.
"""
const CURRENT_VERSION = Int64(1)

"Maximum string length. For strings longer than this, reading may error."
const MAX_STRING_LEN = 120

"Supported numeric types."
const SUPPORTED_NUMERIC_TYPES = Union{Float64,Int16,Int64,UInt64}

"Sentinel value for starting another stage."
const STEP_NEXTSTAGE = -1

"Sentinel value for unknown total steps."
const TOTAL_STEPS_UNKNOWN = -1

"""
$(SIGNATURES)

A version of `write` for all the types we use. Numbers are written in low-endian format.
"""
_write(io::IO, x::SUPPORTED_NUMERIC_TYPES) = write(io, htol(x))

"""
$(SIGNATURES)

Read data written by [`_write`](@ref).
"""
_read(io::IO, ::Type{T}) where {T <: SUPPORTED_NUMERIC_TYPES} = ltoh(read(io, T))

"""
$(SIGNATURES)

Write the length of the string as an `UInt16`, then the UTF-8 codeunits.
"""
function _write(io::IO, str::String)
    len = ncodeunits(str)
    if len > MAX_STRING_LEN
        len = MAX_STRING_LEN
        if !isvalid(str, len)
            len = prevind(str, len)
        end
    end
    _write(io, Int16(len))
    write(io, @view codeunits(str)[1:len])
end

_write(io::IO, str::AbstractString) = _write(io, String(str))

function _read(io::IO, ::Type{String})
    n = _read(io, Int16)
    n > MAX_STRING_LEN && error("string too long")
    String(read(io, n))
end

Base.@kwdef struct StageSpec
    "label for the stage, always present (but may be empty)"
    label::String
    "total steps, [`TOTAL_STEPS_UNKNOWN`](@ref) if unknown."
    total_steps::Int64 = TOTAL_STEPS_UNKNOWN
end

function _write(io::IO, x::StageSpec)
    write(io, UInt8('S'))
    _write(io, x.label)
    _write(io, x.total_steps)
end

function _read(io::IO, ::Type{StageSpec})
    StageSpec(; label = _read(io, String), total_steps = _read(io, Int64))
end

"""
A log entry within a stage.

$(FIELDS)
"""
Base.@kwdef struct LogEntry
    "timestap in nanoseconds (cf [`time_ns`](@ref), always present"
    time_ns::UInt64 = time_ns()
    "step, always provided. special values: `STEP_NEXTSTAGE` for starting a stage, `0` for completing initialization of a stage."
    step::Int64
    "distance metric, used for estimation when total steps are not known or applicable."
    distance::Float64 = NaN
end

function _write(io::IO, x::LogEntry)
    write(io, UInt8('L'))
    _write(io, x.time_ns)
    _write(io, x.step)
    _write(io, x.distance)
end

function _read(io::IO, ::Type{LogEntry})
    LogEntry(; time_ns = _read(io, UInt64), step = _read(io, Int64), distance = _read(io, Float64))
end

####
#### reading
####

function _read_entry(io::IO)
    h = read(io, UInt8)
    if h == UInt8('S')
        _read(io, StageSpec)
    elseif h == UInt8('L')
        _read(io, LogEntry)
    else
        error("Don't know how to parse entries beginning with $(Char(h))")
    end
end

"""
$(SIGNATURES)

Check that `time_ns` properties of the elements in the vector are ascending.
"""
function _is_ascending_time_ns(log_entries::AbstractVector)
    isempty(log_entries) && return true
    t0 = log_entries[1].time_ns
    for e in @view log_entries[2:end]
        t = e.time_ns
        t - t0 ≥ 0 && return false # difference because of wrap-around
        t0 = t
    end
    true
end

function parse_file_v1(io::IO)
    current_stage = 1
    stages = Vector{Pair{StageSpec,Vector{LogEntry}}}()
    _add_stage(stage_spec::StageSpec) = push!(stages, stage_spec => Vector{LogEntry}())
    _log_entry(log_entry::LogEntry) = push!(last(last(stages)), log_entry)
    while !eof(io)
        entry = _read_entry(io)
        if entry isa StageSpec
            _add_stage(entry)
        elseif entry isa LogEntry
            if entry.step == STEP_NEXTSTAGE
                l = length(stages)
                current_stage ≥ l && _add_stage(StageSpec(; label = "stage $(l + 1)"))
                current_stage += 1
            end
            _log_entry(entry)
        else
            error("internal error")
        end
    end
    for stage in stages
        if !_is_ascending_time_ns(stage[2])
            error("non-ascending time entries in stage $(stage.label)")
        end
    end
    stages
end

function parse_file(io::IO)
    header = read(io, length(HEADER))
    @argcheck String(header) == HEADER "invalid header $(header)"
    version = _read(io, Int64)
    if version == 1
        parse_file_v1(io)
    else
        error("Don't know how to handle version $(version), perhaps update the package.")
    end
end

parse_file(pathname::AbstractString) = open(parse_file, pathname; read = true)

####
#### writing
####

function _write_entry(pathname::AbstractString, entry; skip_check::Bool = false)
    if skip_check
        exists = true
    else
        exists = isfile(pathname)
        if !exists && ispath(pathname)
            error("$pathname exists, but it is not a file")
        end

    end
    open(pathname; append = true) do io
        if !exists
            print(io, HEADER)
            _write(io, CURRENT_VERSION)
        end
        _write(io, entry)
    end
    nothing
end

function add_stage(pathname::AbstractString; skip_check = false, label = "", total_steps = -1)
    _write_entry(pathname, StageSpec(; label, total_steps); skip_check)
end

function log_entry(pathname::AbstractString; step, skip_check = false, distance = NaN)
    _write_entry(pathname, LogEntry(; time_ns = time_ns(), step, distance); skip_check)
end

function next_stage(pathname::AbstractString; skip_check::Bool = false)
    _write_entry(pathname, LogEntry(; time_ns = time_ns(), step = STEP_NEXTSTAGE); skip_check)
end

function add_next_stage(pathname::AbstractString; skip_check = false, label = "", total_steps = TOTAL_STEPS_UNKNOWN)
    add_stage(pathname; label, total_steps, skip_check)
    next_stage(pathname; skip_check = true)
end
