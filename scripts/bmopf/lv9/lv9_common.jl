# =============================================================================
# lv9_common.jl: shared helpers for all LV9 scripts (load network, DOE, realised reading)
#
# What it does (plain English): loads the prepared LV9 network into BMOPFTools with the
#   same inverter settings as LV3 (scripts/bmopf/load_lv3.jl), sets the source voltage,
#   puts the 207-253 V phase-to-neutral limits on the 123 customer connection points only,
#   computes the equal bound-point DOE (eq_doe), and gives the "realised" reading of an
#   issued DOE (realised: everyone may export up to its cap, Volt-VAr / Volt-Watt / 5 kVA
#   kept, no voltage limit imposed). Defines nothing to run on its own.
#   Do NOT include doe_common.jl in the same Julia session (same function names).
#   Source voltage: LV3's transformer has tap 1.025 on the 11 kV side, LV9's has 1.000, so at
#   the same source pu LV9's street is about 2.5 % higher (LV3 1.03 pu ~ LV9 1.005 pu; same
#   transformer no-load voltage only, see REPRODUCE.md known issue 17).
# Inputs:   data/networks/LV9_258bus_withPV/Master.dss (from prepare_lv9.jl).
# Outputs:  none (helper functions and constants only).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   included by the other LV9 scripts; not run directly.
# Used for: every LV9 result (REPRODUCE.md steps 20-24, 29-31 and 33).
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

# Where the prepared LV9 network files live (made by prepare_lv9.jl)
const LV9_DIR     = joinpath(pwd(), "data", "networks", "LV9_258bus_withPV")
# The street has 123 homes (customers), each with one load and one rooftop PV inverter
const N_CUST      = 123
# 230 V = normal home voltage; used to turn the inverter curve points from pu into volts
# (pu = grid voltage relative to normal, so 1.03 pu = 3 % high)
const V_BASE_INV  = 230.0
# Allowed home voltage, phase-to-neutral (the voltage a home feels): 207 V to 253 V
const V_MIN_PN    = 207.0
const V_MAX_PN    = 253.0
# Dummy 'no limit' values, used on bus phases that have no home on them
const NO_LIMIT_HI = 1.0e4
const NO_LIMIT_LO = 0.0
# The two 11 kV buses before the transformer; every voltage check skips them
const MV_BUSES    = ("sourcebus", "b1690")
# Solver (Ipopt) settings: tight tolerance, up to 3000 steps, print nothing
const OPTS        = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)
# 1.00 pu at the 11 kV source, in volts per phase (11000 / sqrt(3))
const V_SRC_1PU   = 11000 / sqrt(3)
# Every house load: 1 kW and 0.539743 kvar (CSIRO default, written by prepare_lv9.jl)
const LOAD_P_W    = 1000.0
const LOAD_Q_VAR  = 539.743
# Line codes: the 16 mm2 copper cable the records say, and the thinner 4 mm2 cable used as the 'true' one
const SVC_LC      = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SMALL_LC    = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
# Factor to compare with LV3 (different transformer tap, see the header above)
const LV9_EQUIV   = 1.025          # LV9 pu x 1.025 = LV3-equivalent pu (same LV voltage)

# Load the LV9 network and give every inverter the same rules as LV3, then check it. Returns the network.
# Volt-VAr / Volt-Watt = inverter rules from AS/NZS 4777.2: when voltage is high the inverter
# soaks up reactive power (Volt-VAr) and then cuts its real power (Volt-Watt)
function load_lv9()
    net = from_dss(joinpath(LV9_DIR, "Master.dss"))
    # The two curves as read from the OpenDSS file (x values in pu)
    vv  = net["control_profile"]["invall"]["volt_var"]
    vw  = net["control_profile"]["invall"]["volt_watt"]
    # Volt-VAr: drop the two outer curve points, turn the middle four from pu into volts,
    # and set the reactive power range (-0.6 when voltage is high, +0.44 when low)
    vv_pu = Float64.(vv["breakpoints"]); @assert length(vv_pu) == 6
    vv["breakpoints"] = vv_pu[2:5] .* V_BASE_INV
    vv["q_limits"] = [-0.6, 0.44]
    vv["voltage_reference"] = "PN_PER_PHASE"
    # Volt-Watt: keep the two middle points (in volts); real power can be cut down to 20 %
    vw_pu = Float64.(vw["breakpoints"]); @assert length(vw_pu) == 4
    vw["breakpoints"] = vw_pu[2:3] .* V_BASE_INV
    vw["p_limits"] = [0.2, 1.0]
    vw["voltage_reference"] = "PN_PER_PHASE"
    # Every inverter uses this one shared rule set ('invall'); any other rule set is deleted
    for ibr in values(net["ibr"])
        ibr["control_profile"] = "invall"
    end
    for k in collect(keys(net["control_profile"]))
        k == "invall" || delete!(net["control_profile"], k)
    end
    # Safety checks: curves in volts as expected, 123 PVs, each between a phase and the neutral,
    # each with a size, and the 4 mm2 line code is present
    @assert vv["breakpoints"] ≈ [207, 220, 240, 258]
    @assert vw["breakpoints"] ≈ [253, 260]
    @assert vw["p_limits"][1] < vw["p_limits"][2]
    @assert length(net["ibr"]) == N_CUST "expected $N_CUST PVs, found $(length(net["ibr"]))"
    @assert all(ibr["terminal_map"][2] == "n" for ibr in values(net["ibr"])) "a PV is not on the neutral"
    @assert all(haskey(ibr, "s_max") for ibr in values(net["ibr"])) "a PV has no s_max"
    @assert haskey(net["linecode"], SMALL_LC) "4 mm2 line code missing"
    return net
