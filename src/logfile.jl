#####
##### parsing logfiles
#####

export add_stage, log_entry, next_stage, add_next_stage

####
#### logfile data
####

const HEADER = "PermaProgress.jl logfile"

const CURRENT_VERSION = Int64(1)

const MAX_STRING_LEN = 120

const SUPPORTED_NUMERIC_TYPES = Union{Float64,Int16,Int64,UInt64}

_write(io::IO, x::SUPPORTED_NUMERIC_TYPES) = write(io, htol(x))

_read(io::IO, ::Type{T}) where {T <: SUPPORTED_NUMERIC_TYPES} = ltoh(read(io, T))

function _write(io, str::String)
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

function _read(io, ::Type{String})
    n = _read(io, Int16)
    n > MAX_STRING_LEN && error("string too long")
    String(read(io, n))
end

Base.@kwdef struct StageSpec
    "label for the stage"
    label::String
    total_steps::Int64 = -1
end

function _write(io::IO, x::StageSpec)
    write(io, UInt8('S'))
    _write(io, x.label)
    _write(io, x.total_steps)
end

function _read(io::IO, ::Type{StageSpec})
    StageSpec(; label = _read(io, String), total_steps = _read(io, Int64))
end

Base.@kwdef struct LogEntry
    time_ns::UInt64 = time_ns()
    step::Int64 = -1
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

Base.@kwdef struct NextStage
    time_ns::UInt64
end

function _write(io::IO, x::NextStage)
    write(io, UInt8('N'))
    _write(io, x.time_ns)
end

function _read(io::IO, ::Type{NextStage})
    NextStage(; time_ns = _read(io, UInt64))
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
    elseif h == UInt8('N')
        _read(io, NextStage)
    else
        error("Don't know how to parse entries beginning with $(Char(h))")
    end
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
        elseif entry isa NextStage
            l = length(stages)
            current_stage ≥ l && _add_stage(StageSpec(; label = "stage $(l + 1)"))
            current_stage += 1
            _log_entry(LogEntry(; entry.time_ns, step = 0, distance = NaN))
        elseif entry isa LogEntry
            _log_entry(entry)
        else
            error("internal error")
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

function log_entry(pathname::AbstractString; skip_check = false, step = -1, distance = NaN)
    _write_entry(pathname, LogEntry(; time_ns = time_ns(), step, distance); skip_check)
end

function next_stage(pathname::AbstractString; skip_check::Bool = false)
    _write_entry(pathname, NextStage(; time_ns = time_ns()); skip_check)
end

function add_next_stage(pathname::AbstractString; skip_check = false, label = "", total_steps = -1)
    add_stage(pathname; label, total_steps, skip_check)
    next_stage(pathname; skip_check = true)
end
