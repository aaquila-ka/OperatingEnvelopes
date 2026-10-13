# scripts/bmopf/validate_network_pinned.jl
#
# PURPOSE (Aim 1, final check) – split validation into two independent tests
#   (A) NETWORK PHYSICS: each BMOPF inverter is replaced by a fixed injection
#       equal to OpenDSS's PV output, so both tools solve the SAME determined
#       problem. Phase-to-neutral and neutral-to-ground magnitudes compared.
#   (B) INVERTER BEHAVIOUR: OpenDSS's PV P and Q are checked against the
#       AS/NZS 4777.2 curve evaluated at OpenDSS's own phase-to-neutral voltage.
#
# WHY NOT solve_pf WITH DROOP (BMOPFTools b7aa9a1, ext/BMOPFOpfExt/ibr.jl):
#   - Volt-Watt is a cap (P <= cap, line 693): in a power flow P is not
#     determined, so any P in [0, cap] solves.
#   - Volt-VAr is Q == s_max * f(U) (lines 336, 703). solve_pf returned Q = 0
#     exactly, consistent with s_max being stripped from the PF working copy.
#     (Open question for F. Geth.)
#
# HOW TO RUN (from C:\thesis\OperatingEnvelopes, Julia started with --project=bmopf)
#   julia> include("scripts/bmopf/validate_network_pinned.jl")
#
# OUTPUT
#   results/pf_validation_lv3_pinned.csv
#
# Everything runs inside one function so no variable can clash with variables
# already defined in the REPL session.

using BMOPFTools, JuMP, Ipopt, OpenDSSDirect, Printf

include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))   # defines load_lv3()

# AS/NZS 4777.2 Australia A curves on a 230 V base, as fractions of 5 kVA / 5 kW
q_curve(V) = V <= 207 ? 0.44 : V <= 220 ? 0.44 * (220 - V) / 13 : V <= 240 ? 0.0 :
             V <= 258 ? -0.6 * (V - 240) / 18 : -0.6
p_curve(V) = V <= 253 ? 1.0 : V <= 260 ? 1.0 - 0.8 * (V - 253) / 7 : 0.2

