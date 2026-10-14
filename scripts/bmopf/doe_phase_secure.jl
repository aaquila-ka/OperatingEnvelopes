# scripts/bmopf/doe_phase_secure.jl
#
# Phase-imbalance-secure equal DOE on LV3: the highest equal export limit that keeps every
# customer within 207-253 V (inverter Volt-VAr/Volt-Watt and 5 kVA kept) not only when everyone
# exports (bound point) but also when the customers of one or two phases export nothing
# (7 phase patterns, PowerOptLab verify_operating_envelope with explicit utilisation vectors).
# Found by bisection (10 steps, precision ~0.1 % of the bound-point DOE).
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_phase_secure.jl")
#   julia> run_phase_secure_lv3()
# OUTPUT results/doe_phase_secure_lv3.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))

function run_phase_secure_lv3(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for (sname, prep) in (("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25)))
        bound, b, _, _ = ts_doe(prep(make_net(pu)))
        sec, it = ps_doe(prep(make_net(pu)), bound)
        @printf("%-13s %.3f pu: bound-point DOE %.3f kW (%s) -> phase-secure DOE %.3f kW (%+.1f %%)\n",
                sname, pu, bound, b, sec, 100 * (sec / bound - 1))
        push!(rows, @sprintf("LV3,%s,%.3f,%.6f,%s,%.6f,%.3f", sname, pu, bound, b, sec, 100 * (sec / bound - 1)))
    end
    open(joinpath(pwd(), "results", "doe_phase_secure_lv3.csv"), "w") do io
        println(io, "feeder,setting,source_pu,bound_point_kW,bound_binding,phase_secure_kW,change_pct")
        foreach(l -> println(io, l), rows)
    end
    @printf("written results/doe_phase_secure_lv3.csv (%.0f s)\n", time() - t0)
end
