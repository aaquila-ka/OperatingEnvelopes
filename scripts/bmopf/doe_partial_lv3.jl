# =============================================================================
# doe_partial_lv3.jl: LV3 safety checks: partial export by phase, and cable currents
#
# What it does (plain English):
#   (1) PARTIAL EXPORT. The DOE is computed for the "bound point" (every customer exports its
#       full limit at once). Is it still safe when some customers do NOT export? With
#       single-phase customers on a four-wire feeder, switching one phase off shifts the
#       neutral and can lift the other phases. The clean equal DOE is applied on the TRUE
#       (correct) network for the 7 phase patterns (each subset of phases exporting; customers
#       on the other phases get limit 0) and the realised voltages are read (Volt-VAr,
#       Volt-Watt, 5 kVA kept; no voltage limit imposed; fr_realised from doe_fairness.jl).
#   (2) CABLE CURRENTS. Highest phase and neutral current in each cable type (line code) at the
#       clean DOE (bound point), to compare with cable ratings (no current limits are modelled).
#   Settings: 1 kW snapshot and 12:00 loads, 1.03 pu.
#
# Inputs:   LV3 network and house profiles. Includes doe_fairness.jl (-> doe_timeseries.jl ...).
# Outputs:  results/doe_partial_lv3.csv (14 rows), results/cable_currents_lv3.csv (6 rows).
#           curtail_kW there is about 0.001 kW low per silent customer (see doe_fairness.jl).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_partial_lv3.jl")   then   run_partial_lv3()
# Used for: REPRODUCE.md step 17 (section 4 row "LV3 partial export"); DATA_CARD.md files 16-17.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_fairness.jl"))

# The 7 phase patterns: which phases have homes exporting (homes on the other phases export nothing)
const PHASE_PATTERNS = [("abc",), ("bc",), ("ac",), ("ab",), ("a",), ("b",), ("c",)]

# For each cable type (line code), finds the highest phase current and the highest neutral current (A)
# in the solved snapshot, and which segment had the highest phase current
function cable_currents(net, snap)
    out = Dict{String,Tuple{Float64,Float64,String}}()     # linecode => (max phase A, max neutral A, where)
    # Go through every line (cable segment) in the solved results
    for (lid, lr) in get(snap, "line", Dict())
        lc = String(get(get(net["line"], lid, Dict()), "linecode", "?"))
        mp = 0.0; mn = 0.0
        # Each conductor (a, b, c or n) of this segment
        for (t, c) in lr
            c isa Dict || continue
            # Current magnitude at the "from" end or the "to" end, whichever is bigger
            i = max(get(c, "cm_fr", 0.0), get(c, "cm_to", 0.0))
            # Neutral current goes to mn, phase currents to mp
            t == "n" ? (mn = max(mn, i)) : (mp = max(mp, i))
        end
        # Keep the running maximum for this cable type, and the segment name if this one is the new phase maximum
        old = get(out, lc, (0.0, 0.0, ""))
        out[lc] = (max(old[1], mp), max(old[2], mn), mp > old[1] ? String(lid) : old[3])
    end
    return out
end

# Main run: for the snapshot and 12:00, apply the clean equal DOE (DOE = the export limit every home gets)
# to the 7 phase patterns, then report cable currents; writes the two CSVs
function run_partial_lv3(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # Two settings: the snapshot keeps the CSIRO loads; "day_1200" puts on the half-hour 25 (12:00) loads
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    rows = String[]; crows = String[]
    for (sname, prep) in settings
        # Solve the clean bound-point DOE (bound-point = checked only with everyone exporting)
        net = prep(make_net(pu))
        cps = connection_points(net)
        r   = doe(net, cps)
        kw  = r.envelope[cps[1].id][1] / 1000
        # Which phase each home is on (its inverter's phase terminal, e.g. "a")
        phase_of = Dict(cp.id => cp.phase_terminals[1] for cp in cps)
        @printf("\n=== %s, %.3f pu: clean equal DOE %.3f kW ===\n", sname, pu, kw)
        println("  exporting phases | realised max V   customers >253  (who)")
        for (pat,) in PHASE_PATTERNS
            # This pattern's caps: homes on an exporting phase get the DOE, the others get 0
            caps = Dict(id => (phase_of[id][1] in pat ? kw : 0.0) for id in keys(phase_of))
            # Realised reading (fr_realised from doe_fairness.jl): homes export up to their cap with the inverter rules
            # (Volt-VAr / Volt-Watt from AS/NZS 4777.2) on and no voltage limit, then we read the voltages
            rv = fr_realised(prep(make_net(pu)), caps)
            @printf("  %-16s |   %7.2f          %2d          %s\n", pat, rv.v, rv.n_over, rv.who)
            # CSV row: the pattern, highest customer voltage, customers above 253 V and who they are
            push!(rows, @sprintf("%s,%.3f,%.6f,%s,%.4f,%d,%.6f,\"%s\"", sname, pu, kw, pat, rv.v, rv.n_over, rv.curtail_kW, rv.who))
        end
        # Cable currents in the DOE solution itself (everyone exporting the full DOE)
        cc = cable_currents(net, r.snapshots[1])
        println("  cable currents at the clean DOE (bound point):")
        # Print/save cable types with the highest phase current first
        for (lc, (ip, ineu, where)) in sort(collect(cc); by = x -> -x[2][1])
            @printf("    %-42s max phase %6.1f A (%s), max neutral %6.1f A\n", lc, ip, where, ineu)
            push!(crows, @sprintf("%s,%.3f,%s,%.3f,%.3f,%s", sname, pu, lc, ip, ineu, where))
        end
    end
    # Write the partial-export file, then the cable-current file
    open(joinpath(pwd(), "results", "doe_partial_lv3.csv"), "w") do io
        println(io, "setting,source_pu,clean_kW,exporting_phases,realised_V_VW,n_customers_over_253,curtail_kW,customers_over_253")
        foreach(l -> println(io, l), rows)
    end
    open(joinpath(pwd(), "results", "cable_currents_lv3.csv"), "w") do io
        println(io, "setting,source_pu,linecode,max_phase_current_A,max_neutral_current_A,max_phase_segment")
        foreach(l -> println(io, l), crows)
    end
    @printf("\nwritten results/doe_partial_lv3.csv and results/cable_currents_lv3.csv (%.0f s)\n", time() - t0)
end
