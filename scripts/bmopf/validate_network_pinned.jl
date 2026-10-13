# scripts/bmopf/validate_network_pinned.jl
#
# PURPOSE (Aim 1) – validation in two independent parts
#   (A) NETWORK PHYSICS: each BMOPF inverter is replaced by a fixed injection equal
#       to OpenDSS's PV output, so both tools solve the SAME determined problem.
#       Phase-to-neutral and neutral-to-ground magnitudes compared at all LV buses.
#   (B) INVERTER BEHAVIOUR: OpenDSS PV P and Q checked against the AS/NZS 4777.2 curves
#       evaluated at PHASE-TO-GROUND voltage (what OpenDSS InvControl monitors),
#       with the 5 kVA limit (reactive priority) applied to P.
#   Also prints OpenDSS load P/Q to confirm both tools use the same loads.
#
# OpenDSS side: Master.dss pu=1.00; Loads.dss kw=1 kvar=0.539743 (original CSIRO);
# PVSystems.dss has `Edit InvControl.invall VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6`
#
# RUN    julia> include("scripts/bmopf/validate_network_pinned.jl")
# OUTPUT results/pf_validation_lv3_pinned.csv

using BMOPFTools, JuMP, Ipopt, OpenDSSDirect, Printf

isdefined(Main, :load_lv3) || include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))

q_curve(V) = V <= 207 ? 0.44 : V <= 220 ? 0.44 * (220 - V) / 13 : V <= 240 ? 0.0 :
             V <= 258 ? -0.6 * (V - 240) / 18 : -0.6
p_curve(V) = V <= 253 ? 1.0 : V <= 260 ? 1.0 - 0.8 * (V - 253) / 7 : 0.2

