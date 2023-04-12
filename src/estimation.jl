#####
##### estimation of remaining time left
#####

export estimate_seconds_per_step

"""
$(SIGNATURES)

Estimate seconds/step, also return last step as a `(; seconds_per_step, last_step)` `NamedTuple`.

Estimation using exponential weighted average, `α` is the decay parameter *per step*.
"""
function estimate_seconds_per_step(log_entries::Vector{LogEntry}; α = 0.99)
    @argcheck 0 < α ≤ 1
    step = -1                   # last step, -1 sentinel for no steps yet
    t = UInt64(0)               # time of last step in ns, only set when step > 0
    speed = NaN                 # estimate of seconds/step
    for e in log_entries
        e.step > 0 || continue
        if step > 0
            Δt = e.time_ns - t  # time since last
            Δn = e.step - step  # steps since last
            current_speed = Float64(Δt) / exp10(9) / Δn # second/step
            if isnan(speed)
                speed = current_speed
            else
                speed += α^Δn * (current_speed - speed)
            end
            t = e.time_ns
            step = e.step
        else
            step = e.step
            t = e.time_ns
        end
    end
    (; seconds_per_step = speed, last_step = step)
end
