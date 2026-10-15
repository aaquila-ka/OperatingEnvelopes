# =============================================================================
# doe_timeseries_service.jl: the measured day (48 half-hours) redone with a PLAUSIBLE
#                            service-cable record error instead of 4 mm2
#
# What it does (plain English):
#   Exactly the day run of doe_timeseries.jl (same 12 house profiles, same steps, same three
#   readings, same CSV columns), but the TRUE street is built by a "truth" function instead of
#   all_small! (all 22 services 4 mm2). Default truth = the critical home's service (l_3432,
#   29.5 m, bus b828) is really overhead 16 mm2 aerial bundled cable (abc4x16, LV3's own line
#   code, about 1.59 x the phase resistance), while the records say underground 16 mm2 Cu.
#   Any other truth from doe_service_errors.jl can be passed in, e.g.
#     truth! = net -> (se_apply_lengthbias!(net, 1.25); net)
#   In the CSV the "A_" columns now mean "this truth" (kept so plotting code still works).
#   The summary at the end counts the half-hours where the records' basic DOE, limited by the
#   available sun (pv_VW reading), puts at least one home above 253 V.
# Inputs:   as doe_timeseries.jl. Includes doe_timeseries.jl and doe_service_errors.jl.
# Outputs:  results/doe_timeseries_type_l3432.csv (or the name given in `out`)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, FRESH session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_timeseries.jl")
#   include("scripts/bmopf/doe_timeseries_service.jl")
#   run_timeseries_service()
# Credits:  as doe_timeseries.jl; error type from F. Geth (pers. comm., Oct 2026)
# =============================================================================

isdefined(Main, :ts_step) ||
    include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))
isdefined(Main, :se_apply_type!) ||
    include(joinpath(pwd(), "scripts", "bmopf", "doe_service_errors.jl"))

const TSS_TRUTH_L3432 = net -> (net["line"]["l_3432"]["linecode"] = SE_ABC_LC; net)

# ---- same as ts_step, but the true street comes from truth!
function tss_step(t, pmap, P, Q, pv; pu = RE_PU, truth! = TSS_TRUTH_L3432)
    clean = set_loads!(make_net(pu), pmap, P, Q, t)
    small = truth!(set_loads!(make_net(pu), pmap, P, Q, t))
    c_kw, c_b, c_v, c_st = ts_doe(clean)
    a_kw, a_b, a_v, a_st = ts_doe(small)
    bp_v, bp_note = re_street(small, c_kw)
    w   = re_realised(small, c_kw)
    pvc = min(c_kw, PV_KW * pv[t])
    p   = re_realised(small, pvc)
    return (t = t, pv = pv[t], c_kw = c_kw, c_b = c_b, c_v = c_v, c_st = c_st,
            a_kw = a_kw, a_b = a_b, a_st = a_st,
            gap = c_kw - a_kw, over = 100 * (c_kw / a_kw - 1), lossB = 100 * (a_kw / c_kw - 1),
            bp_v = bp_v, bp_note = bp_note, w = w, pvc = pvc, p = p)
end

function run_timeseries_service(; steps = 1:48, pu = RE_PU, truth! = TSS_TRUTH_L3432,
                                out = "doe_timeseries_type_l3432.csv")
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    println("time   pv cap | records kW bind  | true kW gap kW  over-prom | bound V  worst V(VW) | sun-limited: V(VW) >253 curtail")
    rows = String[]
    n_bad = 0; vmax = -Inf; tmax = ""; best_over = -Inf; tbest = ""
    for t in steps
        load_kw = sum(P[sh][t] for (_, sh) in pmap)
        try
            s = tss_step(t, pmap, P, Q, pv; pu = pu, truth! = truth!)
            @printf("%s %5.2f  | %7.3f  %-7s | %6.3f %+6.3f  %+7.1f %% | %7.2f%s  %7.2f    | %7.2f  %3d  %6.3f\n",
                    tlabel(t), s.pvc, s.c_kw, s.c_b, s.a_kw, s.gap, s.over, s.bp_v,
                    s.bp_note == "delivered" ? " " : "c", s.w.v, s.p.v, s.p.n_over, s.p.curtail_kW)
            push!(rows, ts_row(s, pu, load_kw))
            s.p.n_over > 0 && (n_bad += 1)
            isfinite(s.p.v) && s.p.v > vmax && (vmax = s.p.v; tmax = tlabel(t))
            s.pv > 0 && isfinite(s.over) && s.over > best_over && (best_over = s.over; tbest = tlabel(t))
        catch err
            msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " "), 120)
            println(tlabel(t), "  ERROR: ", msg)
        end
    end
    open(joinpath(pwd(), "results", out), "w") do io
        println(io, TS_HEADER)
        foreach(l -> println(io, l), rows)
    end
    @printf("\nhalf-hours with a home above 253 V (sun-limited, records' basic DOE): %d\n", n_bad)
    @printf("highest home voltage: %.2f V at %s;  largest daylight over-promise: %.1f %% at %s\n",
            vmax, tmax, best_over, tbest)
    @printf("written results/%s (%d rows, %.0f s)\n", out, length(rows), time() - t0)
end
