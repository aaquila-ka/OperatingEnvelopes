# ============================================================
# pmd_02_testcase.jl
# Parse a small PMD test network and inspect its structure.
# Three buses, so everything can be checked by hand.
# ============================================================

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