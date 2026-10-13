# scripts/bmopf/lv9/lv9_common.jl
#
# Helpers for the second feeder (CSIRO LV9, 258 buses, 123 customers). Same conventions and
# corrections as scripts/bmopf/load_lv3.jl and doe_common.jl, with LV9 constants.
# Do NOT include doe_common.jl in the same Julia session (same function names).
#
# NOTE ON SOURCE VOLTAGE: LV3's transformer has tap 1.025 on the 11 kV side, LV9's has 1.000,
# so at the same source pu LV9's street is about 2.5 % HIGHER. LV3 at 1.03 pu ~ LV9 at 1.005 pu.

using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

const LV9_DIR     = joinpath(pwd(), "data", "networks", "LV9_258bus_withPV")
const N_CUST      = 123
const V_BASE_INV  = 230.0
const V_MIN_PN    = 207.0
const V_MAX_PN    = 253.0
const NO_LIMIT_HI = 1.0e4
const NO_LIMIT_LO = 0.0
const MV_BUSES    = ("sourcebus", "b1690")
const OPTS        = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)
const V_SRC_1PU   = 11000 / sqrt(3)
const LOAD_P_W    = 1000.0
const LOAD_Q_VAR  = 539.743
const SVC_LC      = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SMALL_LC    = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const LV9_EQUIV   = 1.025          # LV9 pu x 1.025 = LV3-equivalent pu (same LV voltage)

function load_lv9()
    net = from_dss(joinpath(LV9_DIR, "Master.dss"))
    vv  = net["control_profile"]["invall"]["volt_var"]
    vw  = net["control_profile"]["invall"]["volt_watt"]
    vv_pu = Float64.(vv["breakpoints"]); @assert length(vv_pu) == 6
    vv["breakpoints"] = vv_pu[2:5] .* V_BASE_INV
    vv["q_limits"] = [-0.6, 0.44]
    vv["voltage_reference"] = "PN_PER_PHASE"
    vw_pu = Float64.(vw["breakpoints"]); @assert length(vw_pu) == 4
    vw["breakpoints"] = vw_pu[2:3] .* V_BASE_INV
    vw["p_limits"] = [0.2, 1.0]
    vw["voltage_reference"] = "PN_PER_PHASE"
    for ibr in values(net["ibr"])
        ibr["control_profile"] = "invall"
    end
    for k in collect(keys(net["control_profile"]))
        k == "invall" || delete!(net["control_profile"], k)
    end
    @assert vv["breakpoints"] ≈ [207, 220, 240, 258]
    @assert vw["breakpoints"] ≈ [253, 260]
    @assert vw["p_limits"][1] < vw["p_limits"][2]
    @assert length(net["ibr"]) == N_CUST "expected $N_CUST PVs, found $(length(net["ibr"]))"
    @assert all(ibr["terminal_map"][2] == "n" for ibr in values(net["ibr"])) "a PV is not on the neutral"
    @assert all(haskey(ibr, "s_max") for ibr in values(net["ibr"])) "a PV has no s_max"
    @assert haskey(net["linecode"], SMALL_LC) "4 mm2 line code missing"
    return net
end

function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    vm = Float64.(vs["v_magnitude"])
    @assert isapprox(maximum(vm), V_SRC_1PU; rtol = 1e-6) "Master.dss source is not at 1.00 pu"
    vs["v_magnitude"] = vm .* pu
    return net
end

function check_loads(net)
    @assert length(net["load"]) == N_CUST "expected $N_CUST loads"
    for (id, ld) in net["load"]
        @assert isapprox(ld["p_nom"][1], LOAD_P_W; atol = 0.01) "$id p_nom $(ld["p_nom"])"
        @assert isapprox(ld["q_nom"][1], LOAD_Q_VAR; atol = 0.01) "$id q_nom $(ld["q_nom"])"
    end
end

customer_points(net) = Set((String(ld["bus"]), String(ld["terminal_map"][1])) for ld in values(net["load"]))
inverter_points(net) = Set((String(i["bus"]), String(i["terminal_map"][1])) for i in values(net["ibr"]))

function add_pn_limits!(net)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    cust = customer_points(net)
    @assert length(cust) == N_CUST "expected $N_CUST customer points, found $(length(cust))"
    @assert cust == inverter_points(net) "customer points and inverter points differ"
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        phases = [t for t in terms if t != "n"]
        any((bid, p) in cust for p in phases) || continue
        b["vpn_min"] = [((bid, p) in cust) ? V_MIN_PN : NO_LIMIT_LO for p in phases]
        b["vpn_max"] = [((bid, p) in cust) ? V_MAX_PN : NO_LIMIT_HI for p in phases]
    end
end

function make_net(pu)
    net = load_lv9()
    check_loads(net)
    scale_source!(net, pu)
    add_pn_limits!(net)
    return net
end

function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

doe(net, cps; fairness = :equal) = solve_operating_envelope(net, cps; fairness = fairness, direction = :export,
                                                              security = :bound_point, solver_options = OPTS)

vpn(ts, ph) = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - complex(ts["n"]["vr"], ts["n"]["vi"]))

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

function binding(snap, net)
    smax = 0.0
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "other"
end

# equal DOE: (kW, binding, max customer V, status)
function eq_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    ok  = isfinite(r.total_capacity[1])
    kw  = ok ? r.envelope[cps[1].id][1] / 1000 : NaN
    return kw, ok ? binding(r.snapshots[1], net) : "infeasible",
           ok ? max_pn(r.snapshots[1]; only = customer_points(net))[1] : NaN, string(r.termination_status[1]), r
end

# 16 mm2 service segments, and the ones that touch a customer bus (longest first)
service_ids(net) = sort([String(id) for (id, l) in net["line"] if l["linecode"] == SVC_LC])
function customer_cables(net)
    lb = Set(lowercase(String(l["bus"])) for l in values(net["load"]))
    ids = [id for id in service_ids(net)
           if lowercase(String(net["line"][id]["bus_from"])) in lb || lowercase(String(net["line"][id]["bus_to"])) in lb]
    return sort(ids; by = id -> -Float64(net["line"][id]["length"]))
end

function all_small!(net)
    for id in service_ids(net)
        net["line"][id]["linecode"] = SMALL_LC
    end
    return net
end

# realised outcome: everyone may export up to caps (Dict id => kW, or a number for all);
# inverters keep Volt-VAr, Volt-Watt, 5 kVA; no voltage limit imposed
function realised(net, caps)
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in ("vpn_min", "vpn_max", "vpg_min", "vpg_max", "v_min", "v_max", "vm_min", "vm_max")
        delete!(b, k)
    end
    capf(id) = caps isa Number ? caps : caps[id]
    cps = [ConnectionPoint(id = cp.id, bus = cp.bus, phase_terminals = cp.phase_terminals,
                           neutral = cp.neutral, export_max = max(1000.0 * capf(cp.id), 1.0),
                           ibr_id = cp.ibr_id) for cp in connection_points(ev)]
    r = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, curtail_kW = NaN, who = "")
    snap = r.snapshots[1]
    v, _ = max_pn(snap; only = customer_points(net))
    over = [pt for pt in collect(customer_points(net)) if max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005]
    curtail = sum(capf(cp.id) - r.envelope[cp.id][1] / 1000 for cp in cps)
    return (v = v, n_over = length(over), curtail_kW = curtail,
            who = join(["$(p[1]) $(p[2])-n" for p in sort(over)], ";"))
end
