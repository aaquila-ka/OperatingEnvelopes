# =============================================================================
# doe_common.jl: shared helper functions for all LV3 DOE scripts
#
# What it does (plain English):
#   Defines the building blocks the other scripts reuse: build a fresh LV3 network at a
#   chosen source voltage, put the 207-253 V phase-to-neutral limits on the 12 customer
#   connection points, describe the 12 solar connection points, solve the equal-share
#   DOE (dynamic operating envelope = the export limit each home gets), and find the
#   highest phase-to-neutral voltage. Defines functions only; it runs nothing except
#   loading load_lv3.jl once per Julia session.
# Inputs:   includes scripts/bmopf/load_lv3.jl (which reads the LV3 .dss files)
# Outputs:  none of its own (load_lv3.jl rewrites results/analyze_lv3_after_ctrlfix.txt
#           the first time it is included)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/doe_common.jl")   then e.g.   net = make_net(1.03); r = doe(net, connection_points(net))
# Used for: every LV3 step in REPRODUCE.md (included directly or through another script),
#           and by lv9/lv9_common.jl
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by
#           Frederik Geth; JuMP; Ipopt
# =============================================================================
#
# Conventions (checked against BMOPFTools b7aa9a1 / PowerOptLab 953e45c):
#   - voltage_source "v_magnitude": phase-to-neutral volts, 4 entries, neutral 0.
#     1.00 pu (per unit) = 11 kV line-to-line = 6350.85 V phase-to-neutral.
#   - vpn_min / vpn_max: SI volts, one entry per phase in terminal_names order (neutral excluded).
#   - DOE snapshots are in SI units (V, W, var); envelope values are in W (divide by 1000 for kW).
#   - Loads: ORIGINAL CSIRO values, 1 kW + 0.539743 kvar (power factor 0.88), written in Loads.dss.

# BMOPFTools builds the network model; PowerOptLab computes and checks DOEs; JuMP and Ipopt are the
# optimisation tools that do the actual solving
using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

# Load load_lv3.jl only if it is not loaded yet, so including this file again does not reload it
isdefined(Main, :load_lv3) || include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))

# The allowed voltage band at a home, phase-to-neutral (what a home feels): 207 V to 253 V
const V_MIN_PN    = 207.0
const V_MAX_PN    = 253.0
# Very wide limits (0 V to 10 000 V) for points that should in effect have NO limit
const NO_LIMIT_HI = 1.0e4
const NO_LIMIT_LO = 0.0
# The two 11 kV (medium-voltage) buses on the high side of the transformer; they never get the
# 207-253 V limits
const MV_BUSES    = ("sourcebus", "b804")
# Ipopt solver settings: tight tolerance, up to 3000 iterations, no solver printout
const OPTS        = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)
# Which points get the 253 V limit: :customer = only the 12 homes' own connection points (the thesis
# default)
const LIMIT_MODE  = :customer          # :customer (default) or :all
# 1.00 pu source = 11 kV line-to-line / sqrt(3) = 6350.85 V phase-to-neutral
const V_SRC_1PU   = 11000 / sqrt(3)    # 6350.85 V phase-to-neutral at 1.00 pu
# The original CSIRO load at every home: 1 kW and 0.539743 kvar
const LOAD_P_W    = 1000.0
const LOAD_Q_VAR  = 539.743

# scale_source!: set the grid (source) voltage to pu x normal and return the same network. pu = grid
# voltage relative to normal, so 1.03 = 3% high
function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    vm = Float64.(vs["v_magnitude"])
    # First check the files really start at 1.00 pu, so multiplying by pu gives the right voltage
    @assert isapprox(maximum(vm), V_SRC_1PU; rtol = 1e-6) "Master.dss source is not at 1.00 pu (max $(maximum(vm)) V)"
    vs["v_magnitude"] = vm .* pu
    return net
end

# check_loads: stop with an error unless there are 12 loads and each is 1 kW and 0.539743 kvar
function check_loads(net)
    @assert length(net["load"]) == 12 "expected 12 loads"
    for (id, ld) in net["load"]
        @assert isapprox(ld["p_nom"][1], LOAD_P_W; atol = 0.01) "$id p_nom $(ld["p_nom"]) (expected 1000 W)"
        @assert isapprox(ld["q_nom"][1], LOAD_Q_VAR; atol = 0.01) "$id q_nom $(ld["q_nom"]) (expected 539.743 var)"
    end
end

# The set of (bus, phase) points where a home is connected, and where an inverter is connected (on
# LV3 these must be the same 12 points)
customer_points(net) = Set((String(ld["bus"]), String(ld["terminal_map"][1])) for ld in values(net["load"]))
inverter_points(net) = Set((String(i["bus"]), String(i["terminal_map"][1])) for i in values(net["ibr"]))

