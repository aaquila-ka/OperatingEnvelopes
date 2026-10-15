# =============================================================================
# doe_source_sweep.jl: Case A at source voltages 1.00 to 1.035 pu
#
# What it does (plain English):
#   Checks how much the chosen source voltage drives the result (added after the
#   code review; AI-assisted review, checked by me). For each source voltage, Case A (records 16 mm2, all 22
#   service cables really 4 mm2) at:
#     - the 1 kW CSIRO snapshot
#     - three sunny half-hours of the real day (11:00, 12:00, 13:00, Team-Nando loads)
#   Reports the clean DOE (= the DOE issued from the records), correct DOE, gap (kW,
#   issued minus correct), over-promise (% of the correct DOE), and what the issued DOE
#   does on the true street with Volt-Watt on: worst case (may export the full DOE) and
#   sun-limited (cap = min(DOE, 5 kW x pv_shape)). Uses the functions of doe_timeseries.jl.
#   Snapshot rows have no sun limit: pv_cap_kW and A_pv_V_VW are NaN there and
#   A_pv_n_over_253 is written as 0, which means "not applicable".
# Inputs:   includes doe_timeseries.jl (-> doe_record_errors.jl -> doe_common.jl ->
#           load_lv3.jl); data/profiles/TeamNando_OE1_LoadShapes.txt
# Outputs:  results/doe_source_sweep.csv (24 rows); prints a table
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_source_sweep.jl")   then   run_source_sweep()
# Used for: REPRODUCE.md step 11 (12:00 gap 0.14 / 0.17 / 0.71 / 1.63 / 2.29 / 0.60 kW)
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); Team-Nando OE1-Ideal load profiles
#           (BSD-3); BMOPFTools.jl and PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

# Source voltages to try (pu = grid voltage relative to normal, so 1.03 = 3% high) and the three half-hours
const SW_PUS   = [1.00, 1.01, 1.02, 1.025, 1.03, 1.035]
const SW_STEPS = [23, 25, 27]          # 11:00, 12:00, 13:00

# The 1 kW snapshot at one source voltage: clean DOE (= issued from the records) vs Case A correct DOE
# (DOE = the export limit every home gets), plus the realised reading of the issued DOE on the Case A street
function sw_snapshot(pu)
    # Clean street = the records; small = Case A true street with all 22 service cables 4 mm2
    clean = make_net(pu)
    small = all_small!(make_net(pu))
    c_kw, c_b, c_v, c_st = ts_doe(clean)
    a_kw, a_b, a_v, a_st = ts_doe(small)
    # Realised reading: homes export up to the issued cap with Volt-VAr/Volt-Watt (AS/NZS 4777.2 inverter rules) on
    w = re_realised(small, c_kw)
    # Same fields as a ts_step result, so one print/CSV line fits both; there is no sun limit here, so the sun fields are NaN / 0
    return (c_kw = c_kw, c_b = c_b, a_kw = a_kw, gap = c_kw - a_kw,
            over = 100 * (c_kw / a_kw - 1), w = w, pvc = NaN, p = (v = NaN, n_over = 0, curtail_kW = NaN, status = "n/a"))
end

# Main run: for each source voltage, the snapshot plus the three half-hours; prints a table and writes the CSV
function run_source_sweep(; pus = SW_PUS, steps = SW_STEPS)
    t0 = time()
    # Read the house and sun shapes once and pick the same 12 house shapes as the day run
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(RE_PU), P)
    println("setting        pu     | clean kW  bind     | A kW    gap kW  over-prom | worst V(VW) >253 | sun cap  sun V(VW) >253")
    rows = String[]
    for pu in pus
        # Settings list: ("snapshot_1kW", 0) first, then ("day_1100", 23) and so on; t = 0 means "snapshot"
        settings = vcat([("snapshot_1kW", 0)], [("day_" * replace(tlabel(t), ":" => ""), t) for t in steps])
        for (name, t) in settings
            try
                # Snapshot uses sw_snapshot; a half-hour uses ts_step from doe_timeseries.jl at this source voltage
                s = t == 0 ? sw_snapshot(pu) : ts_step(t, pmap, P, Q, pv; pu = pu)
                @printf("%-13s %5.3f  | %7.3f  %-8s | %6.3f  %+6.3f  %+7.1f %% | %7.2f    %3d  | %6.3f  %7.2f    %3d\n",
                        name, pu, s.c_kw, s.c_b, s.a_kw, s.gap, s.over, s.w.v, s.w.n_over,
                        s.pvc, s.p.v, s.p.n_over)
                # One CSV row: clean and correct DOE, gap, over-promise %, then the realised readings (worst case, then sun-limited)
                push!(rows, @sprintf("%s,%.3f,%.6f,%s,%.6f,%.6f,%.3f,%.4f,%d,%.6f,%.6f,%.4f,%d,%.6f",
                                     name, pu, s.c_kw, s.c_b, s.a_kw, s.gap, s.over,
                                     s.w.v, s.w.n_over, s.w.curtail_kW, s.pvc, s.p.v, s.p.n_over, s.p.curtail_kW))
            catch err
                # If a setting fails, print a short message and write a row of NaN (n_over -1 marks the failure)
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