function run_pinned_validation()
    root = pwd()
    net  = load_lv3()                                   # fresh corrected network

    # -------------------------------------------------------- 1. OpenDSS solve
    master = abspath(joinpath(root, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
    try
        for _ in 1:2    # OpenDSSDirect warm-up bug: first solve leaves zeros
            OpenDSSDirect.Text.Command("clear")
            OpenDSSDirect.Text.Command("redirect \"$master\"")
            OpenDSSDirect.Text.Command("set maxcontroliter=200")
            OpenDSSDirect.Solution.Solve()
        end
    finally
        cd(root)        # OpenDSS redirect can change the working folder
    end
    @assert OpenDSSDirect.Solution.Converged() "OpenDSS did not converge"
    @assert maximum(abs.(OpenDSSDirect.Circuit.AllBusVolts())) > 0 "OpenDSS voltages all zero"

    odss = Dict{String, Dict{Int, ComplexF64}}()
    for name in OpenDSSDirect.Circuit.AllBusNames()
        OpenDSSDirect.Circuit.SetActiveBus(name)
        nodes = OpenDSSDirect.Bus.Nodes()
        volts = OpenDSSDirect.Bus.Voltages()
        @assert length(volts) == length(nodes) "unexpected OpenDSS voltage format at bus $name"
        odss[lowercase(name)] = Dict(n => ComplexF64(volts[j]) for (j, n) in enumerate(nodes))
    end

    pvout = Dict{String, Tuple{Float64, Float64}}()     # id => (kW, kvar), generator convention
    k = OpenDSSDirect.PVsystems.First()
    while k > 0
        pvout[lowercase(OpenDSSDirect.PVsystems.Name())] =
            (OpenDSSDirect.PVsystems.kW(), OpenDSSDirect.PVsystems.kvar())
        k = OpenDSSDirect.PVsystems.Next()
    end
    @assert length(pvout) == 12 "expected 12 PVs from OpenDSS, got $(length(pvout))"

    # ------------------------------------------- 2. (B) inverter vs standard
    phase_node = Dict("a" => 1, "b" => 2, "c" => 3)
    println("\n(B) OpenDSS inverters vs AS/NZS 4777.2 curve (5 kVA, 230 V base)")
    println("    PV                V_pn(V)   P_dss  P_curve(cap)   Q_dss  Q_curve")
    for id in sort(collect(keys(net["ibr"])))
        ibr = net["ibr"][id]
        bus = ibr["bus"]; ph = ibr["terminal_map"][1]
        nd  = odss[bus]
        V   = abs(nd[phase_node[ph]] - nd[4])
        kw, kvar = pvout[id]
        @printf("    %-16s %8.2f  %6.3f  %8.3f      %7.3f  %7.3f\n",
                id, V, kw, 5 * p_curve(V), kvar, 5 * q_curve(V))
    end

    # ---------------------------- 3. (A) pin BMOPF injections to OpenDSS output
    for (id, ibr) in collect(net["ibr"])
        kw, kvar = pvout[id]
        net["load"]["pvfixed_" * id] = Dict{String, Any}(
            "bus" => ibr["bus"], "terminal_map" => copy(ibr["terminal_map"]),
            "configuration" => "SINGLE_PHASE", "model" => "constant_power",
            # load convention = minus generator convention
            "p_nom" => Any[-1000 * kw], "q_nom" => Any[-1000 * kvar], "v_nom" => Any[230.0])
    end
    empty!(net["ibr"])

    quiet = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
    pf = solve_pf(net; optimizer = quiet)
    @assert string(pf["termination_status"]) == "LOCALLY_SOLVED" "BMOPF PF failed: $(pf["termination_status"])"
    vbm(b, t) = complex(pf["bus"][b][t]["vr"], pf["bus"][b][t]["vi"])

    rows = Tuple{String, String, Float64, Float64, Float64}[]
    for bus in sort(collect(keys(odss)))
        nd = odss[bus]
        (haskey(nd, 4) && haskey(nd, 1)) || continue
        abs(nd[1] - nd[4]) > 1000 && continue              # skip MV buses
        if !haskey(pf["bus"], bus)
            println("  note: $bus not in BMOPF"); continue
        end
        for (n, t) in ((1, "a"), (2, "b"), (3, "c"))
            haskey(nd, n) || continue
            vd = abs(nd[n] - nd[4])
            vb = abs(vbm(bus, t) - vbm(bus, "n"))
            push!(rows, (bus, t * "-n", vd, vb, vb - vd))
        end
        push!(rows, (bus, "n-g", abs(nd[4]), abs(vbm(bus, "n")), abs(vbm(bus, "n")) - abs(nd[4])))
    end
    pn  = filter(r -> r[2] != "n-g", rows)
    ng  = filter(r -> r[2] == "n-g", rows)
    dpn = [abs(r[5]) for r in pn]
    dng = [abs(r[5]) for r in ng]

    println("\n(A) NETWORK PHYSICS – BMOPF (injections pinned to OpenDSS) vs OpenDSS, LV buses only")
    @printf("  Phase-to-neutral: %d values   OpenDSS %.2f–%.2f V   BMOPF %.2f–%.2f V\n",
            length(pn), minimum(r[3] for r in pn), maximum(r[3] for r in pn),
            minimum(r[4] for r in pn), maximum(r[4] for r in pn))
    w = pn[argmax(dpn)]
    @printf("    |difference| mean %.4f V   max %.4f V   (worst %s %s)\n",
            sum(dpn) / length(dpn), maximum(dpn), w[1], w[2])
    @printf("  Neutral-to-ground: %d buses   OpenDSS max %.3f V   BMOPF max %.3f V\n",
            length(ng), maximum(r[3] for r in ng), maximum(r[4] for r in ng))
    @printf("    |difference| mean %.4f V   max %.4f V\n", sum(dng) / length(dng), maximum(dng))

    try
        @printf("  OpenDSS total losses: %.1f W\n", real(OpenDSSDirect.Circuit.Losses()[1]))
    catch
        println("  (OpenDSS losses not available)")
    end
    try
        @printf("  BMOPF   total losses: %.1f W\n", pf["losses"]["p_loss"])
    catch
        println("  (BMOPF losses not available in result)")
    end

    open(joinpath(root, "results", "pf_validation_lv3_pinned.csv"), "w") do io
        println(io, "bus,quantity,v_opendss_V,v_bmopf_V,diff_V")
        for r in rows
            @printf(io, "%s,%s,%.6f,%.6f,%.6f\n", r...)
        end
    end
    println("\nwritten results/pf_validation_lv3_pinned.csv")
    return nothing
end

run_pinned_validation()