end

# Set the source voltage to pu x normal (e.g. pu = 0.94 gives 94 % of normal)
function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    # The file must start at exactly 1.00 pu, otherwise the scaling would be wrong
    vm = Float64.(vs["v_magnitude"])
    @assert isapprox(maximum(vm), V_SRC_1PU; rtol = 1e-6) "Master.dss source is not at 1.00 pu"
    vs["v_magnitude"] = vm .* pu
    return net
end

# Check that all 123 loads are the 1 kW / 0.539743 kvar default
function check_loads(net)
    @assert length(net["load"]) == N_CUST "expected $N_CUST loads"
    for (id, ld) in net["load"]
        @assert isapprox(ld["p_nom"][1], LOAD_P_W; atol = 0.01) "$id p_nom $(ld["p_nom"])"
        @assert isapprox(ld["q_nom"][1], LOAD_Q_VAR; atol = 0.01) "$id q_nom $(ld["q_nom"])"
    end
end

# The (bus, phase) where each home connects: once from the loads, once from the inverters
customer_points(net) = Set((String(ld["bus"]), String(ld["terminal_map"][1])) for ld in values(net["load"]))
inverter_points(net) = Set((String(i["bus"]), String(i["terminal_map"][1])) for i in values(net["ibr"]))

# Put the 207-253 V limits only on the phases where a home is connected.
# Other phases on the same bus get dummy limits (0 to 10000 V), so they never bind
function add_pn_limits!(net)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    # Both lists must give the same 123 points (each home's load and PV share one point)
    cust = customer_points(net)
    @assert length(cust) == N_CUST "expected $N_CUST customer points, found $(length(cust))"
    @assert cust == inverter_points(net) "customer points and inverter points differ"
    # Skip the 11 kV buses, buses without a neutral, and buses with no home on them
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        phases = [t for t in terms if t != "n"]
        any((bid, p) in cust for p in phases) || continue
        # Real limit on a home's phase, dummy limit on the other phases
        b["vpn_min"] = [((bid, p) in cust) ? V_MIN_PN : NO_LIMIT_LO for p in phases]
        b["vpn_max"] = [((bid, p) in cust) ? V_MAX_PN : NO_LIMIT_HI for p in phases]
    end
end

# Build a ready-to-use street at source voltage pu: load it, check loads, set source, add home limits
function make_net(pu)
    net = load_lv9()
    check_loads(net)
    scale_source!(net, pu)
    add_pn_limits!(net)
    return net
end

# One 'connection point' per home (bus, phase, neutral, its inverter), sorted by name.
# Each may export up to export_max watts (5000 W = 5 kW unless told otherwise)
function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

# Solve the DOE (DOE = the export limit every home gets) with PowerOptLab.
# fairness = :equal gives every home the same limit; :bound_point = the basic DOE,
# checked only with everyone exporting at once
doe(net, cps; fairness = :equal) = solve_operating_envelope(net, cps; fairness = fairness, direction = :export,
                                                              security = :bound_point, solver_options = OPTS)

# Phase-to-neutral voltage (what a home feels) from one bus result: |V phase - V neutral|
vpn(ts, ph) = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - complex(ts["n"]["vr"], ts["n"]["vi"]))

