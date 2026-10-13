# scripts/bmopf/doe_source_sweep.jl
#
# FIX 3 (after independent review): how much does the chosen source voltage drive the result?
# For each source voltage, Case A (records 16 mm2, all 22 service cables really 4 mm2) at:
#   - the 1 kW CSIRO snapshot
#   - three sunny half-hours of the real day (11:00, 12:00, 13:00, Team-Nando loads)
# Reports clean DOE, correct DOE, gap (kW), over-promise (%), and what the issued DOE does on the
# true street with Volt-Watt on: worst case (may export the full DOE) and sun-limited
# (cap = min(DOE, 5 kW x pv_shape)). Uses the functions of doe_timeseries.jl.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_source_sweep.jl")
#   julia> run_source_sweep()
# OUTPUT results/doe_source_sweep.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

const SW_PUS   = [1.00, 1.01, 1.02, 1.025, 1.03, 1.035]
const SW_STEPS = [23, 25, 27]          # 11:00, 12:00, 13:00

function sw_snapshot(pu)
    clean = make_net(pu)
    small = all_small!(make_net(pu))
    c_kw, c_b, c_v, c_st = ts_doe(clean)
    a_kw, a_b, a_v, a_st = ts_doe(small)
    w = re_realised(small, c_kw)
    return (c_kw = c_kw, c_b = c_b, a_kw = a_kw, gap = c_kw - a_kw,
            over = 100 * (c_kw / a_kw - 1), w = w, pvc = NaN, p = (v = NaN, n_over = 0, curtail_kW = NaN, status = "n/a"))
end

function run_source_sweep(; pus = SW_PUS, steps = SW_STEPS)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(RE_PU), P)
    println("setting        pu     | clean kW  bind     | A kW    gap kW  over-prom | worst V(VW) >253 | sun cap  sun V(VW) >253")
    rows = String[]
    for pu in pus
        settings = vcat([("snapshot_1kW", 0)], [("day_" * replace(tlabel(t), ":" => ""), t) for t in steps])
        for (name, t) in settings
            try
                s = t == 0 ? sw_snapshot(pu) : ts_step(t, pmap, P, Q, pv; pu = pu)
                @printf("%-13s %5.3f  | %7.3f  %-8s | %6.3f  %+6.3f  %+7.1f %% | %7.2f    %3d  | %6.3f  %7.2f    %3d\n",
                        name, pu, s.c_kw, s.c_b, s.a_kw, s.gap, s.over, s.w.v, s.w.n_over,
                        s.pvc, s.p.v, s.p.n_over)
                push!(rows, @sprintf("%s,%.3f,%.6f,%s,%.6f,%.6f,%.3f,%.4f,%d,%.6f,%.6f,%.4f,%d,%.6f",
                                     name, pu, s.c_kw, s.c_b, s.a_kw, s.gap, s.over,
                                     s.w.v, s.w.n_over, s.w.curtail_kW, s.pvc, s.p.v, s.p.n_over, s.p.curtail_kW))
            catch err
                msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " "), 120)
                @printf("%-13s %5.3f  ERROR: %s\n", name, pu, msg)
                push!(rows, @sprintf("%s,%.3f,NaN,error,NaN,NaN,NaN,NaN,-1,NaN,NaN,NaN,-1,NaN", name, pu))
            end
        end
    end
    open(joinpath(pwd(), "results", "doe_source_sweep.csv"), "w") do io
        println(io, "setting,source_pu,clean_kW,clean_binding,A_correct_kW,A_gap_kW,A_overpromise_pct,A_worst_V_VW,A_worst_n_over_253,A_worst_curtail_kW,pv_cap_kW,A_pv_V_VW,A_pv_n_over_253,A_pv_curtail_kW")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_source_sweep.csv (%d rows, %.0f s)\n", length(rows), time() - t0)
end
