# =============================================================================
# doe_ratio.jl: does the 4 mm2 / 16 mm2 resistance ratio matter? (3.07 dataset vs 4.0 test)
#
# What it does (plain English):
#   The dataset's line codes give 4 mm2 / 16 mm2 = 3.07. This script also tests a
#   higher ratio of 4.0 (the variant name ends in _IEC; that is only a label, the
#   value is not cited from the standard here). Records always say 16 mm2 (dataset
#   code). The TRUE street has all 22 service-cable segments:
#     dataset_4mm2_code : the dataset's 4 mm2 line code (whole code swapped; ratio 3.07),
#                         the same as in every other script
#     diagR_x3.07       : 16 mm2 code with diagonal R x 3.07 (consistency check vs the swap)
#     diagR_x4.00_IEC   : 16 mm2 code with diagonal R x 4.0 (higher test ratio)
#   Settings: 1 kW snapshot, 11:30 and 12:00 of the real day; source 1.03 pu; equal
#   allocation. Reports the correct DOE, the gap, and the realised voltage with
#   Volt-Watt on: worst case (may export the full issued DOE) and sun-limited
#   (cap = min(DOE, 5 kW x pv_shape)). Snapshot rows have no sun limit: pv_* columns
#   are NaN and pv_n_over_253 = 0 there means "not applicable".
# Inputs:   includes doe_robust.jl (for scale_R_all!; it includes doe_timeseries.jl ->
#           doe_record_errors.jl -> doe_common.jl -> load_lv3.jl);
#           data/profiles/TeamNando_OE1_LoadShapes.txt
# Outputs:  results/doe_ratio.csv (9 rows); prints a table
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_ratio.jl")   then   run_ratio()
# Used for: REPRODUCE.md step 14 and section 6 item 2 (ratio 4.0 at 12:00: correct
#           1.624 kW, gap 2.628 kW, +161.8 %)
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0);
#           Team-Nando OE1-Ideal load profiles (BSD-3); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_robust.jl"))

# Main run: for each setting and each way of making the true street's cables thinner, find the correct DOE
# (DOE = the export limit every home gets), the gap, and the realised readings; writes the CSV
function run_ratio(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # Settings: (name, how to set the loads, sun limit in kW); the snapshot has no sun limit (NaN);
    # 11:30 and 12:00 are half-hours 24 and 25, with sun limit = 5 kW x the sun shape
    settings = [("snapshot_1kW", net -> net, NaN),
                ("day_1130", net -> set_loads!(net, pmap, P, Q, 24), PV_KW * pv[24]),
                ("day_1200", net -> set_loads!(net, pmap, P, Q, 25), PV_KW * pv[25])]
    # Three true streets: the dataset's 4 mm2 code (ratio 3.07), 16 mm2 x 3.07 (should match it), 16 mm2 x 4.0
    variants = [("dataset_4mm2_code", net -> all_small!(net)),
                ("diagR_x3.07",       net -> scale_R_all!(net, 3.07)),
                ("diagR_x4.00_IEC",   net -> scale_R_all!(net, 4.0))]
    println("setting        variant             | clean kW  correct kW  gap kW  over-prom | worst V(VW) >253 | sun cap  sun V(VW) >253")
    rows = String[]
    for (sname, prep, pvsun) in settings
        # Issued DOE = the clean DOE on the records (all 16 mm2); [1] keeps just the kW value
        clean = ts_doe(prep(make_net(pu)))[1]
        for (vname, wrong) in variants
            # True street for this variant, and its correct DOE
            truth = wrong(prep(make_net(pu)))
            a     = ts_doe(truth)[1]
            # Realised reading, worst case: homes may export up to the full issued DOE with Volt-VAr / Volt-Watt
            # (AS/NZS 4777.2 inverter rules) on, no voltage limit; then we read the voltage
            w     = re_realised(truth, clean)
            # Sun-limited cap = the smaller of the issued DOE and what the sun gives; none for the snapshot
            cap   = isnan(pvsun) ? NaN : min(clean, pvsun)
            # Sun-limited realised reading (for the snapshot, a placeholder with n_over = 0, meaning "not applicable")
            p     = isnan(cap) ? (v = NaN, n_over = 0, curtail_kW = NaN, status = "n/a") : re_realised(truth, cap)
            # Gap in kW, and how much too generous the records' limit is, in %: 100 x (issued / correct - 1)
            gap   = clean - a
            over  = 100 * (clean / a - 1)
            @printf("%-13s  %-18s  | %7.3f    %7.3f   %+6.3f  %+7.1f %% |  %7.2f    %3d  | %6.3f   %7.2f   %3d\n",
                    sname, vname, clean, a, gap, over, w.v, w.n_over, cap, p.v, p.n_over)
            # One CSV row: DOEs, gap, over-promise, then the worst-case and sun-limited readings
            push!(rows, @sprintf("%s,%.3f,%s,%.6f,%.6f,%.6f,%.3f,%.4f,%d,%.6f,%.6f,%.4f,%d,%.6f",
                                 sname, pu, vname, clean, a, gap, over, w.v, w.n_over, w.curtail_kW,
                                 cap, p.v, p.n_over, p.curtail_kW))
        end
    end
    open(joinpath(pwd(), "results", "doe_ratio.csv"), "w") do io
        println(io, "setting,source_pu,variant,clean_kW,correct_kW,gap_kW,overpromise_pct,worst_V_VW,worst_n_over_253,worst_curtail_kW,pv_cap_kW,pv_V_VW,pv_n_over_253,pv_curtail_kW")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_ratio.csv (%d rows, %.0f s)\n", length(rows), time() - t0)
end
