# =============================================================================
# pmd_03_powerflow.jl: solve a power flow in PowerModelsDistribution on a 3-bus test network
#
# What it does (plain English): solves an unbalanced AC power flow on PMD's
#   3-bus test network (case3_unbalanced.dss) and prints the solver status,
#   solve time, what the solution contains and the bus voltage magnitudes.
#   OpenDSS solves power flow with its own built-in method. PMD (in this
#   usage) writes the power flow equations as a mathematical problem and
#   hands them to a solver, here Ipopt.
# Inputs:   <PMD package folder>/test/data/opendss/case3_unbalanced.dss
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; the older
#   top-level PowerModelsDistribution project, not bmopf/):
#   include("scripts/study/pmd_03_powerflow.jl")
# Used for: learning PMD (study exercise), not used for thesis results
# Credits:  PowerModelsDistribution.jl (PMD) and its test network
#   case3_unbalanced.dss; Ipopt (via Ipopt.jl)
# =============================================================================

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
# Units: when the input is an engineering model, PMD by default converts the
# solution back to engineering units (make_si = true), so vm is expected in
# kV, not per unit; pmd_04_compare_opendss.jl multiplies it by 1000 to get
# volts. The label printed below says "per unit": check the printed values
# (about 0.23 means kV phase-to-ground on this 0.4 kV case, about 1.0 would
# mean per unit).
println()
println("Bus voltage magnitudes (per unit):")
for (name, bus) in result["solution"]["bus"]
    if haskey(bus, "vm")                      # some buses may lack it
        println("  ", rpad(name, 12), round.(bus["vm"], digits=4))
    end
end