# add_pn_limits!: put the 207-253 V phase-to-neutral limits on the network. With :customer, only the
# phase a home is on gets the real limits; other phases at that bus get the very wide ones. Returns
# how many points got real limits
function add_pn_limits!(net; mode = LIMIT_MODE)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    cust = customer_points(net)
    @assert length(cust) == 12 "expected 12 customer connection points"
    @assert cust == inverter_points(net) "customer points and inverter points differ"
    nphase = 0
    # Go through every bus, skipping the two medium-voltage buses and any bus with no neutral wire
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        phases = [t for t in terms if t != "n"]
        # :all = limit every phase of every low-voltage bus (a stricter alternative, see
        # REPRODUCE.md section 5)
        if mode == :all
            b["vpn_min"] = fill(V_MIN_PN, length(phases))
            b["vpn_max"] = fill(V_MAX_PN, length(phases))
            nphase += length(phases)
        # :customer (default) = limit only the phases where a home is connected; buses with no home
        # are skipped
        elseif mode == :customer
            any((bid, p) in cust for p in phases) || continue
            # For each phase: 207 / 253 V if a home is on it, otherwise the very wide 0 V / 10 000 V
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

# connection_points: describe the 12 solar connection points for PowerOptLab: which bus, which
# phase, neutral "n", and the most each may export (5000 W = the 5 kW nameplate). Sorted by id so
# the order is always the same
function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

# doe(): solve the DOE (dynamic operating envelope = the export limit every home gets). fairness =
# :equal means every home gets the SAME limit; security = :bound_point means it is checked only with
# everyone exporting their full limit at once (the basic, bound-point DOE).
# It returns PowerOptLab's result: r.envelope[id][1] = a home's limit in W, r.total_capacity[1] =
# the total, r.snapshots[1] = the solved voltages and powers
doe(net, cps) = solve_operating_envelope(net, cps; fairness = :equal, direction = :export,
                                         security = :bound_point, solver_options = OPTS)

# vpn: phase-to-neutral voltage at one bus = size of (phase voltage - neutral voltage), built from
# the real (vr) and imaginary (vi) parts
vpn(ts, ph) = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - complex(ts["n"]["vr"], ts["n"]["vi"]))

# Highest phase-to-neutral voltage; only = set of (bus, phase) to restrict.
# Returns (highest voltage in V, where it is, e.g. "b828 b-n"); the two medium-voltage buses are
# skipped
function max_pn(snapshot; only = nothing)
    best, where = -Inf, ""
    for (bid, ts) in snapshot["bus"]
        bid in MV_BUSES && continue
        haskey(ts, "n") || continue
        for ph in ("a", "b", "c")
            haskey(ts, ph) || continue
            # If `only` is given, skip any point not in it (for example, keep only the 12 customer
            # points)
            only === nothing || (bid, ph) in only || continue
            v = vpn(ts, ph)
            # Remember the highest voltage so far and where it was
            v > best && (best = v; where = "$bid $ph-n")
        end
    end
    return best, where
end

# Per-house table and which limit is binding.
function house_report(snap, net, r)
    @printf("  %-16s %9s %10s %9s\n", "house", "limit kW", "V_pn (V)", "S/5kVA")
    smax_ratio = 0.0
    # One line per home: its limit (kW), its voltage, and how full its 5 kVA inverter is (S/5kVA,
    # 1.0 = completely full)
    for (id, inv) in sort(collect(net["ibr"]); by = first)
        ph = String(inv["terminal_map"][1])
        v  = vpn(snap["bus"][inv["bus"]], ph)
        g  = get(get(get(snap, "ibr", Dict()), id, Dict()), ph, nothing)
        # How full the inverter is: sqrt(P^2 + Q^2) of its output divided by its rating s_max
        s  = g === nothing ? NaN : hypot(g["pg"], g["qg"]) / inv["s_max"][1]
        isfinite(s) && (smax_ratio = max(smax_ratio, s))
        @printf("  %-16s %9.3f %10.2f %9.3f\n", id, r.envelope[id][1] / 1000, v, s)
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    # What stops more export: the inverter is full (above 0.999), else a home is at 253 V (within
    # 0.01 V), else the 5 kW nameplate cap
    lim = smax_ratio > 0.999 ? "inverter rating (5 kVA, with Volt-VAr absorption)" :
          vc >= V_MAX_PN - 0.01 ? "voltage limit (253 V at a customer)" :
          "export_max (5 kW nameplate)"
    println("  -> export is limited by: ", lim)
end