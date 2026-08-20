# ============================================================
# 03_diagnose_zero_volts.jl
# Purpose: find out WHY bus voltages come back as zero.
#          Tests the warm-up hypothesis and inspects solver
#          state directly.
# ============================================================

using OpenDSSDirect

network_dir = joinpath(@__DIR__, "..", "data", "networks", "LV3_55bus_withPV")
master_file = joinpath(network_dir, "Master.dss")

function report(label)
    println("--- ", label, " ---")
    println("  Converged:   ", Solution.Converged())
    println("  Iterations:  ", Solution.Iterations())
    println("  TotalPower:  ", Circuit.TotalPower())
    v = abs.(Circuit.AllBusVolts())
    println("  Max |V|:     ", maximum(v))
    println("  Nonzero:     ", count(x -> x > 1e-6, v), " of ", length(v))
    println()
end

# --- Attempt 1: single solve, as before ---------------------
dss("Clear")
dss("Redirect \"$master_file\"")
Solution.Solve()
report("Attempt 1 (single solve)")

# --- Attempt 2: solve again without reloading ---------------
Solution.Solve()
report("Attempt 2 (second solve, same circuit)")

# --- Attempt 3: full reload with warm-up --------------------
dss("Clear")
dss("Redirect \"$master_file\"")
Solution.Solve()          # throwaway
dss("Clear")
dss("Redirect \"$master_file\"")
Solution.Solve()          # the real one
report("Attempt 3 (warm-up then reload)")

# --- Ask OpenDSS directly for one bus -----------------------
# Different code path from AllBusVolts. If this works and
# AllBusVolts does not, the problem is in how we are reading,
# not in the solve.
Circuit.SetActiveBus("b804")
println("Direct read of b804:")
println("  puVmagAngle: ", Bus.puVMagAngle())
println("  VMagAngle:   ", Bus.VMagAngle())