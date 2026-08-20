# ============================================================
# pmd_03_powerflow.jl
# Task 3: solve a power flow in PMD on the 3-bus test network.
#
# OpenDSS solves power flow with its own built-in method.
# PMD does NOT have one. It writes the power flow equations
# as a mathematical problem and hands them to a solver.
# That solver is Ipopt.
# ============================================================

using PowerModelsDistribution   # network modelling and formulations
using Ipopt                     # the numerical solver that does the work

# --- Find PMD's own test network -----------------------------
# pkgdir() returns the folder where a package is installed.
testdir = joinpath(pkgdir(PowerModelsDistribution), "test", "data", "opendss")
case = joinpath(testdir, "case3_unbalanced.dss")

# --- Read the network into the ENGINEERING model -------------
# parse_file reads the .dss text and builds a Julia dictionary.
eng = parse_file(case)

# --- Solve the power flow ------------------------------------
# Three arguments:
#   eng                -> the network
#   ACPUPowerModel     -> which set of equations to use (see below)
#   Ipopt.Optimizer    -> which solver to hand them to
result = solve_mc_pf(eng, ACPUPowerModel, Ipopt.Optimizer)

# --- Did it work? --------------------------------------------
# LOCALLY_SOLVED means Ipopt found a solution.
println()
println("Status:     ", result["termination_status"])
println("Solve time: ", round(result["solve_time"], digits=3), " s")

# --- What came back? -----------------------------------------
# result["solution"] holds the computed values, organised by
# component type, mirroring the input structure.
println()
println("Solution contains:")
for k in sort(collect(keys(result["solution"])))
    v = result["solution"][k]
    println("  ", rpad(k, 20), v isa Dict ? length(v) : v)
end

# --- Look at the bus voltages --------------------------------
# "vm" = voltage magnitude, one value per terminal at each bus.
# These are in PER UNIT, not volts. More on that below.
println()
println("Bus voltage magnitudes (per unit):")
for (name, bus) in result["solution"]["bus"]
    if haskey(bus, "vm")                      # some buses may lack it
        println("  ", rpad(name, 12), round.(bus["vm"], digits=4))
    end
end