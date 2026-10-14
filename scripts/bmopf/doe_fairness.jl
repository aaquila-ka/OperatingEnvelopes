# =============================================================================
# doe_fairness.jl: does the sharing rule decide who pays for a wrong cable record?
#
# What it does (plain English):
#   Computes per-customer export limits under three PowerOptLab sharing rules: :equal (used
#   elsewhere), :proportional (maximise sum of log) and :max_min (raise the smallest limit
#   first, then the total). Issued limits = rule applied on the records (all 16 mm2); correct
#   limits = rule applied on the TRUE street; per-customer gap = issued - correct. The issued
#   limits are then applied on the true street (realised reading: inverters keep Volt-VAr,
#   Volt-Watt and 5 kVA; no voltage limit imposed).
#   True-street cases: l_3432 wrong (only customer Ld1291's cable is really 4 mm2, the critical
#   one), l_4155 wrong (only Ld1668's cable, the mildest one), all 22 wrong (Case A).
#   Settings: CSIRO 1 kW snapshot and the 12:00 loads of the profile day; source 1.03 pu.
#   Also defines fr_realised(), the realised reading reused by doe_partial_lv3.jl and the
#   dropout scripts. In fr_realised a customer with limit 0 is given a 1 W cap (export_max
#   floor), so it may still inject up to 1 W and curtail_kW comes out about 0.001 kW lower per
#   such customer (visible as -0.004 / -0.008 in results/doe_partial_lv3.csv).
#   Note: curtail_kW mixes Volt-Watt and 5 kVA cutback, and BMOPF's smoothed Volt-Watt corner
#   overstates it by about 5 % when many customers sit just above 253 V (voltages unaffected).
#
# Inputs:   LV3 network and house profiles (as doe_timeseries.jl). Includes doe_timeseries.jl.
# Outputs:  results/doe_fairness_summary.csv (18 rows), results/doe_fairness_customers.csv
#           (216 rows); prints a summary table. Records which customers are above 253 V.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_fairness.jl")   then   run_fairness()
# Used for: REPRODUCE.md step 13 (section 4 row "Sharing rules"; section 6 item 3);
#           DATA_CARD.md files 11 and 12.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

# The three sharing rules to compare
const FR_POLICIES = [:equal, :proportional, :max_min]

# Solves the DOE (DOE = the export limit each home gets) under one sharing rule; returns each home's limit
# in kW (NaN for all if the solve failed) and the solver status
function fr_doe(net, policy)
    cps = connection_points(net)
    r = solve_operating_envelope(net, cps; fairness = policy, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    ok = isfinite(r.total_capacity[1])
    # Per-home limits in kW, keyed by the inverter (connection point) id
    caps = Dict(cp.id => (ok ? r.envelope[cp.id][1] / 1000 : NaN) for cp in cps)
    return caps, string(r.termination_status[1])
end

# issued per-customer limits applied on a street: physical outcome
# Realised reading for a SET of per-home limits: homes export up to their own cap with the inverter rules
# (Volt-VAr / Volt-Watt from AS/NZS 4777.2) and 5 kVA on, no voltage limit; returns the highest customer
# voltage, how many customers are above 253 V, total curtailment and which customers are over
function fr_realised(net, caps)
    # If the limits themselves are missing (failed solve), there is nothing to read
    all(isfinite, values(caps)) || return (v = NaN, n_over = -1, curtail_kW = NaN, who = "")
    # Copy the street and remove every voltage limit, so only physics and the inverter rules decide
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in RE_BUS_LIMIT_KEYS
        delete!(b, k)
    end
    # Each home's cap is its own issued limit (in W), with a 1 W floor so a 0 limit still gives a valid cap
    cps = [ConnectionPoint(id = cp.id, bus = cp.bus, phase_terminals = cp.phase_terminals,
                           neutral = cp.neutral, export_max = max(1000.0 * caps[cp.id], 1.0),
                           ibr_id = cp.ibr_id) for cp in connection_points(ev)]
    # Let the solver push total export as high as it can inside those caps
    r = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, curtail_kW = NaN, who = "")
    snap = r.snapshots[1]
    # Highest phase-to-neutral voltage (what a home feels) at a customer
    v, _ = max_pn(snap; only = customer_points(net))
    # Customers whose own voltage is above 253.005 V (253 V plus a tiny tolerance), as "bus phase-n" names
    over = [pt for pt in collect(customer_points(net)) if max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005]
    who  = join(["$(pt[1]) $(pt[2])-n" for pt in sort(over)], ";")
    # Curtailment: how far each home ended up below its cap, added over all homes
    curtail = sum(caps[cp.id] - r.envelope[cp.id][1] / 1000 for cp in cps)
    return (v = v, n_over = length(over), curtail_kW = curtail, who = who)
