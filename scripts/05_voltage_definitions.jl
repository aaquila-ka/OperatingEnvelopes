# ============================================================
# 05_voltage_definitions.jl
# Solves LV3_55bus_withPV and reports bus voltages TWO ways:
#   phase-to-ground  = |V_phase|
#   phase-to-neutral = |V_phase - V_neutral|
# On a four-wire model these differ, because the neutral
# conductor carries current and is not at earth potential.
# ============================================================

using OpenDSSDirect, DataFrames, Statistics

net = joinpath(@__DIR__, "..", "data", "networks", "LV3_55bus_withPV")
master = joinpath(net, "Master.dss")

# Warm-up solve required: the first solve after Clear/Redirect
# reports converged but leaves all voltages at zero.
dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()
dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()
@assert Solution.Converged()
@assert maximum(abs.(Circuit.AllBusVolts())) > 1e-6 "voltages all zero"

df = DataFrame(node = Circuit.AllNodeNames(), v = Circuit.AllBusVolts())
df.bus  = [split(n, ".")[1] for n in df.node]
df.cond = [parse(Int, split(n, ".")[2]) for n in df.node]

# LV only: drop the 11 kV primary side
lv_buses = unique(filter(r -> r.cond == 1 && abs(r.v) < 1000, df).bus)
df = filter(r -> r.bus in lv_buses, df)

pg = Float64[]      # phase-to-ground
pn = Float64[]      # phase-to-neutral
neutrals = Float64[]

for g in groupby(df, :bus)
    nrow_n = findfirst(==(4), g.cond)
    nrow_n === nothing && continue
    vn = g.v[nrow_n]                 # complex neutral voltage
    push!(neutrals, abs(vn))
    for i in 1:nrow(g)
        if g.cond[i] in (1, 2, 3)
            push!(pg, abs(g.v[i]))        # vs ground
            push!(pn, abs(g.v[i] - vn))   # vs neutral, as phasors
        end
    end
end

for (label, v) in (("PHASE-TO-GROUND", pg), ("PHASE-TO-NEUTRAL", pn))
    println()
    println("--- ", label, " (n = ", length(v), ") ---")
    println("  Mean: ", round(mean(v), digits=2), "   Sd: ", round(std(v), digits=2))
    println("  Min:  ", round(minimum(v), digits=2), "   Max: ", round(maximum(v), digits=2))
    println("  Above 253 V: ", count(>(253.0), v), " of ", length(v))
end

println()
println("Neutral magnitude across ", length(neutrals), " buses: ",
        round(minimum(neutrals), digits=2), " to ",
        round(maximum(neutrals), digits=2), " V (mean ",
        round(mean(neutrals), digits=2), " V)")