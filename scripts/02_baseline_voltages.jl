# ============================================================
# 02_baseline_voltages.jl
# Regression check against Semester 1: mean 260.91 V, sd 0.39 V
#
# NOTE: OpenDSSDirect requires a WARM-UP solve. The first solve
# after a fresh Clear/Redirect reports Converged() == true but
# leaves every bus voltage at zero. A throwaway solve followed
# by a full reload is required. Confirmed 20 Aug 2026 on
# OpenDSSDirect v0.9.9 / Julia 1.9.4, and independently in
# Semester 1.
# ============================================================

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
# statistics across the 55 bus values. Semester 1 reported
# "across 55 buses", so this may be the matching definition.
bus_level = combine(groupby(lv, :bus), :volts => mean => :mean_v)

println()
println("--- Bus-level (", nrow(bus_level), " buses) ---")
println("Mean:    ", round(mean(bus_level.mean_v), digits=2), " V")
println("Std dev: ", round(std(bus_level.mean_v),  digits=2), " V")
println("Min:     ", round(minimum(bus_level.mean_v), digits=2), " V")
println("Max:     ", round(maximum(bus_level.mean_v), digits=2), " V")