end

# Makes one chosen segment the thin 4 mm2 cable
function one_wrong!(net, seg)
    net["line"][seg]["linecode"] = RE_SMALL_LC
    return net
end

# Main run: for each setting and sharing rule, issued limits from the records, then for each wrong-cable case
# the correct limits, the per-home gaps and the realised reading; writes the two CSVs
function run_fairness(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # Two settings: the snapshot keeps the CSIRO loads; "day_1200" puts on the half-hour 25 (12:00) loads
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    # Three true-street cases: only l_3432 wrong, only l_4155 wrong, all 22 wrong (Case A)
    cases = [("l_3432_wrong", net -> one_wrong!(net, "l_3432")),
             ("l_4155_wrong", net -> one_wrong!(net, "l_4155")),
             ("all22_wrong",  net -> all_small!(net))]
    srows = String[]; crows = String[]
    for (sname, prep) in settings, policy in FR_POLICIES
        # Issued limits: the sharing rule applied on the records (all 16 mm2)
        issued, ist = fr_doe(prep(make_net(pu)), policy)
        ids = sort(collect(keys(issued)))
        @printf("\n=== %s, %s: issued total %.2f kW, min %.3f, max %.3f kW [%s] ===\n", sname, policy,
                sum(values(issued)), minimum(values(issued)), maximum(values(issued)), ist)
        println("  case           correct total  min     | customers changed  total gap  max gap (who)          | realised V  >253  curtail  over 253 V at")
        for (cname, wrong) in cases
            # True street for this case, and the correct limits on it under the same rule
            truth = wrong(prep(make_net(pu)))
            correct, cst = fr_doe(truth, policy)
            # Per-home gap = issued - correct (kW)
            gaps = Dict(id => issued[id] - correct[id] for id in ids)
            # Count homes whose limit changes by more than 0.05 kW
            nchg = count(id -> abs(gaps[id]) > 0.05, ids)
            # The home with the largest gap
            worst = ids[argmax([gaps[id] for id in ids])]
            # Realised reading of the issued limits on the true street
            rv = fr_realised(truth, issued)
            @printf("  %-13s  %7.2f  %6.3f   |   %2d of 12        %+6.2f     %+6.3f (%-14s) |  %7.2f    %2d   %6.3f   %s\n",
                    cname, sum(values(correct)), minimum(values(correct)), nchg,
                    sum(values(gaps)), gaps[worst], worst, rv.v, rv.n_over, rv.curtail_kW,
                    rv.n_over > 4 ? "($(rv.n_over) customers)" : rv.who)
            # Summary CSV row: issued and correct totals, how many homes changed, gaps, realised reading, solver statuses
            push!(srows, @sprintf("%s,%.3f,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%.6f,%.6f,%s,%.4f,%d,%.6f,\"%s\",%s,%s",
                                  sname, pu, policy, cname, sum(values(issued)), minimum(values(issued)),
                                  maximum(values(issued)), sum(values(correct)), minimum(values(correct)), nchg,
                                  sum(values(gaps)), gaps[worst], worst, rv.v, rv.n_over, rv.curtail_kW, rv.who, ist, cst))
            for id in ids
                # Per-home CSV row: issued, correct and gap for each home
                push!(crows, @sprintf("%s,%.3f,%s,%s,%s,%.6f,%.6f,%.6f",
                                      sname, pu, policy, cname, id, issued[id], correct[id], gaps[id]))
            end
        end
    end
    # Write the summary file, then the per-home file
    open(joinpath(pwd(), "results", "doe_fairness_summary.csv"), "w") do io
        println(io, "setting,source_pu,policy,case,issued_total_kW,issued_min_kW,issued_max_kW,correct_total_kW,correct_min_kW,n_customers_changed,total_gap_kW,max_gap_kW,max_gap_customer,realised_V_VW,n_customers_over_253,curtail_kW,customers_over_253,issued_status,correct_status")
        foreach(l -> println(io, l), srows)
    end
    open(joinpath(pwd(), "results", "doe_fairness_customers.csv"), "w") do io
        println(io, "setting,source_pu,policy,case,customer,issued_kW,correct_kW,gap_kW")
        foreach(l -> println(io, l), crows)
    end
    @printf("\nwritten results/doe_fairness_summary.csv (%d rows) and doe_fairness_customers.csv (%d rows)  (%.0f s)\n",
            length(srows), length(crows), time() - t0)
end
