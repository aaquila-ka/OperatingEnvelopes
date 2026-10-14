# scripts/bmopf/lv9/lv9_phase_secure.jl
#
# Phase-imbalance-secure equal DOE on LV9 (same method as scripts/bmopf/doe_phase_secure.jl):
# highest equal limit that is safe for all 7 phase export patterns. Voltage limits only
# (no thermal limits), to compare with the bound-point DOE of lv9_core.jl.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/lv9/lv9_phase_secure.jl")
#   julia> run_phase_secure_lv9()          # 0.94 and 1.00 pu (~15-20 min)
# OUTPUT results/lv9/lv9_phase_secure.csv

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))

function run_phase_secure_lv9(; pus = [0.94, 1.00])
    t0 = time()
    rows = String[]
    for pu in pus
        bound, b, _, _, _ = eq_doe(make_net(pu))
        sec, it = ps_doe(make_net(pu), bound)
        @printf("LV9 %.3f pu: bound-point DOE %.3f kW (%s) -> phase-secure DOE %.3f kW (%+.1f %%)  [%.0f s]\n",
                pu, bound, b, sec, 100 * (sec / bound - 1), time() - t0)
        push!(rows, @sprintf("LV9,clean_1kW,%.3f,%.6f,%s,%.6f,%.3f", pu, bound, b, sec, 100 * (sec / bound - 1)))
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_phase_secure.csv"), "w") do io
        println(io, "feeder,setting,source_pu,bound_point_kW,bound_binding,phase_secure_kW,change_pct")
        foreach(l -> println(io, l), rows)
    end
    @printf("written results/lv9/lv9_phase_secure.csv (%.0f s)\n", time() - t0)
end
