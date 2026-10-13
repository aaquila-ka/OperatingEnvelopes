# scripts/bmopf/doe_ratio.jl
#
# STEP (b): how much does the cable resistance ratio matter?
# The dataset's line codes give 4 mm2 / 16 mm2 = 3.07 (its 16 mm2 code is about 30 % above the
# IEC 60228 maximum, its 4 mm2 code close to IEC). IEC 60228 maximum DC values give about 4.0.
# Records always say 16 mm2 (dataset code). The TRUE street has all 22 service cables:
#   dataset_4mm2_code   : the dataset's 4 mm2 line code (whole code swapped; ratio 3.07)  [as before]
#   diagR_x3.07         : 16 mm2 code with diagonal R x 3.07 (consistency check vs the swap)
#   diagR_x4.00_IEC     : 16 mm2 code with diagonal R x 4.0 (IEC-like ratio)
# Settings: 1 kW snapshot, 11:30 and 12:00 of the real day; source 1.03 pu; equal allocation.
# Reports the correct DOE, the gap, and the realised voltage with Volt-Watt on: worst case
# (may export the full issued DOE) and sun-limited (cap = min(DOE, 5 kW x pv_shape)).
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_ratio.jl")
#   julia> run_ratio()
# OUTPUT results/doe_ratio.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_robust.jl"))

function run_ratio(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    settings = [("snapshot_1kW", net -> net, NaN),
                ("day_1130", net -> set_loads!(net, pmap, P, Q, 24), PV_KW * pv[24]),
                ("day_1200", net -> set_loads!(net, pmap, P, Q, 25), PV_KW * pv[25])]
    variants = [("dataset_4mm2_code", net -> all_small!(net)),
                ("diagR_x3.07",       net -> scale_R_all!(net, 3.07)),
                ("diagR_x4.00_IEC",   net -> scale_R_all!(net, 4.0))]
    println("setting        variant             | clean kW  correct kW  gap kW  over-prom | worst V(VW) >253 | sun cap  sun V(VW) >253")
    rows = String[]
    for (sname, prep, pvsun) in settings
        clean = ts_doe(prep(make_net(pu)))[1]
        for (vname, wrong) in variants
            truth = wrong(prep(make_net(pu)))
            a     = ts_doe(truth)[1]
            w     = re_realised(truth, clean)
            cap   = isnan(pvsun) ? NaN : min(clean, pvsun)
            p     = isnan(cap) ? (v = NaN, n_over = 0, curtail_kW = NaN, status = "n/a") : re_realised(truth, cap)
            gap   = clean - a
            over  = 100 * (clean / a - 1)
            @printf("%-13s  %-18s  | %7.3f    %7.3f   %+6.3f  %+7.1f %% |  %7.2f    %3d  | %6.3f   %7.2f   %3d\n",
                    sname, vname, clean, a, gap, over, w.v, w.n_over, cap, p.v, p.n_over)
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
