# =============================================================================
# doe_dropout_service_lv3.jl: dropout-secure headline redone with PLAUSIBLE service errors
#
# What it does (plain English):
#   Same question as doe_dropout_records_lv3.jl, but the true networks now use the
#   plausible service-connection errors from doe_service_errors.jl (after Fred Geth's
#   email, Oct 2026) instead of 4 mm2 cables:
#     type_l3432      : only the critical home's service (l_3432, 29.5 m, b828) is really
#                       overhead 16 mm2 ABC (abc4x16, LV3's own line code)
#     type_all12      : all 12 home services are really abc4x16
#     lengthbias_1.25 : every home service 25 % longer than recorded (route not modelled)
#     lengthbias_1.50 : every home service 50 % longer than recorded
#     wiring_100      : every home has meter-to-inverter wiring at the full AS/NZS 4777.1
#                       1 % allowance (loop R 0.1058 ohm)
#   The utility only knows its records (every service 16 mm2 Cu, no house wiring) and issues
#   the DROPOUT-SECURE equal DOE on them (read from results/doe_dropout_secure_lv3.csv).
#   For each true network: (1) does the issued DOE break 253 V on the true network, in how
#   many of the dropout cases; (2) what would the correct dropout-secure DOE have been
#   (bisection, same rules as doe_dropout_records_lv3.jl). gap_pct = gap / correct x 100.
# Inputs:   results/doe_dropout_secure_lv3.csv, LV3 network and house profiles.
#           Includes doe_dropout_records_lv3.jl (-> doe_dropout_lv3.jl) and doe_service_errors.jl.
# Outputs:  results/doe_dropout_service_lv3.csv (one row per setting x truth)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, FRESH session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_timeseries.jl")
#   include("scripts/bmopf/doe_dropout_service_lv3.jl")
#   run_dropout_service_lv3()        # both settings, about 15 min
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data);
#           error types from F. Geth (pers. comm., Oct 2026); AS/NZS 4777.1 voltage rise
# =============================================================================

isdefined(Main, :run_dropout_records_lv3) ||
    include(joinpath(pwd(), "scripts", "bmopf", "doe_dropout_records_lv3.jl"))
isdefined(Main, :se_apply_type!) ||
    include(joinpath(pwd(), "scripts", "bmopf", "doe_service_errors.jl"))

# each truth takes a network, changes it, and RETURNS it (mk() needs the network back)
const SE_DO_TRUTHS = [
    ("type_l3432",      net -> (net["line"]["l_3432"]["linecode"] = SE_ABC_LC; net)),
    ("type_all12",      net -> (se_apply_type!(net, 12, MersenneTwister(0)); net)),
    ("lengthbias_1.25", net -> (se_apply_lengthbias!(net, 1.25); net)),
    ("lengthbias_1.50", net -> (se_apply_lengthbias!(net, 1.50); net)),
    ("wiring_100",      net -> (se_apply_wiring!(net, 1.0); net)),
]

function run_dropout_service_lv3(; pu = RE_PU, depth = 2, settings = DO_SETTINGS)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for setting in settings
        issued = rec_issued_kw(setting, pu)
        ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
        @printf("\n=== %s, %.3f pu: issued dropout-secure DOE (records) = %.3f kW, %d cases ===\n",
                setting, pu, issued, length(sets))
        for (tname, truth!) in SE_DO_TRUTHS
            mk = () -> truth!(do_net(setting, pu, pmap, P, Q))
            on_true = rec_check(mk, ids, sets, issued; early_stop = false)
            correct = rec_doe(mk, ids, sets, issued)
            gap = issued - correct
            @printf("  truth %-16s | issued on true network: worst %.2f V (%s, %d customers over), cases over 253 V: %d of %d\n",
                    tname, on_true.v, on_true.worst, on_true.worst_n, on_true.nfail, length(sets))
            @printf("  %-22s | correct dropout-secure DOE %.3f kW -> issued is %.3f kW (%.1f %%) too high  [%.0f s]\n",
                    "", correct, gap, correct > 0 ? 100 * gap / correct : NaN, time() - t0)
            push!(rows, @sprintf("%s,%.3f,%s,%.6f,%.6f,%.6f,%.3f,%.4f,\"%s\",%d,%d,%d",
                                 setting, pu, tname, issued, correct, gap,
                                 correct > 0 ? 100 * gap / correct : NaN,
                                 on_true.v, on_true.worst, on_true.worst_n, on_true.nfail, length(sets)))
        end
    end
    open(joinpath(pwd(), "results", "doe_dropout_service_lv3.csv"), "w") do io
        println(io, "setting,source_pu,truth,issued_kW_records,correct_kW_true,gap_kW,gap_pct,issued_on_true_worst_V,worst_case,worst_case_customers_over_253,cases_over_253,n_cases")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_dropout_service_lv3.csv (%.0f min)\n", (time() - t0) / 60)
end
