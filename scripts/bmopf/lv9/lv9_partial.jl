# =============================================================================
# lv9_partial.jl: LV9 partial export (phase patterns) and cable currents at the clean DOE
#
# What it does (plain English): two checks, same as scripts/bmopf/doe_partial_lv3.jl:
#   (1) PARTIAL EXPORT: the clean equal (bound-point) DOE is applied on the correct network
#       for the 7 phase patterns (each subset of phases exporting, the others silent);
#       realised voltages with Volt-VAr, Volt-Watt and 5 kVA kept.
#   (2) CABLE CURRENTS at the clean DOE (bound point), highest per segment kind (drops /
#       shared 16 mm2 / stubs) or per other line code, to compare with cable ratings
#       (no current limits are modelled here; see lv9_thermal.jl).
# Inputs:   data/networks/LV9_258bus_withPV/; includes lv9_core.jl (and so lv9_common.jl).
# Outputs:  results/lv9/lv9_partial.csv, results/lv9/lv9_cable_currents.csv; tables printed.
#           Note: curtail_kW in lv9_partial.csv is about 0.001 kW too low per silent customer
#           (silent customers get a 1 W cap in realised(), see lv9_common.jl), which is why
#           some rows show -0.041 / -0.082.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_partial.jl")   then   run_lv9_partial()   # 0.94 and 1.00 pu
# Used for: REPRODUCE.md step 22 (DATA_CARD rows lv9_partial.csv, lv9_cable_currents.csv).
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_core.jl"))

# The 7 phase patterns: which phases export (homes on the other phases are silent)
const PHASE_PATTERNS9 = ["abc", "bc", "ac", "ab", "a", "b", "c"]

# For each source voltage: test the clean DOE under each phase pattern, then list the highest cable currents
function run_lv9_partial(; pus = [0.94, 1.00])
    t0 = time()
    rows = String[]; crows = String[]
    for pu in pus
        net = make_net(pu)
        # Segment kinds (drop / upstream / stub) and homes behind each segment, from lv9_core.jl
        _, up, _, kinds, ncust, _, _, _ = segment_sets(net)
        # Clean equal DOE (DOE = export limit every home gets), basic bound-point version (checked only with
        # everyone exporting); r keeps the solved result for the cable currents
        kw, b, _, _, r = eq_doe(net)
        cps = connection_points(net)
        # Which phase each home is on
        phase_of = Dict(cp.id => cp.phase_terminals[1] for cp in cps)
        @printf("\n=== %.3f pu: clean equal DOE %.3f kW (%s) ===\n", pu, kw, b)
        println("  exporting phases | realised max V   customers >253")
        for pat in PHASE_PATTERNS9
            # Homes on an exporting phase may export up to the DOE; homes on silent phases get 0
            caps = Dict(id => (phase_of[id][1] in pat ? kw : 0.0) for id in keys(phase_of))
            # Realised reading: homes export up to the cap with inverter rules on and no voltage limit
            # imposed, then we read the highest home voltage
            rv = realised(make_net(pu), caps)
            @printf("  %-16s |   %7.2f          %3d\n", pat, rv.v, rv.n_over)
            push!(rows, @sprintf("%.3f,%.6f,%s,%.4f,%d,%.6f", pu, kw, pat, rv.v, rv.n_over, rv.curtail_kW))
        end
        # cable currents by kind
        snap = r.snapshots[1]
        # For each kind (or other line code) keep: highest phase current, highest neutral current,
        # and the segment with the highest phase current
        best = Dict{String,Tuple{Float64,Float64,String}}()
        for (lid, lr) in get(snap, "line", Dict())
            lc = String(get(get(net["line"], lid, Dict()), "linecode", "?"))
            kind = lc == SVC_LC ? get(kinds, String(lid), "?") : lc
            mp = 0.0; mn = 0.0
            # Largest current at either end of the segment; neutral kept apart from the phases
            for (t, c) in lr
                c isa Dict || continue
                i = max(get(c, "cm_fr", 0.0), get(c, "cm_to", 0.0))
                t == "n" ? (mn = max(mn, i)) : (mp = max(mp, i))
            end
            old = get(best, kind, (0.0, 0.0, ""))
            best[kind] = (max(old[1], mp), max(old[2], mn), mp > old[1] ? String(lid) : old[3])
        end
        println("  cable currents at the clean DOE (bound point):")
        # Print, largest phase current first; add how many homes are behind that segment
        for (k, (ip, ineu, where)) in sort(collect(best); by = x -> -x[2][1])
            extra = haskey(ncust, where) ? @sprintf(" (%d customers behind)", ncust[where]) : ""
            @printf("    %-42s max phase %6.1f A at %s%s, max neutral %6.1f A\n", k, ip, where, extra, ineu)
            push!(crows, @sprintf("%.3f,%s,%.3f,%.3f,%s", pu, k, ip, ineu, where))
        end
    end
    # Write the phase-pattern results and the cable currents to two CSV files
    open(joinpath(pwd(), "results", "lv9", "lv9_partial.csv"), "w") do io
        println(io, "source_pu,clean_kW,exporting_phases,realised_V_VW,n_customers_over_253,curtail_kW")
        foreach(l -> println(io, l), rows)
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_cable_currents.csv"), "w") do io
        println(io, "source_pu,segment_kind_or_linecode,max_phase_current_A,max_neutral_current_A,max_phase_segment")
        foreach(l -> println(io, l), crows)
    end
    @printf("\nwritten results/lv9/lv9_partial.csv and lv9_cable_currents.csv (%.0f s)\n", time() - t0)
end
