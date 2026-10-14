# scripts/bmopf/lv9/lv9_dropout_records.jl
#
# HEADLINE RESULT ON LV9, REDONE WITH THE SAFEST DOE (same idea as doe_dropout_records_lv3.jl).
# The utility only knows its records (16 mm2 everywhere the 16 mm2 code is used). It issues the
# DROPOUT-SECURE equal DOE computed on those records (results/lv9/lv9_dropout_secure.csv).
# The real network has 4 mm2 cables in some places ("truths"):
#   "upstream_12"  the 12 shared 16 mm2 cables are really 4 mm2
#   "l_2373"       only the shared cable l_2373 (43 customers behind it) is really 4 mm2
#   "drops_123"    every customer drop is really 4 mm2 (optional, add to `truths` if wanted)
# For each truth:
#   (1) the issued DOE is applied on the TRUE network for 130 cases (nobody dropped, 6 phase
#       patterns, each single customer dropped) -> worst voltage, cases over 253 V;
#   (2) the CORRECT dropout-secure DOE on the true network: bisection on nobody + 6 phase
#       patterns (the binding cases on LV9), then a final check over all 130 cases.
# Voltage limits only (no thermal limits). Realised reading (Volt-VAr, Volt-Watt, 5 kVA kept).
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/lv9/lv9_dropout_records.jl")
#   julia> run_lv9_dropout_records()          # 0.94 and 1.00 pu, 2 truths (~30-45 min)
# NEEDS   results/lv9/lv9_dropout_secure.csv  (from run_lv9_dropout_secure)
# OUTPUT  results/lv9/lv9_dropout_records.csv

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_core.jl"))       # segment_sets, set_small!
include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_dropout.jl"))    # lv9_dropout_sets, lv9_check

function lv9_issued_kw()
    file = joinpath(pwd(), "results", "lv9", "lv9_dropout_secure.csv")
    isfile(file) || error("missing $file: run run_lv9_dropout_secure() first")
    lines = collect(eachline(file)); hdr = split(lines[1], ",")
    ip = findfirst(==("source_pu"), hdr); ik = findfirst(==("dropout_secure_kW"), hdr)
    return Dict(round(parse(Float64, split(l, ",")[ip]); digits = 3) => parse(Float64, split(l, ",")[ik])
                for l in lines[2:end])
end

function run_lv9_dropout_records(; pus = [0.94, 1.00], truths = ["upstream_12", "l_2373"], iters = 10)
    t0 = time()
    issued_all = lv9_issued_kw()
    drops, up, _, _, ncust, _, _, _ = segment_sets(make_net(1.00))
    truth_ids = Dict("upstream_12" => up, "l_2373" => ["l_2373"], "drops_123" => drops)
    rows = String[]
    for pu in pus
        issued = issued_all[round(pu; digits = 3)]
        base = make_net(pu)
        ids, sets = lv9_dropout_sets(base)
        psets = sets[1:7]
        @printf("\n=== LV9 %.3f pu: issued dropout-secure DOE (records) = %.3f kW, %d cases ===\n",
                pu, issued, length(sets))
        for tname in truths
            tnet = set_small!(make_net(pu), truth_ids[tname])        # realised() copies it, so one is enough
            tb = time()
            on_true = lv9_check(tnet, ids, sets, issued; early_stop = false)
            # correct DOE: bisection 0 .. issued on the 7 binding cases, then full check
            lo, hi = 0.0, issued
            if lv9_check(tnet, ids, psets, hi).ok
                lo = hi
            else
                for it in 1:iters
                    mid = (lo + hi) / 2
                    lv9_check(tnet, ids, psets, mid).ok ? (lo = mid) : (hi = mid)
                end
            end
            correct = lo
            fin = lv9_check(tnet, ids, sets, correct; early_stop = false)
            gap = issued - correct
            @printf("  truth %-12s | issued on true network: worst %.2f V (%s), cases over 253 V: %d of %d\n",
                    tname, on_true.v, on_true.worst, on_true.nfail, length(sets))
            @printf("  %-18s | correct dropout-secure DOE %.3f kW -> issued is %.3f kW (%.1f %%) too generous\n",
                    "", correct, gap, 100 * gap / correct)
            @printf("  %-18s | final check of correct DOE: worst %.2f V, over 253 V: %d   [%.0f min]\n",
                    "", fin.v, fin.nfail, (time() - tb) / 60)
            push!(rows, @sprintf("%.3f,%s,%.6f,%.6f,%.6f,%.3f,%.4f,%s,%d,%d,%.4f,%d",
                                 pu, tname, issued, correct, gap, 100 * gap / correct,
                                 on_true.v, on_true.worst, on_true.nfail, length(sets), fin.v, fin.nfail))
        end
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_dropout_records.csv"), "w") do io
        println(io, "source_pu,truth,issued_kW_records,correct_kW_true,gap_kW,gap_pct,issued_on_true_worst_V,worst_case,cases_over_253,n_cases,correct_final_worst_V,correct_final_n_fail")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_dropout_records.csv (%.0f min)\n", (time() - t0) / 60)
end
