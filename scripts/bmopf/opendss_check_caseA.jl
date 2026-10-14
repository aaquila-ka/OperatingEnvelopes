# =============================================================================
# opendss_check_caseA.jl: independent OpenDSS check of the Case A bound-point voltage
#
# What it does (plain English):
#   True street: the 22 service segments are 4 mm2 (uglv_4cu) instead of 16 mm2. Source
#   1.03 pu, original CSIRO loads (1 kW each). Every PV exports the over-promised 4.529 kW
#   (the DOE issued from the wrong records). Volt-Watt switched off (flat curve); Volt-VAr
#   unchanged in var (kvarMax = 5); inverter size relaxed (kVA = 100) so P is not cut ->
#   same setup as the BMOPF bound-point counterfactual. Also runs 0 kW export in both tools as
#   a check that the cable swap is applied identically. Prints the highest customer
#   phase-to-neutral voltage from both tools and their difference.
#   Note: OpenDSS InvControl senses PHASE-TO-GROUND voltage, BMOPF uses PHASE-TO-NEUTRAL, so
#   Volt-VAr Q differs slightly between the tools.
#
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss (OpenDSS) and the same network via
#           doe_common.jl -> load_lv3.jl (BMOPFTools).
# Outputs:  printed only (no file).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/opendss_check_caseA.jl")          (runs run_check() on include)
# Used for: REPRODUCE.md step 6 (section 4 row "Case A": bound-point 255.12 V).
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; OpenDSS (EPRI) via OpenDSSDirect.jl; Ipopt.
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))
using OpenDSSDirect

const SVC_16 = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SVC_4  = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const PU_X   = 1.03
const KW_ISSUED = 4.529

odcmd(c) = OpenDSSDirect.Text.Command(c)

# ---------------- OpenDSS: true 4 mm2 street with fixed PV export
function opendss_max_customer_v(kw, cust)
    root = pwd()
    master = abspath(joinpath(root, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
    try
        # solve twice: in this setup the first solve after clear+redirect left zero voltages
        for _ in 1:2                                    # warm-up: solve twice
            odcmd("clear")
            odcmd("redirect \"$master\"")
            odcmd("Edit Vsource.source pu=$(PU_X)")
            n = 0
            for nm in OpenDSSDirect.Lines.AllNames()
                OpenDSSDirect.Lines.Name(nm)
                if lowercase(OpenDSSDirect.Lines.LineCode()) == lowercase(SVC_16)
                    odcmd("Edit Line.$nm linecode=$SVC_4")
                    n += 1
                end
            end
            @assert n == 22 "expected 22 service segments in OpenDSS, swapped $n"
            odcmd("Edit XYCurve.VoltWatt yarray=[1 1 1 1]")         # Volt-Watt off
            for nm in OpenDSSDirect.PVsystems.AllNames()
                if kw > 0
                    odcmd("Edit PVSystem.$nm Pmpp=$kw kVA=100 kvarMax=5 kvarMaxAbs=5 irradiance=1")
                else
                    odcmd("Edit PVSystem.$nm kVA=100 kvarMax=5 kvarMaxAbs=5 irradiance=0")
                end
            end
            odcmd("set maxcontroliter=500")
            OpenDSSDirect.Solution.Solve()
        end
    finally
        cd(root)
    end
    @assert OpenDSSDirect.Solution.Converged() "OpenDSS did not converge"
    @assert maximum(abs.(OpenDSSDirect.Circuit.AllBusVolts())) > 0 "OpenDSS voltages all zero"
    node = Dict("a" => 1, "b" => 2, "c" => 3)
    best, where = -Inf, ""
    for (bus, ph) in cust
        OpenDSSDirect.Circuit.SetActiveBus(bus)
        v = Dict(zip(OpenDSSDirect.Bus.Nodes(), OpenDSSDirect.Bus.Voltages()))
        vpn_ = abs(v[node[ph]] - v[4])
        vpn_ > best && (best = vpn_; where = "$bus $ph-n")
    end
    pk = Float64[]; qk = Float64[]
    for nm in OpenDSSDirect.PVsystems.AllNames()
        OpenDSSDirect.PVsystems.Name(nm)
        push!(pk, OpenDSSDirect.PVsystems.kW()); push!(qk, OpenDSSDirect.PVsystems.kvar())
    end
    return best, where, extrema(pk), extrema(qk)
end

# ---------------- BMOPF: same true street, same fixed export, rating relaxed, VW off
function bmopf_max_customer_v(kw)
    net = make_net(PU_X)
    n = 0
    for l in values(net["line"])
        if l["linecode"] == SVC_16
            l["linecode"] = SVC_4
            n += 1
        end
    end
    @assert n == 22
    ev_net = deepcopy(net)
    for b in values(ev_net["bus"]); delete!(b, "vpn_min"); delete!(b, "vpn_max"); end
    for p in values(ev_net["control_profile"]); delete!(p, "volt_watt"); end
    for i in values(ev_net["ibr"]); i["s_max"] = [1.0e5]; end
    vv = ev_net["control_profile"]["invall"]["volt_var"]
    vv["q_limits"] = Float64.(vv["q_limits"]) .* (5000.0 / 1.0e5)    # same Q in var
    cps  = connection_points(net)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(ev_net, cps, caps; solver_options = OPTS)
    ev.feasible[1] || return (NaN, string(ev.termination_status[1]))
    return max_pn(ev.snapshots[1]; only = customer_points(net))
end

function run_check()
    cust = collect(customer_points(make_net(PU_X)))
    println("\n==== CASE A independent check: true street 4 mm2, source $(PU_X) pu ====")
    for kw in (0.0, KW_ISSUED)
        vo, wo, pr, qr = opendss_max_customer_v(kw, cust)
        vb, wb = bmopf_max_customer_v(kw)
        @printf("\nexport %.3f kW per house\n", kw)
        @printf("  OpenDSS : max customer V %.2f V at %s   (PV P %.3f-%.3f kW, Q %.3f-%.3f kvar)\n",
                vo, wo, pr[1], pr[2], qr[1], qr[2])
        @printf("  BMOPF   : max customer V %.2f V at %s\n", vb, wb)
        @printf("  difference %.3f V   | both vs 253 V: OpenDSS %+.2f V, BMOPF %+.2f V\n",
                vb - vo, vo - V_MAX_PN, vb - V_MAX_PN)
    end
end

run_check()