function run_pinned_validation()
    root = pwd()
    net  = load_lv3()

    # ------------------------------------------------------------ OpenDSS solve
    master = abspath(joinpath(root, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
    try
        for _ in 1:2    # OpenDSSDirect warm-up bug: first solve leaves zeros
            OpenDSSDirect.Text.Command("clear")
            OpenDSSDirect.Text.Command("redirect \"$master\"")
            OpenDSSDirect.Text.Command("set maxcontroliter=200")
            OpenDSSDirect.Solution.Solve()
        end
    finally
        cd(root)
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

    # ------------------------------------------------------------ loads check
    println("\nLOADS: OpenDSS vs BMOPF (should all be 1.000 kW, 0.540 kvar)")
    k = OpenDSSDirect.Loads.First()
    while k > 0
        id = lowercase(OpenDSSDirect.Loads.Name())
        @printf("  %-16s OpenDSS %.3f kW %.3f kvar | BMOPF %.3f kW %.3f kvar\n", id,
                OpenDSSDirect.Loads.kW(), OpenDSSDirect.Loads.kvar(),
                net["load"][id]["p_nom"][1] / 1000, net["load"][id]["q_nom"][1] / 1000)
        k = OpenDSSDirect.Loads.Next()
    end

    pvout = Dict{String, Tuple{Float64, Float64}}()
    k = OpenDSSDirect.PVsystems.First()
    while k > 0
        pvout[lowercase(OpenDSSDirect.PVsystems.Name())] =
            (OpenDSSDirect.PVsystems.kW(), OpenDSSDirect.PVsystems.kvar())
        k = OpenDSSDirect.PVsystems.Next()
    end
    @assert length(pvout) == 12 "expected 12 PVs from OpenDSS, got $(length(pvout))"

    # ------------------------------------------------------------ (B) inverters
    phase_node = Dict("a" => 1, "b" => 2, "c" => 3)
    println("\n(B) OpenDSS inverters vs AS/NZS 4777.2 at PHASE-TO-GROUND voltage (5 kVA, 230 V base)")
    println("    PV                V_pg(V)  V_pn(V)   P_dss  P_expect   Q_dss  Q_expect")
    worstP, worstQ = 0.0, 0.0
    for id in sort(collect(keys(net["ibr"])))
        ibr = net["ibr"][id]
        bus = ibr["bus"]; ph = ibr["terminal_map"][1]
        nd  = odss[bus]
        Vpg = abs(nd[phase_node[ph]])
        Vpn = abs(nd[phase_node[ph]] - nd[4])
        qe  = 5 * q_curve(Vpg)
        pe  = min(5 * p_curve(Vpg), sqrt(max(25 - qe^2, 0.0)))   # Volt-Watt cap and 5 kVA limit
        kw, kvar = pvout[id]
        worstP = max(worstP, abs(kw - pe)); worstQ = max(worstQ, abs(kvar - qe))
        @printf("    %-16s %8.2f %8.2f  %6.3f  %8.3f  %7.3f  %7.3f\n", id, Vpg, Vpn, kw, pe, kvar, qe)
    end
    @printf("    worst |P_dss - P_expect| = %.3f kW, worst |Q_dss - Q_expect| = %.3f kvar\n", worstP, worstQ)

    # ------------------------------------------------------------ (A) network physics
    for (id, ibr) in collect(net["ibr"])
        kw, kvar = pvout[id]
        net["load"]["pvfixed_" * id] = Dict{String, Any}(
            "bus" => ibr["bus"], "terminal_map" => copy(ibr["terminal_map"]),
            "configuration" => "SINGLE_PHASE", "model" => "constant_power",
            "p_nom" => Any[-1000 * kw], "q_nom" => Any[-1000 * kvar], "v_nom" => Any[230.0])
    end
    empty!(net["ibr"])

    quiet = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
    pf = solve_pf(net; optimizer = quiet)
        # ---- loss breakdown (diagnosis of the 7 % loss gap, 13 Oct 2026; field names checked in BMOPFTools b7aa9a1)
    let
        svc = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
        vbus(b, t) = (tb = get(get(pf["bus"], b, Dict()), t, nothing);
                      tb === nothing ? 0.0 + 0.0im : complex(get(tb, "vr", 0.0), get(tb, "vi", 0.0)))
        p_svc = 0.0; p_main = 0.0; p_tx = 0.0; p_sh = 0.0; p_sw = 0.0
        for (lid, lr) in get(pf, "line", Dict())
            pl = get(get(lr, "loss", Dict()), "p_loss", 0.0)
            lc = get(get(get(net, "line", Dict()), lid, Dict()), "linecode", "")
            lc == svc ? (p_svc += pl) : (p_main += pl)
        end
        for (tid, tr) in get(pf, "transformer", Dict())
            tr isa Dict || continue
            p_tx += get(get(tr, "loss", Dict()), "p_loss", 0.0)
        end
        for (sid, sh) in get(net, "shunt", Dict())
            sh isa Dict || continue
            b = String(get(sh, "bus", "")); tm = String.(get(sh, "terminal_map", String[]))
            G = BMOPFTools._pattern_keys_to_matrix(sh, "G_"); B = BMOPFTools._pattern_keys_to_matrix(sh, "B_")
            n = length(tm); n == 0 && continue
            Y = (G === nothing ? zeros(n, n) : G[1:n, 1:n]) .+ im .* (B === nothing ? zeros(n, n) : B[1:n, 1:n])
            V = [vbus(b, t) for t in tm]
            p_sh += real(sum(V .* conj.(Y * V)))
        end
        for (sid, sr) in get(pf, "switch", Dict())
            for (t, c) in sr
                c isa Dict && (p_sw += 1e-3 * get(c, "cm", 0.0)^2)
            end
        end
        @printf("BMOPF p_loss (reported)          %8.2f W\n", get(get(pf, "losses", Dict()), "p_loss", NaN))
        @printf("  lines: service 16 mm2         %8.2f W\n", p_svc)
        @printf("  lines: mains                  %8.2f W\n", p_main)
        @printf("  transformers                  %8.2f W\n", p_tx)
        @printf("NOT in p_loss: earthing shunts  %8.2f W\n", p_sh)
        @printf("NOT modelled: switches 1 mOhm   %8.2f W   (OpenDSS switch=y)\n", p_sw)
        @printf("p_loss + shunts + switches      %8.2f W   (compare with the OpenDSS losses above)\n",
                get(get(pf, "losses", Dict()), "p_loss", 0.0) + p_sh + p_sw)
        @printf("switches imported: %d\n", length(get(net, "switch", Dict())))
    end
    @assert string(pf["termination_status"]) == "LOCALLY_SOLVED" "BMOPF PF failed: $(pf["termination_status"])"
    vbm(b, t) = complex(pf["bus"][b][t]["vr"], pf["bus"][b][t]["vi"])

    rows = Tuple{String, String, Float64, Float64, Float64}[]
    for bus in sort(collect(keys(odss)))
        nd = odss[bus]
        (haskey(nd, 4) && haskey(nd, 1)) || continue
        abs(nd[1] - nd[4]) > 1000 && continue                  # skip MV buses
        haskey(pf["bus"], bus) || continue
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
    w   = pn[argmax(dpn)]

    println("\n(A) NETWORK PHYSICS – BMOPF (injections pinned to OpenDSS) vs OpenDSS, LV buses only")
    @printf("  Phase-to-neutral: %d values   OpenDSS %.2f–%.2f V   BMOPF %.2f–%.2f V\n",
            length(pn), minimum(r[3] for r in pn), maximum(r[3] for r in pn),
            minimum(r[4] for r in pn), maximum(r[4] for r in pn))
    @printf("    |difference| mean %.4f V   max %.4f V   (worst %s %s)\n",
            sum(dpn) / length(dpn), maximum(dpn), w[1], w[2])
    @printf("  Neutral-to-ground: %d buses   OpenDSS max %.3f V   BMOPF max %.3f V\n",
            length(ng), maximum(r[3] for r in ng), maximum(r[4] for r in ng))
    @printf("    |difference| mean %.4f V   max %.4f V\n", sum(dng) / length(dng), maximum(dng))
    @printf("  Losses: OpenDSS %.1f W   BMOPF %.1f W\n", real(OpenDSSDirect.Circuit.Losses()[1]), pf["losses"]["p_loss"])

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