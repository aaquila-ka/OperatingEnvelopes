# scripts/bmopf/validate_pf_vs_opendss.jl
#
# PURPOSE (Aim 1, part 2)
#   Check that the BMOPFTools power flow and OpenDSS give the same voltages on
#   the corrected LV3 network. Compared quantity: PHASE-TO-NEUTRAL magnitude
#   at every LV bus/phase, plus neutral-to-ground magnitude.
#   Only magnitudes are compared, because the two tools may use different
#   angle references across the Dyn transformer.
#
# HOW TO RUN (from C:\thesis\OperatingEnvelopes)
#   julia +1.11 --project=bmopf
#   julia> include("scripts/bmopf/validate_pf_vs_opendss.jl")
#
# OUTPUT
#   results/pf_validation_lv3.csv  (one row per bus/phase)

using BMOPFTools, JuMP, Ipopt, OpenDSSDirect, Printf

const ROOT = pwd()
include(joinpath(ROOT, "scripts", "bmopf", "load_lv3.jl"))   # builds corrected `net`

# ---------------------------------------------------------------- 1. BMOPF
quiet = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
pf = solve_pf(net; optimizer = quiet)
@assert string(pf["termination_status"]) == "LOCALLY_SOLVED" "BMOPF PF failed: $(pf["termination_status"])"
vbm(bus, t) = complex(pf["bus"][bus][t]["vr"], pf["bus"][bus][t]["vi"])

# ---------------------------------------------------------------- 2. OpenDSS
master = abspath(joinpath(ROOT, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
try
    # Known OpenDSSDirect bug: the first solve after clear+redirect reports
    # converged but leaves every voltage at zero. So load and solve twice.
    for _ in 1:2
        OpenDSSDirect.Text.Command("clear")
        OpenDSSDirect.Text.Command("redirect \"$master\"")
        OpenDSSDirect.Text.Command("set maxcontroliter=200")
        OpenDSSDirect.Solution.Solve()
    end
finally
    cd(ROOT)   # OpenDSS redirect can change the working folder; put it back
end
@assert OpenDSSDirect.Solution.Converged() "OpenDSS did not converge"
@assert maximum(abs.(OpenDSSDirect.Circuit.AllBusVolts())) > 0 "OpenDSS voltages all zero (warm-up bug)"

odss = Dict{String, Dict{Int, ComplexF64}}()
for name in OpenDSSDirect.Circuit.AllBusNames()
    OpenDSSDirect.Circuit.SetActiveBus(name)
    nodes = OpenDSSDirect.Bus.Nodes()
    volts = OpenDSSDirect.Bus.Voltages()
    @assert length(volts) == length(nodes) "unexpected OpenDSS voltage format at bus $name"
    odss[lowercase(name)] = Dict(n => ComplexF64(volts[i]) for (i, n) in enumerate(nodes))
end

# ---------------------------------------------------------------- 3. Compare
phase = Dict(1 => "a", 2 => "b", 3 => "c")
rows = Tuple{String, String, Float64, Float64, Float64}[]
for bus in sort(collect(keys(odss)))
    nd = odss[bus]
    haskey(nd, 4) || continue                     # only 4-wire buses (have a neutral)
    if !haskey(pf["bus"], bus)
        println("  note: bus $bus not in BMOPF result"); continue
    end
    for k in 1:3
        haskey(nd, k) || continue
        v_dss = abs(nd[k] - nd[4])
        v_bm  = abs(vbm(bus, phase[k]) - vbm(bus, "n"))
        push!(rows, (bus, phase[k] * "-n", v_dss, v_bm, v_bm - v_dss))
    end
    push!(rows, (bus, "n-g", abs(nd[4]), abs(vbm(bus, "n")), abs(vbm(bus, "n")) - abs(nd[4])))
end

pn = filter(r -> r[2] != "n-g", rows)
ng = filter(r -> r[2] == "n-g", rows)
summ(v) = (sum(v) / length(v), maximum(v))

println("\n==================== BMOPF vs OpenDSS (LV3, corrected) ====================")
@printf("Phase-to-neutral: %d bus/phase values compared\n", length(pn))
@printf("  OpenDSS range  %.2f to %.2f V\n", minimum(r[3] for r in pn), maximum(r[3] for r in pn))
@printf("  BMOPF   range  %.2f to %.2f V\n", minimum(r[4] for r in pn), maximum(r[4] for r in pn))
m, x = summ([abs(r[5]) for r in pn]); w = pn[argmax([abs(r[5]) for r in pn])]
@printf("  |difference|   mean %.4f V   max %.4f V   (worst: %s %s)\n", m, x, w[1], w[2])
@printf("Neutral-to-ground: %d buses\n", length(ng))
@printf("  OpenDSS range  %.3f to %.3f V\n", minimum(r[3] for r in ng), maximum(r[3] for r in ng))
@printf("  BMOPF   range  %.3f to %.3f V\n", minimum(r[4] for r in ng), maximum(r[4] for r in ng))
m2, x2 = summ([abs(r[5]) for r in ng])
@printf("  |difference|   mean %.4f V   max %.4f V\n", m2, x2)

open(joinpath(ROOT, "results", "pf_validation_lv3.csv"), "w") do io
    println(io, "bus,quantity,v_opendss_V,v_bmopf_V,diff_V")
    for r in rows
        @printf(io, "%s,%s,%.6f,%.6f,%.6f\n", r...)
    end
end
println("\nwritten results/pf_validation_lv3.csv")

# ---------------------------------------------------------------- 4. PV output (OpenDSS)
println("\nPV output in OpenDSS (kW exported, kvar):")
try
    i = OpenDSSDirect.PVsystems.First()
    while i > 0
        @printf("  %-16s %7.3f kW  %8.3f kvar\n", lowercase(OpenDSSDirect.PVsystems.Name()),
                OpenDSSDirect.PVsystems.kW(), OpenDSSDirect.PVsystems.kvar())
        i = OpenDSSDirect.PVsystems.Next()
    end
catch e
    println("  (could not read PV powers from OpenDSS: ", e, ")")
end
println("\nBMOPF result for PV ld1970_load_c:")
println(get(get(pf, "ibr", Dict()), "ld1970_load_c", "  (no 'ibr' section in result)"))