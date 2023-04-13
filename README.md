# PermaProgress.jl

![lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)
[![build](https://github.com/tpapp/PermaProgress.jl/workflows/CI/badge.svg)](https://github.com/tpapp/PermaProgress.jl/actions?query=workflow%3ACI)
[![codecov.io](http://codecov.io/github/tpapp/PermaProgress.jl/coverage.svg?branch=master)](http://codecov.io/github/tpapp/PermaProgress.jl?branch=master)

<!-- Documentation -- uncomment or delete as needed -->
<!--
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://tpapp.github.io/PermaProgress.jl/stable)
[![Documentation](https://img.shields.io/badge/docs-master-blue.svg)](https://tpapp.github.io/PermaProgress.jl/dev)
-->

# Introduction

Progress meter for long running operations in Julia, using a binary file for logging progress.

A computation just calls a simple interface to write to a single file:

``` julia
using PermaProgress
log_path = "/tmp/my_computation.log"

add_stage(log_path; label = "first stage", total_steps = 100)
for i in 1:100
  log_entry(log_path; step = i)
  # ... do computation
end
computation_done(log_path)
```

This file can be read and analyzed, eg for the purposes of estimating remaining computation time or displaying a progress bar.

# Design principles

- the filesystem is used for logging, a single file for each computation
- this log file can be analyzed independently from the computational process
- callers should feel free to log as often as they like, eg each step, because the binary format is compact

# Related libraries

- [ProgressMeter.jl](https://github.com/timholy/ProgressMeter.jl)
- **TODO fill this list**