# Highest phase-to-neutral voltage in a solved result, and where it is.
# With `only`, look only at the listed (bus, phase) points (e.g. the 123 home points)
function max_pn(snapshot; only = nothing)
    best, where = -Inf, ""
    for (bid, ts) in snapshot["bus"]
        bid in MV_BUSES && continue
        haskey(ts, "n") || continue
        for ph in ("a", "b", "c")
            haskey(ts, ph) || continue
            only === nothing || (bid, ph) in only || continue
            v = vpn(ts, ph)
            v > best && (best = v; where = "$bid $ph-n")
        end
    end
    return best, where
end

# Say what stopped the DOE going higher: 'inverter' if an inverter is at its full size (5 kVA),
# 'voltage' if a home sits at 253 V, otherwise 'other'
function binding(snap, net)
    smax = 0.0
    # Largest inverter loading: sqrt(P^2 + Q^2) / inverter size
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "other"
end

# equal bound-point DOE: returns (kW per customer, binding, max customer V, status, full result r);
# kW is NaN and binding "infeasible" if the solve fails
function eq_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    # The solve failed if the total is not a finite number
    ok  = isfinite(r.total_capacity[1])
    # Every home gets the same limit, so read the first home's one (W -> kW)
    kw  = ok ? r.envelope[cps[1].id][1] / 1000 : NaN
    return kw, ok ? binding(r.snapshots[1], net) : "infeasible",
           ok ? max_pn(r.snapshots[1]; only = customer_points(net))[1] : NaN, string(r.termination_status[1]), r
end

# 16 mm2 service segments, and the ones that touch a customer bus (longest first)
service_ids(net) = sort([String(id) for (id, l) in net["line"] if l["linecode"] == SVC_LC])
function customer_cables(net)
    # lb = every bus where a home is connected; keep the 16 mm2 segments that touch one of them
    lb = Set(lowercase(String(l["bus"])) for l in values(net["load"]))
    ids = [id for id in service_ids(net)
           if lowercase(String(net["line"][id]["bus_from"])) in lb || lowercase(String(net["line"][id]["bus_to"])) in lb]
    return sort(ids; by = id -> -Float64(net["line"][id]["length"]))
end

# Make EVERY 16 mm2 segment 4 mm2 (all these cables thinner than the records say)
function all_small!(net)
    for id in service_ids(net)
        net["line"][id]["linecode"] = SMALL_LC
    end
    return net
end

# realised outcome: everyone may export up to caps (Dict id => kW, or a number for all);
# inverters keep Volt-VAr, Volt-Watt, 5 kVA; no voltage limit imposed.
# A cap of 0 ("dropped" / silent customer) is given as 1 W to the solver, so curtail_kW is about
# 0.001 kW lower per silent customer. A failed solve returns v = NaN, n_over = -1 (callers that
# test v <= limit then count it as a failure).
# Realised reading = homes export up to the cap with inverter rules on and no voltage limit
# imposed, then we read the voltage
function realised(net, caps)
    # Work on a copy and remove every voltage limit, so the solver does not cut export to protect 253 V
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in ("vpn_min", "vpn_max", "vpg_min", "vpg_max", "v_min", "v_max", "vm_min", "vm_max")
        delete!(b, k)
    end
    # caps can be one number for everyone, or one number per home
    capf(id) = caps isa Number ? caps : caps[id]
    # Each home may export up to its cap (kW -> W), at least 1 W (the solver needs a cap above zero)
    cps = [ConnectionPoint(id = cp.id, bus = cp.bus, phase_terminals = cp.phase_terminals,
                           neutral = cp.neutral, export_max = max(1000.0 * capf(cp.id), 1.0),
                           ibr_id = cp.ibr_id) for cp in connection_points(ev)]
    # :max_total = let the homes export as much as they can within their caps and inverter rules
    r = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, curtail_kW = NaN, who = "")
    snap = r.snapshots[1]
    # Highest home voltage, and the list of homes above 253 V (0.005 V tolerance)
    v, _ = max_pn(snap; only = customer_points(net))
    over = [pt for pt in collect(customer_points(net)) if max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005]
    # Curtailment: how much less than their caps the homes really export (Volt-Watt and 5 kVA cuts), kW
    curtail = sum(capf(cp.id) - r.envelope[cp.id][1] / 1000 for cp in cps)
    return (v = v, n_over = length(over), curtail_kW = curtail,
            who = join(["$(p[1]) $(p[2])-n" for p in sort(over)], ";"))
end
