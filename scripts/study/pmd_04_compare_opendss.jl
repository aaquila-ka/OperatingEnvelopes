# =============================================================================
# pmd_04_compare_opendss.jl: solve the same 3-bus network in PMD and OpenDSS and compare
#
# What it does (plain English): solves PMD's 3-bus test network
#   (case3_unbalanced.dss) once with PowerModelsDistribution + Ipopt and once
#   with OpenDSS (with the warm-up solve), and prints the voltage magnitudes
#   of each bus side by side in volts (phase-to-ground).
#   Two independent tools on identical input should agree. If they do not,
#   one of them is being driven incorrectly, and it is better to find that
#   out on a 3-bus network.
#   The two lists are printed per bus as returned by each tool; they are not
#   matched terminal by terminal, so a bus can show a different number of
#   entries in each column (e.g. if one tool lists a grounded terminal).
# Inputs:   <PMD package folder>/test/data/opendss/case3_unbalanced.dss
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; the older
#   top-level PowerModelsDistribution project, not bmopf/):
#   include("scripts/study/pmd_04_compare_opendss.jl")
# Used for: learning PMD (study exercise), not used for thesis results
# Credits:  PowerModelsDistribution.jl (PMD) and its test network
#   case3_unbalanced.dss; Ipopt (via Ipopt.jl); OpenDSS (EPRI) via OpenDSSDirect.jl
# =============================================================================

using PowerModelsDistribution
using Ipopt
using OpenDSSDirect

# Locate PMD's test network (used by BOTH tools below)
testdir = joinpath(pkgdir(PowerModelsDistribution), "test", "data", "opendss")
case = joinpath(testdir, "case3_unbalanced.dss")

# ---------- PMD ----------------------------------------------
eng = parse_file(case)                                    # read network
res = solve_mc_pf(eng, ACPUPowerModel, Ipopt.Optimizer)   # solve

# Pull voltages out, converting kV -> V
pmd_v = Dict{String,Vector{Float64}}()                    # empty container
for (name, bus) in res["solution"]["bus"]                 # loop over buses
    haskey(bus, "vm") && (pmd_v[name] = bus["vm"] .* 1000)  # .* means
end                                                       # multiply each element

# ---------- OpenDSS ------------------------------------------
# Warm-up solve first (the zero-voltage workaround)
dss("Clear"); dss("Redirect \"$case\""); Solution.Solve()
dss("Clear"); dss("Redirect \"$case\""); Solution.Solve()

# Build a lookup of bus -> voltages from the flat node list
odss_v = Dict{String,Vector{Float64}}()
names_ = Circuit.AllNodeNames()          # e.g. "loadbus.1"
volts_ = abs.(Circuit.AllBusVolts())     # magnitude of each
for (n, v) in zip(names_, volts_)        # zip pairs them up
    bus = split(n, ".")[1]               # text before the dot
    push!(get!(odss_v, bus, Float64[]), v)  # append to that bus's list
end

# ---------- Compare ------------------------------------------
println()
println(rpad("Bus", 12), rpad("PMD (V)", 30), "OpenDSS (V)")
for bus in sort(collect(keys(pmd_v)))
    p = round.(pmd_v[bus], digits=2)
    o = round.(get(odss_v, bus, Float64[]), digits=2)
    println(rpad(bus, 12), rpad(string(p), 30), o)
end