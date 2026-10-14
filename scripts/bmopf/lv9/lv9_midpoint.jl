# =============================================================================
# lv9_midpoint.jl: the whole LV9 dropout-secure chain at extra source voltages (default 0.97 pu)
#
# What it does (plain English): runs every LV9 step at another source voltage in one go and
#   writes it to its OWN file, so the 0.94 / 1.00 pu results are not overwritten:
#     1. bound-point equal DOE and phase-secure DOE (7 phase patterns, verify_operating_envelope)
#     2. dropout-secure DOE (realised reading; bisection on nobody + 6 phase patterns, then a
#        final check over 130 cases: nobody, 6 phase patterns, each customer dropped)
#     3. headline: issued dropout-secure DOE (records, 16 mm2) on the true network for
#        "upstream_12" and "l_2373"; correct dropout-secure DOE on the true network; final
#        check. Gap = issued minus correct.
#   Same methods as lv9_phase_secure.jl, lv9_dropout.jl and lv9_dropout_records.jl.
# Inputs:   data/networks/LV9_258bus_withPV/; includes lv9_core.jl and lv9_dropout.jl
#           (which brings in lv9_common.jl and phase_secure_core.jl). Reads no earlier csv.
# Outputs:  results/lv9/lv9_midpoint_<pu>.csv (one file per source voltage); progress printed.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_midpoint.jl")   then
#   run_lv9_midpoint()                         # 0.97 pu, about 25-35 min
#   run_lv9_midpoint(pus = [0.96, 0.98])       # other points if wanted
# Used for: the 0.97 pu LV9 result (dropout-secure 1.876 kW, gap 0.430 kW with the 12 shared
#           segments wrong; results/lv9/lv9_midpoint_0.97.csv). REPRODUCE.md step 31.
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_core.jl"))       # segment_sets, set_small!
include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_dropout.jl"))    # lv9_dropout_sets, lv9_check, ps_doe

# highest equal kw in [lo0, hi] passing lv9_check on `sets` (bisection); returns lo.
# Never returns more than hi, so a correct DOE found this way gives a gap of 0 or more.
function lv9_bisect(net, ids, sets, hi; lo0 = 0.0, iters = 10)
    lv9_check(net, ids, sets, hi).ok && return hi
    lo = lo0
    if lo > 0 && !lv9_check(net, ids, sets, lo).ok
        lo = 0.0; iters += 4
    end
    for it in 1:iters
        mid = (lo + hi) / 2
        lv9_check(net, ids, sets, mid).ok ? (lo = mid) : (hi = mid)
    end
    return lo
end

function run_lv9_midpoint(; pus = [0.97], truths = ["upstream_12", "l_2373"])
    t0 = time()
    drops, up, _, _, _, _, _, _ = segment_sets(make_net(1.00))
    truth_ids = Dict("upstream_12" => up, "l_2373" => ["l_2373"], "drops_123" => drops)
    for pu in pus
        rows = String[]
        net = make_net(pu)
        ids, sets = lv9_dropout_sets(net)
        psets = sets[1:7]
        # 1. bound-point and phase-secure
        bound, b, _, _, _ = eq_doe(make_net(pu))
        sec, _ = ps_doe(make_net(pu), bound)
        @printf("\n=== LV9 %.3f pu: bound-point %.3f kW (%s), phase-secure %.3f kW (%+.1f %%)  [%.0f min]\n",
                pu, bound, b, sec, 100 * (sec / bound - 1), (time() - t0) / 60)
        # 2. dropout-secure
        ds  = lv9_bisect(net, ids, psets, sec; lo0 = 0.9 * sec, iters = 8)
        chk = lv9_check(net, ids, sets, ds; early_stop = false)
        @printf("  dropout-secure %.3f kW (%+.1f %% vs bound point); final check: worst %.2f V (%s), over 253 V: %d of %d  [%.0f min]\n",
                ds, 100 * (ds / bound - 1), chk.v, chk.worst, chk.nfail, length(sets), (time() - t0) / 60)
        push!(rows, @sprintf("%.3f,clean,%.6f,%.6f,%.6f,%.6f,0,0,%.4f,%s,%d,%.4f,%d",
                             pu, bound, sec, ds, ds, chk.v, chk.worst, chk.nfail, chk.v, chk.nfail))
        # 3. headline with wrong records
        for tname in truths
            tnet = set_small!(make_net(pu), truth_ids[tname])
            on_true = lv9_check(tnet, ids, sets, ds; early_stop = false)
            correct = lv9_bisect(tnet, ids, psets, ds)
            fin = lv9_check(tnet, ids, sets, correct; early_stop = false)
            gap = ds - correct
            @printf("  truth %-12s | issued on true: worst %.2f V (%s), cases over 253 V: %d of %d\n",
                    tname, on_true.v, on_true.worst, on_true.nfail, length(sets))
            @printf("  %-18s | correct %.3f kW -> issued %.3f kW (%.1f %%) too generous; final check worst %.2f V, over: %d  [%.0f min]\n",
                    "", correct, gap, 100 * gap / correct, fin.v, fin.nfail, (time() - t0) / 60)
            push!(rows, @sprintf("%.3f,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.3f,%.4f,%s,%d,%.4f,%d",
                                 pu, tname, bound, sec, ds, correct, gap, 100 * gap / correct,
                                 on_true.v, on_true.worst, on_true.nfail, fin.v, fin.nfail))
        end
        file = joinpath(pwd(), "results", "lv9", @sprintf("lv9_midpoint_%.2f.csv", pu))
        open(file, "w") do io
            println(io, "source_pu,truth,bound_point_kW,phase_secure_kW,dropout_secure_kW_issued,correct_dropout_secure_kW,gap_kW,gap_pct,issued_on_true_worst_V,worst_case,cases_over_253_of_130,correct_final_worst_V,correct_final_n_fail")
            foreach(l -> println(io, l), rows)
        end
        println("written ", file)
    end
    @printf("\ndone (%.0f min)\n", (time() - t0) / 60)
end
