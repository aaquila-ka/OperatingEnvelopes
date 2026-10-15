# =============================================================================
# validate_pf_vs_opendss.jl: BMOPFTools power flow vs OpenDSS on LV3, each tool with its own
#                            inverter controls (not pinned)
#
# What it does (plain English): (thesis Aim 1, part 2)
#   Checks that the BMOPFTools power flow and OpenDSS give the same voltages on the corrected
#   LV3 network. Compared quantity: PHASE-TO-NEUTRAL magnitude at every LV bus/phase, plus
#   neutral-to-ground magnitude. Only magnitudes are compared, because the two tools may use
#   different angle references across the Dyn transformer. Here each tool runs its own
#   inverter settings, but the BMOPFTools power flow does not fix inverter P (Volt-Watt is a
#   cap) and returns Q = 0, so the inverter outputs differ between the tools and so do the
#   voltages (up to 2.07 V on the current model). This is NOT a network-model validation;
#   use validate_network_pinned.jl for that (0.103 V). Also prints the OpenDSS PV outputs.
#
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss (OpenDSS); includes load_lv3.jl, which
#           builds the corrected `net` (BMOPFTools).
# Outputs:  results/pf_validation_lv3.csv (one row per bus/phase); prints a summary.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/validate_pf_vs_opendss.jl")       (runs on include)
# Used for: REPRODUCE.md step 34 and known issue 25 (why the unpinned test is not
#           like-for-like); the validation numbers quoted come from
#           validate_network_pinned.jl (step 2).
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl by Frederik Geth; OpenDSS (EPRI)
#           via OpenDSSDirect.jl; Ipopt.
# =============================================================================

using BMOPFTools, JuMP, Ipopt, OpenDSSDirect, Printf

# Remember the repo folder (OpenDSS may change the working folder)
const ROOT = pwd()
include(joinpath(ROOT, "scripts", "bmopf", "load_lv3.jl"))   # builds corrected `net`

# ---------------------------------------------------------------- 1. BMOPF
# Run the BMOPFTools power flow on the LV3 network quietly (Ipopt print level 0) and stop if it fails
quiet = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
pf = solve_pf(net; optimizer = quiet)
@assert string(pf["termination_status"]) == "LOCALLY_SOLVED" "BMOPF PF failed: $(pf["termination_status"])"
# Short helper: complex voltage of one bus terminal ("a", "b", "c" or "n") from the BMOPF result
vbm(bus, t) = complex(pf["bus"][bus][t]["vr"], pf["bus"][bus][t]["vi"])

# ---------------------------------------------------------------- 2. OpenDSS
# OpenDSS: load the same LV3 network from Master.dss and solve it with its own inverter controls
master = abspath(joinpath(ROOT, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
try
    # Observed in this setup: the first solve after clear+redirect reports
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
# Stop if OpenDSS did not converge or gave all-zero voltages
@assert OpenDSSDirect.Solution.Converged() "OpenDSS did not converge"
@assert maximum(abs.(OpenDSSDirect.Circuit.AllBusVolts())) > 0 "OpenDSS voltages all zero (warm-up bug)"

# Save the OpenDSS complex voltage of every bus, by node number (1 = a, 2 = b, 3 = c, 4 = neutral), bus names in lower case
odss = Dict{String, Dict{Int, ComplexF64}}()
for name in OpenDSSDirect.Circuit.AllBusNames()
    OpenDSSDirect.Circuit.SetActiveBus(name)
    nodes = OpenDSSDirect.Bus.Nodes()
    volts = OpenDSSDirect.Bus.Voltages()
    @assert length(volts) == length(nodes) "unexpected OpenDSS voltage format at bus $name"
    odss[lowercase(name)] = Dict(n => ComplexF64(volts[i]) for (i, n) in enumerate(nodes))
end

# ---------------------------------------------------------------- 3. Compare
# Compare every phase-to-neutral voltage (what a home feels) and every neutral-to-ground voltage;
# each row = (bus, quantity, OpenDSS V, BMOPF V, BMOPF - OpenDSS)
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
        # Phase-to-neutral magnitude in each tool: |V(phase) - V(neutral)|
        v_dss = abs(nd[k] - nd[4])
        v_bm  = abs(vbm(bus, phase[k]) - vbm(bus, "n"))
        push!(rows, (bus, phase[k] * "-n", v_dss, v_bm, v_bm - v_dss))
    end
    # Neutral-to-ground magnitude = |V(neutral)| in each tool
    push!(rows, (bus, "n-g", abs(nd[4]), abs(vbm(bus, "n")), abs(vbm(bus, "n")) - abs(nd[4])))
end

# Split the rows into phase-to-neutral and neutral-to-ground, and a helper for (mean, max)
pn = filter(r -> r[2] != "n-g", rows)
ng = filter(r -> r[2] == "n-g", rows)
summ(v) = (sum(v) / length(v), maximum(v))

println("\n==================== BMOPF vs OpenDSS (LV3, corrected) ====================")
@printf("Phase-to-neutral: %d bus/phase values compared\n", length(pn))
@printf("  OpenDSS range  %.2f to %.2f V\n", minimum(r[3] for r in pn), maximum(r[3] for r in pn))
@printf("  BMOPF   range  %.2f to %.2f V\n", minimum(r[4] for r in pn), maximum(r[4] for r in pn))
# Mean and largest absolute difference, and the bus/phase with the largest one
m, x = summ([abs(r[5]) for r in pn]); w = pn[argmax([abs(r[5]) for r in pn])]
@printf("  |difference|   mean %.4f V   max %.4f V   (worst: %s %s)\n", m, x, w[1], w[2])
@printf("Neutral-to-ground: %d buses\n", length(ng))
@printf("  OpenDSS range  %.3f to %.3f V\n", minimum(r[3] for r in ng), maximum(r[3] for r in ng))
@printf("  BMOPF   range  %.3f to %.3f V\n", minimum(r[4] for r in ng), maximum(r[4] for r in ng))
m2, x2 = summ([abs(r[5]) for r in ng])
@printf("  |difference|   mean %.4f V   max %.4f V\n", m2, x2)

# One CSV row per bus/phase (and per bus for n-g)
open(joinpath(ROOT, "results", "pf_validation_lv3.csv"), "w") do io
    println(io, "bus,quantity,v_opendss_V,v_bmopf_V,diff_V")
    for r in rows
        @printf(io, "%s,%s,%.6f,%.6f,%.6f\n", r...)
    end
end
println("\nwritten results/pf_validation_lv3.csv")

# ---------------------------------------------------------------- 4. PV output (OpenDSS)
# For information: what each PV gives in OpenDSS (kW and kvar), and BMOPF's result for one PV
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