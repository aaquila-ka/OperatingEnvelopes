# =============================================================================
# doe_dropout_records_lv3.jl: headline result redone with the dropout-secure DOE (LV3)
#
# What it does (plain English):
#   The utility only knows its records (every service cable recorded as 16 mm2) and computes
#   the DROPOUT-SECURE equal DOE on them (read from results/doe_dropout_secure_lv3.csv). The
#   real network has 4 mm2 cables. Questions:
#     (1) Applied on the TRUE network, does the issued DOE still break 253 V, and in how many
#         of the 85 cases (nobody dropped + 6 other phase patterns + every 1 or 2 customers
#         dropped)?
#     (2) What would the dropout-secure DOE have been with CORRECT records, i.e. how much too
#         generous is the issued one? (gap = issued - correct; gap_pct = gap / correct x 100)
#   Two "true" networks: all 22 service segments 4 mm2 ("all22_wrong"), and only the critical
#   customer cable l_3432 4 mm2 ("l_3432_wrong"). Settings: 1 kW snapshot and 12:00, 1.03 pu.
#   Realised reading as before (Volt-VAr, Volt-Watt, 5 kVA kept; no voltage limit).
#   The correct DOE is found by bisection between 0 and the issued DOE (12 steps, grid about
#   issued / 4096 = 0.001 kW), so it can never come out above the issued DOE, and two truths
#   that give the same pass/fail answers land on the same grid value.
#
# Inputs:   results/doe_dropout_secure_lv3.csv (from run_dropout_secure_lv3, REPRODUCE step
#           26), LV3 network and house profiles. Includes doe_dropout_lv3.jl.
# Outputs:  results/doe_dropout_records_lv3.csv (4 rows); prints two lines per truth.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_dropout_records_lv3.jl")   then   run_dropout_records_lv3()
#   (about 6 min)
# Used for: REPRODUCE.md step 28 (section 4 row "LV3 headline, dropout-secure");
#           DATA_CARD.md file 22.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_dropout_lv3.jl"))

const REC_TRUTHS = [("all22_wrong",  net -> all_small!(net)),
                    ("l_3432_wrong", net -> one_wrong!(net, "l_3432"))]

# issued (records-based) dropout-secure DOE for a setting, from the earlier run
function rec_issued_kw(setting, pu)
    file = joinpath(pwd(), "results", "doe_dropout_secure_lv3.csv")
    isfile(file) || error("missing $file: run run_dropout_secure_lv3() first")
    lines = collect(eachline(file)); hdr = split(lines[1], ",")
    is = findfirst(==("setting"), hdr); ip = findfirst(==("source_pu"), hdr)
    ik = findfirst(==("dropout_secure_kW"), hdr)
    for l in lines[2:end]
        f = split(l, ",")
        f[is] == setting && abs(parse(Float64, f[ip]) - pu) < 1e-6 && return parse(Float64, f[ik])
    end
    error("no row for $setting at $pu pu in $file")
end

# check one limit on a network built by mk(); stop at first failure when early_stop
function rec_check(mk, ids, sets, kw; early_stop = true)
    worst_v = -Inf; worst = ""; worst_n = 0; nfail = 0
    for dropped in sets
        rv = do_case(mk(), ids, dropped, kw)
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail
        rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped); worst_n = rv.n_over)
        fail && early_stop && return (ok = false, v = rv.v, worst = do_label(dropped), worst_n = rv.n_over, nfail = nfail)
    end
    return (ok = nfail == 0, v = worst_v, worst = worst, worst_n = worst_n, nfail = nfail)
end

# highest equal limit that is safe for all cases on the network built by mk() (bisection 0..hi)
function rec_doe(mk, ids, sets, hi; iters = 12)
    rec_check(mk, ids, sets, hi).ok && return hi
    lo = 0.0
    for it in 1:iters
        mid = (lo + hi) / 2
        rec_check(mk, ids, sets, mid).ok ? (lo = mid) : (hi = mid)
    end
    return lo
end

function run_dropout_records_lv3(; pu = RE_PU, depth = 2)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for setting in DO_SETTINGS
        issued = rec_issued_kw(setting, pu)
        ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
        @printf("\n=== %s, %.3f pu: issued dropout-secure DOE (records, 16 mm2) = %.3f kW, %d cases ===\n",
                setting, pu, issued, length(sets))
        for (tname, truth!) in REC_TRUTHS
            mk = () -> truth!(do_net(setting, pu, pmap, P, Q))
            on_true = rec_check(mk, ids, sets, issued; early_stop = false)
            correct = rec_doe(mk, ids, sets, issued)
            gap = issued - correct
            @printf("  truth %-13s | issued on true network: worst %.2f V (%s, %d customers over), cases over 253 V: %d of %d\n",
                    tname, on_true.v, on_true.worst, on_true.worst_n, on_true.nfail, length(sets))
            @printf("  %-19s | correct dropout-secure DOE %.3f kW -> issued is %.3f kW (%.1f %%) too generous  [%.0f s]\n",
                    "", correct, gap, 100 * gap / correct, time() - t0)
            push!(rows, @sprintf("%s,%.3f,%s,%.6f,%.6f,%.6f,%.3f,%.4f,\"%s\",%d,%d,%d",
                                 setting, pu, tname, issued, correct, gap, 100 * gap / correct,
                                 on_true.v, on_true.worst, on_true.worst_n, on_true.nfail, length(sets)))
        end
    end
    open(joinpath(pwd(), "results", "doe_dropout_records_lv3.csv"), "w") do io
        println(io, "setting,source_pu,truth,issued_kW_records,correct_kW_true,gap_kW,gap_pct,issued_on_true_worst_V,worst_case,worst_case_customers_over_253,cases_over_253,n_cases")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_dropout_records_lv3.csv (%.0f min)\n", (time() - t0) / 60)
end
