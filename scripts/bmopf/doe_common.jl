# scripts/bmopf/doe_common.jl
#
# Shared helpers for the DOE scripts. Defines functions only; runs nothing
# except loading load_lv3.jl once per Julia session.
#
# Conventions (checked against BMOPFTools b7aa9a1 / PowerOptLab 953e45c, 13 Oct):
#   - voltage_source "v_magnitude": phase-to-neutral volts, 4 entries, neutral 0.
#   - vpn_min / vpn_max: SI volts, one entry per phase in terminal_names order (neutral excluded).
#   - DOE snapshots are in SI (V, W, var).
#   - Loads: ORIGINAL CSIRO values, 1 kW + 0.539743 kvar (pf 0.88), written in Loads.dss.

using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

isdefined(Main, :load_lv3) || include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))

const V_MIN_PN    = 207.0
const V_MAX_PN    = 253.0
const NO_LIMIT_HI = 1.0e4
const NO_LIMIT_LO = 0.0
const MV_BUSES    = ("sourcebus", "b804")
const OPTS        = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)
const LIMIT_MODE  = :customer          # :customer (default) or :all
const V_SRC_1PU   = 11000 / sqrt(3)    # 6350.85 V phase-to-neutral at 1.00 pu
const LOAD_P_W    = 1000.0
const LOAD_Q_VAR  = 539.743

function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    vm = Float64.(vs["v_magnitude"])
    @assert isapprox(maximum(vm), V_SRC_1PU; rtol = 1e-6) "Master.dss source is not at 1.00 pu (max $(maximum(vm)) V)"
    vs["v_magnitude"] = vm .* pu
    return net
end

function check_loads(net)
    @assert length(net["load"]) == 12 "expected 12 loads"
    for (id, ld) in net["load"]
        @assert isapprox(ld["p_nom"][1], LOAD_P_W; atol = 0.01) "$id p_nom $(ld["p_nom"]) (expected 1000 W)"
        @assert isapprox(ld["q_nom"][1], LOAD_Q_VAR; atol = 0.01) "$id q_nom $(ld["q_nom"]) (expected 539.743 var)"
    end
end

customer_points(net) = Set((String(ld["bus"]), String(ld["terminal_map"][1])) for ld in values(net["load"]))
inverter_points(net) = Set((String(i["bus"]), String(i["terminal_map"][1])) for i in values(net["ibr"]))

function add_pn_limits!(net; mode = LIMIT_MODE)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    cust = customer_points(net)
    @assert length(cust) == 12 "expected 12 customer connection points"
    @assert cust == inverter_points(net) "customer points and inverter points differ"
    nphase = 0
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        phases = [t for t in terms if t != "n"]
        if mode == :all
            b["vpn_min"] = fill(V_MIN_PN, length(phases))
            b["vpn_max"] = fill(V_MAX_PN, length(phases))
            nphase += length(phases)
        elseif mode == :customer
            any((bid, p) in cust for p in phases) || continue
            b["vpn_min"] = [((bid, p) in cust) ? V_MIN_PN : NO_LIMIT_LO for p in phases]
            b["vpn_max"] = [((bid, p) in cust) ? V_MAX_PN : NO_LIMIT_HI for p in phases]
            nphase += count(p -> (bid, p) in cust, phases)
        else
            error("unknown LIMIT_MODE $mode")
        end
    end
    return nphase
end

# Fresh network: load, check loads, set source, add limits.
function make_net(pu; mode = LIMIT_MODE)
    net = load_lv3()
    check_loads(net)
    scale_source!(net, pu)
    add_pn_limits!(net; mode = mode)
    return net
end

function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

doe(net, cps) = solve_operating_envelope(net, cps; fairness = :equal, direction = :export,
                                         security = :bound_point, solver_options = OPTS)

vpn(ts, ph) = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - complex(ts["n"]["vr"], ts["n"]["vi"]))

# Highest phase-to-neutral voltage; only = set of (bus, phase) to restrict.
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

# Per-house table and which limit is binding.
function house_report(snap, net, r)
    @printf("  %-16s %9s %10s %9s\n", "house", "limit kW", "V_pn (V)", "S/5kVA")
    smax_ratio = 0.0
    for (id, inv) in sort(collect(net["ibr"]); by = first)
        ph = String(inv["terminal_map"][1])
        v  = vpn(snap["bus"][inv["bus"]], ph)
        g  = get(get(get(snap, "ibr", Dict()), id, Dict()), ph, nothing)
        s  = g === nothing ? NaN : hypot(g["pg"], g["qg"]) / inv["s_max"][1]
        isfinite(s) && (smax_ratio = max(smax_ratio, s))
        @printf("  %-16s %9.3f %10.2f %9.3f\n", id, r.envelope[id][1] / 1000, v, s)
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    lim = smax_ratio > 0.999 ? "inverter rating (5 kVA, with Volt-VAr absorption)" :
          vc >= V_MAX_PN - 0.01 ? "voltage limit (253 V at a customer)" :
          "export_max (5 kW nameplate)"
    println("  -> export is limited by: ", lim)
end