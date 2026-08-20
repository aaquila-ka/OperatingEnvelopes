# ============================================================
# pmd_04_compare_opendss.jl
# Solve the SAME network in both PMD and OpenDSS, compare.
#
# Two independent tools on identical input should agree.
# If they do not, one of them is being driven incorrectly,
# and it is better to find that out on a 3-bus network.
# ============================================================

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