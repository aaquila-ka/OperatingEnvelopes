# =============================================================================
# doe_verify_proportional.jl: checking cable records one by one under PROPORTIONAL sharing
#
# What it does (plain English):
#   Same idea as Part B of doe_robust.jl (the 12 customer cables are checked one by one;
#   unchecked ones are assumed to be the thinnest type, 4 mm2, so the DOE is safe up to the
#   small non-monotone effect noted in doe_robust.jl), but each customer's limit is set by
#   PowerOptLab fairness = :proportional instead of :equal. Reports the TOTAL safe export (sum
#   of the 12 limits) after k checks as a share of the total when all records are right, plus
#   the smallest limit. Equal-rule totals (12 x the equal DOE) are computed alongside.
#   Orders: OPF-ranked and shortest first. Settings: 1 kW snapshot and 12:00 loads; 1.03 pu.
#
# Inputs:   LV3 network and house profiles. Includes doe_robust.jl (-> doe_timeseries.jl ->
#           doe_record_errors.jl -> doe_common.jl -> load_lv3.jl).
# Outputs:  results/doe_verify_proportional.csv (52 rows); prints a table per order.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_verify_proportional.jl")   then   run_verify_proportional()
# Used for: REPRODUCE.md step 16 (section 4 row "Checking under proportional, 12:00");
#           DATA_CARD.md file 15.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_robust.jl"))

# Solves the DOE (DOE = the export limit each home gets) under one sharing rule; returns the total of the
# 12 limits (kW), the smallest one, and the solver status
function vp_doe(net, policy)
    cps = connection_points(net)
    r = solve_operating_envelope(net, cps; fairness = policy, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    lim = [r.envelope[cp.id][1] / 1000 for cp in cps]
    return sum(lim), minimum(lim), string(r.termination_status[1])
end

# Street where the first k cables in `order` have been checked (left at 16 mm2) and the rest are assumed 4 mm2
function checked_net(prep, pu, order, k)
    net = prep(make_net(pu))
    for id in order[k+1:end]
        net["line"][id]["linecode"] = RE_SMALL_LC
    end
    return net
end

# Main run: for each setting and checking order, the total safe export after k = 0..12 checks, under the
# proportional and the equal rule; writes the CSV
function run_verify_proportional(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # Two settings: the snapshot keeps the CSIRO loads; "day_1200" puts on the half-hour 25 (12:00) loads
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    rows = String[]
    for (sname, prep) in settings
        # The 12 home cables, longest first, and a check that they match the OPF ranking
        ids = customer_cables(prep(make_net(pu)))
        @assert Set(RB_OPF_ORDER) == Set(ids)
        # Totals when all records are right; each "share" below is a % of these
        cleanP, _, _ = vp_doe(prep(make_net(pu)), :proportional)
        cleanE, _, _ = vp_doe(prep(make_net(pu)), :equal)
        @printf("\n=== %s, %.3f pu: all records right -> proportional total %.2f kW, equal total %.2f kW ===\n",
                sname, pu, cleanP, cleanE)
        # Two orders: OPF-ranked (most harmful first) and shortest first
        for (oname, order) in (("opf_ranked", RB_OPF_ORDER), ("shortest_first", reverse(ids)))
            @printf("  order %s\n", oname)
            println("   k checked | proportional: total kW  share   min kW | equal: total kW  share")
            for k in 0:12
                # Same checked street solved under both rules
                tp, mp, stp = vp_doe(checked_net(prep, pu, order, k), :proportional)
                te, _, ste  = vp_doe(checked_net(prep, pu, order, k), :equal)
                # share = 100 x total after k checks / total with all records right
                @printf("   %2d        |  %7.2f        %5.1f %%  %6.3f |  %7.2f       %5.1f %%\n",
                        k, tp, 100 * tp / cleanP, mp, te, 100 * te / cleanE)
                # CSV row: setting, order, k, the cables checked so far, then the proportional and equal totals and shares
                push!(rows, @sprintf("%s,%.3f,%s,%d,\"%s\",%.6f,%.6f,%.3f,%.6f,%.6f,%.3f,%s,%s",
                                     sname, pu, oname, k, join(order[1:k], ";"),
                                     cleanP, tp, 100 * tp / cleanP, mp, te, 100 * te / cleanE, stp, ste))
            end
        end
    end
    open(joinpath(pwd(), "results", "doe_verify_proportional.csv"), "w") do io
        println(io, "setting,source_pu,order,k_checked,checked_segments,clean_total_prop_kW,prop_total_kW,prop_share_pct,prop_min_kW,equal_total_kW,equal_share_pct,prop_status,equal_status")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_verify_proportional.csv (%d rows, %.0f s)\n", length(rows), time() - t0)
end
