# =============================================================================
# lv9_phase_secure.jl: phase-secure equal DOE on LV9
#
# What it does (plain English): finds the highest equal export limit that stays within the
#   voltage limits for all 7 phase export patterns (everyone, or only some whole phases
#   exporting), by bisection between 0 and the bound-point DOE, using PowerOptLab's
#   verify_operating_envelope (same method as scripts/bmopf/doe_phase_secure.jl). Voltage
#   limits only (no thermal limits), to compare with the bound-point DOE of lv9_core.jl.
# Inputs:   data/networks/LV9_258bus_withPV/; includes lv9_common.jl and
#           scripts/bmopf/phase_secure_core.jl (ps_doe).
# Outputs:  results/lv9/lv9_phase_secure.csv; one line printed per source voltage.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_phase_secure.jl")   then
#   run_phase_secure_lv9()          # 0.94 and 1.00 pu (REPRODUCE.md says ~6 min)
# Used for: REPRODUCE.md step 24 (section 4 row "LV9 thermal / phase-secure": 2.445 kW at
#           0.94 pu); its csv is read by lv9_dropout.jl (step 29).
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))

# For each source voltage (pu = grid voltage relative to normal): the basic DOE (export limit every
# home gets), then the phase-secure DOE (also safe when one or two whole phases export nothing)
function run_phase_secure_lv9(; pus = [0.94, 1.00])
    t0 = time()
    rows = String[]
    for pu in pus
        # Bound-point (basic) DOE = checked only with everyone exporting
        bound, b, _, _, _ = eq_doe(make_net(pu))
        # Bisection between 0 and the bound-point DOE, checking all 7 phase patterns (ps_doe, phase_secure_core.jl)
        sec, it = ps_doe(make_net(pu), bound)
        # Print both and the % change = 100 x (phase-secure / bound-point - 1)
        @printf("LV9 %.3f pu: bound-point DOE %.3f kW (%s) -> phase-secure DOE %.3f kW (%+.1f %%)  [%.0f s]\n",
                pu, bound, b, sec, 100 * (sec / bound - 1), time() - t0)
        push!(rows, @sprintf("LV9,clean_1kW,%.3f,%.6f,%s,%.6f,%.3f", pu, bound, b, sec, 100 * (sec / bound - 1)))
    end
    # Write lv9_phase_secure.csv (lv9_dropout.jl reads it)
    open(joinpath(pwd(), "results", "lv9", "lv9_phase_secure.csv"), "w") do io
        println(io, "feeder,setting,source_pu,bound_point_kW,bound_binding,phase_secure_kW,change_pct")
        foreach(l -> println(io, l), rows)
    end
    @printf("written results/lv9/lv9_phase_secure.csv (%.0f s)\n", time() - t0)
end
