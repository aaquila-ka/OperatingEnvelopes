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

# Line-code names of the 16 mm2 service cable (records) and the thin 4 mm2 cable (true street)
const SVC_16 = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SVC_4  = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
# Source voltage 1.03 pu (pu = grid voltage relative to normal, so 1.03 = 3% high) and the issued DOE
# (DOE = the export limit every home gets) that the wrong records give, from REPRODUCE.md section 4
const PU_X   = 1.03
const KW_ISSUED = 4.529

# Short helper: send one text command to OpenDSS
odcmd(c) = OpenDSSDirect.Text.Command(c)

# ---------------- OpenDSS: true 4 mm2 street with fixed PV export
# Solves the true 4 mm2 street in OpenDSS with every PV fixed at kw kW; returns the highest customer
# phase-to-neutral voltage (what a home feels), where it is, and the range of PV P (kW) and Q (kvar)
function opendss_max_customer_v(kw, cust)
    root = pwd()
    master = abspath(joinpath(root, "data", "networks", "LV3_55bus_withPV", "Master.dss"))
    try
        # solve twice: in this setup the first solve after clear+redirect left zero voltages
        for _ in 1:2                                    # warm-up: solve twice
            # Load the LV3 network from Master.dss and set the source to 1.03 pu
            odcmd("clear")
            odcmd("redirect \"$master\"")
            odcmd("Edit Vsource.source pu=$(PU_X)")
            n = 0
            # Swap every 16 mm2 service segment to the 4 mm2 line code, counting how many were changed
            for nm in OpenDSSDirect.Lines.AllNames()
                OpenDSSDirect.Lines.Name(nm)
                if lowercase(OpenDSSDirect.Lines.LineCode()) == lowercase(SVC_16)
                    odcmd("Edit Line.$nm linecode=$SVC_4")
                    n += 1
                end
            end
            @assert n == 22 "expected 22 service segments in OpenDSS, swapped $n"
            # Volt-Watt off: a flat curve that never cuts real power
            # (Volt-VAr / Volt-Watt = AS/NZS 4777.2 inverter rules that react to high voltage)
            odcmd("Edit XYCurve.VoltWatt yarray=[1 1 1 1]")         # Volt-Watt off
            # Fix every PV's output: Pmpp = kw at full sun, inverter size 100 kVA so P is never cut,
            # reactive limit kept at 5 kvar like a 5 kVA inverter; for 0 kW, no sun at all
            for nm in OpenDSSDirect.PVsystems.AllNames()
                if kw > 0
                    odcmd("Edit PVSystem.$nm Pmpp=$kw kVA=100 kvarMax=5 kvarMaxAbs=5 irradiance=1")
                else
                    odcmd("Edit PVSystem.$nm kVA=100 kvarMax=5 kvarMaxAbs=5 irradiance=0")
                end
            end
            # Allow many control iterations so the Volt-VAr loop can settle, then solve
            odcmd("set maxcontroliter=500")
            OpenDSSDirect.Solution.Solve()
        end
    finally
        # OpenDSS redirect can change the working folder; put it back
        cd(root)
    end
    # Stop if OpenDSS did not converge or gave all-zero voltages
    @assert OpenDSSDirect.Solution.Converged() "OpenDSS did not converge"
    @assert maximum(abs.(OpenDSSDirect.Circuit.AllBusVolts())) > 0 "OpenDSS voltages all zero"
    # OpenDSS numbers the conductors: 1 = a, 2 = b, 3 = c, 4 = neutral
    node = Dict("a" => 1, "b" => 2, "c" => 3)
    best, where = -Inf, ""
    # For each customer (bus, phase): phase-to-neutral voltage = |V(phase) - V(neutral)|; keep the highest
    for (bus, ph) in cust
        OpenDSSDirect.Circuit.SetActiveBus(bus)
        v = Dict(zip(OpenDSSDirect.Bus.Nodes(), OpenDSSDirect.Bus.Voltages()))
        vpn_ = abs(v[node[ph]] - v[4])
        vpn_ > best && (best = vpn_; where = "$bus $ph-n")
    end
    # Collect every PV's real (kW) and reactive (kvar) output, to show the min and max
    pk = Float64[]; qk = Float64[]
    for nm in OpenDSSDirect.PVsystems.AllNames()
        OpenDSSDirect.PVsystems.Name(nm)
        push!(pk, OpenDSSDirect.PVsystems.kW()); push!(qk, OpenDSSDirect.PVsystems.kvar())
    end
    return best, where, extrema(pk), extrema(qk)
end

# ---------------- BMOPF: same true street, same fixed export, rating relaxed, VW off
# Same test in BMOPF: true 4 mm2 street, every home exports exactly kw kW, Volt-Watt off and the
# inverter rating relaxed; returns the highest customer voltage and where (NaN and a status if it fails)
function bmopf_max_customer_v(kw)
    net = make_net(PU_X)
    n = 0
    # Swap the 22 service segments to 4 mm2, as in the OpenDSS function
    for l in values(net["line"])
        if l["linecode"] == SVC_16
            l["linecode"] = SVC_4
            n += 1
        end
    end
    @assert n == 22
    # Copy for the check: remove the voltage limits and switch Volt-Watt off
    ev_net = deepcopy(net)
    for b in values(ev_net["bus"]); delete!(b, "vpn_min"); delete!(b, "vpn_max"); end
    for p in values(ev_net["control_profile"]); delete!(p, "volt_watt"); end
    # Pretend-big inverter (100 kVA), and Volt-VAr limits scaled by 5000 / 1e5 so the reactive power stays what a 5 kVA inverter would give
    for i in values(ev_net["ibr"]); i["s_max"] = [1.0e5]; end
    vv = ev_net["control_profile"]["invall"]["volt_var"]
    vv["q_limits"] = Float64.(vv["q_limits"]) .* (5000.0 / 1.0e5)    # same Q in var
    # Every home's cap is kw kW; verify_operating_envelope (PowerOptLab) solves the street with those exports
    cps  = connection_points(net)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(ev_net, cps, caps; solver_options = OPTS)
    ev.feasible[1] || return (NaN, string(ev.termination_status[1]))
    # Highest phase-to-neutral voltage at the 12 customer connection points
    return max_pn(ev.snapshots[1]; only = customer_points(net))
end

# Runs both tools at 0 kW (checks the cable swap is the same in both) and at the issued 4.529 kW, and prints
# the highest customer voltage from each, their difference, and how far each is above or below 253 V
function run_check()
    # The 12 customer (bus, phase) points, taken from the BMOPF network
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

# Runs straight away when the file is included
run_check()