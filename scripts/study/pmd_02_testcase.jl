# =============================================================================
# pmd_02_testcase.jl: parse a small PowerModelsDistribution test network and inspect it
#
# What it does (plain English): reads PMD's own 3-bus test network
#   (case3_unbalanced.dss, shipped inside the PMD package) into PMD's
#   "engineering" data dictionary and prints its keys, one bus, one line and
#   the 4/0quad line code. Three buses, so everything can be checked by hand.
# Inputs:   <PMD package folder>/test/data/opendss/case3_unbalanced.dss
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; the older
#   top-level PowerModelsDistribution project, not bmopf/):
#   include("scripts/study/pmd_02_testcase.jl")
# Used for: learning PMD (study exercise), not used for thesis results
# Credits:  PowerModelsDistribution.jl (PMD) and its test network case3_unbalanced.dss
# =============================================================================

using PowerModelsDistribution

testdir = joinpath(pkgdir(PowerModelsDistribution), "test", "data", "opendss")
eng = parse_file(joinpath(testdir, "case3_unbalanced.dss"))

println("Type: ", typeof(eng))
println()
println("Keys and counts:")
for k in sort(collect(keys(eng)))
    v = eng[k]
    println("  ", rpad(k, 20), v isa Dict ? length(v) : v)
end

println()
println("--- one bus ---")
bus_name = first(keys(eng["bus"]))
println("name: ", bus_name)
for (k, v) in eng["bus"][bus_name]
    println("  ", rpad(k, 20), v)
end

println()
println("--- one line ---")
line_name = first(keys(eng["line"]))
println("name: ", line_name)
for (k, v) in eng["line"][line_name]
    println("  ", rpad(k, 20), v)
end

println("--- linecode ---")
for (k, v) in eng["linecode"]["4/0quad"]
    println("  ", rpad(k, 20), v)
end