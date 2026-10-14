# =============================================================================
# 02_baseline_voltages.jl: summary statistics of the LV3 node voltages (phase-to-ground)
#
# What it does (plain English): loads LV3 in OpenDSS (with the warm-up solve
#   described below), keeps the LV phase nodes (conductors 1-3, below 1000 V)
#   and prints mean, standard deviation, min, max and the count above 253 V,
#   first over all 165 LV phase nodes, then over the 55 bus averages.
#   These are PHASE-TO-GROUND magnitudes (Circuit.AllBusVolts), not the
#   phase-to-neutral voltages used for the thesis results (see
#   05_voltage_definitions.jl), so "above 253 V" here is not the thesis check.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/02_baseline_voltages.jl")
# Used for: early exploration, not used for thesis results
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
#
# Regression value from an earlier stage: mean 260.91 V, sd 0.39 V. That value was
# obtained with the source at 1.07 pu (260.91 V = 1.07 x 243.9 V, the no-load
# LV voltage; see scripts/notes/worklog.md). Master.dss is now at 1.00 pu and
# the PV and transformer star-point connections have changed since, so a
# rerun will not reproduce 260.91 V.
#
# NOTE: OpenDSSDirect requires a WARM-UP solve. The first solve
# after a fresh Clear/Redirect reports Converged() == true but
# leaves every bus voltage at zero. A throwaway solve followed
# by a full reload is required. Observed on OpenDSSDirect
# v0.9.9 / Julia 1.9.4, and independently in an earlier stage.
# =============================================================================

using OpenDSSDirect, DataFrames, Statistics

network_dir = joinpath(@__DIR__, "..", "data", "networks", "LV3_55bus_withPV")
master_file = joinpath(network_dir, "Master.dss")

function load_and_solve(master)
    dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()   # warm-up
    dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()   # real
    @assert Solution.Converged() "Power flow did not converge"
    @assert maximum(abs.(Circuit.AllBusVolts())) > 1e-6 "All voltages zero - warm-up failed"
    return nothing
end

load_and_solve(master_file)

df = DataFrame(node = Circuit.AllNodeNames(),
               volts = abs.(Circuit.AllBusVolts()))
df.bus  = [split(n, ".")[1] for n in df.node]
df.cond = [parse(Int, split(n, ".")[2]) for n in df.node]

# Keep phase conductors only, and drop anything above 1000 V,
# which removes the 11 kV primary side and leaves the LV feeder.
lv = filter(r -> r.cond in (1,2,3) && r.volts < 1000.0, df)

println("LV phase nodes: ", nrow(lv), " across ", length(unique(lv.bus)), " buses")
println()
println("Mean:    ", round(mean(lv.volts), digits=2), " V")
println("Std dev: ", round(std(lv.volts),  digits=2), " V")
println("Min:     ", round(minimum(lv.volts), digits=2), " V")
println("Max:     ", round(maximum(lv.volts), digits=2), " V")
println()
println("Nodes above 253 V: ", count(>(253.0), lv.volts), " of ", nrow(lv))


# --- Bus-level aggregation ----------------------------------
# Average the three phases at each bus FIRST, then take
# statistics across the 55 bus values. an earlier stage reported
# "across 55 buses", so this may be the matching definition.
bus_level = combine(groupby(lv, :bus), :volts => mean => :mean_v)

println()
println("--- Bus-level (", nrow(bus_level), " buses) ---")
println("Mean:    ", round(mean(bus_level.mean_v), digits=2), " V")
println("Std dev: ", round(std(bus_level.mean_v),  digits=2), " V")
println("Min:     ", round(minimum(bus_level.mean_v), digits=2), " V")
println("Max:     ", round(maximum(bus_level.mean_v), digits=2), " V")