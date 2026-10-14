# =============================================================================
# 03_diagnose_zero_volts.jl: diagnose why OpenDSS bus voltages came back as zero
#
# What it does (plain English): loads LV3 three different ways (single solve,
#   second solve on the same circuit, warm-up solve then reload) and after each
#   prints the convergence flag, iteration count, total power and how many
#   node voltages are non-zero. Finally it reads one bus (b804, the 11 kV side
#   of the transformer) directly, as a second way of reading voltages.
#   This is the test behind the "warm-up solve" used in scripts 02-05,
#   count_linecodes.jl and sensitivity_service_cable.jl.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/03_diagnose_zero_volts.jl")
# Used for: early exploration (OpenDSSDirect troubleshooting), not used for thesis results
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
# =============================================================================

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