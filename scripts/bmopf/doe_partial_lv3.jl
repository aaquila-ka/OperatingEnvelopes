# scripts/bmopf/doe_partial_lv3.jl
#
# Checks flagged by the technical audit (LV3):
# (1) PARTIAL EXPORT. The DOE is computed for the "bound point" (every customer exports its full
#     limit at once). Is it still safe when some customers do NOT export? With single-phase
#     customers on a four-wire feeder, switching one phase off shifts the neutral and can lift
#     the other phases. We apply the clean equal DOE on the TRUE (correct) network for the 7
#     phase patterns (each subset of phases exporting) and read the realised voltages
#     (Volt-VAr, Volt-Watt, 5 kVA kept; no voltage limit imposed).
# (2) CABLE CURRENTS. Highest phase and neutral current in each cable type at the clean DOE
#     (bound point), to compare with the cable ratings (no current limits are modelled).
# Settings: 1 kW snapshot and 12:00 loads, 1.03 pu.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_partial_lv3.jl")
#   julia> run_partial_lv3()
# OUTPUT results/doe_partial_lv3.csv, results/cable_currents_lv3.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_fairness.jl"))

const PHASE_PATTERNS = [("abc",), ("bc",), ("ac",), ("ab",), ("a",), ("b",), ("c",)]

function cable_currents(net, snap)
    out = Dict{String,Tuple{Float64,Float64,String}}()     # linecode => (max phase A, max neutral A, where)
    for (lid, lr) in get(snap, "line", Dict())
        lc = String(get(get(net["line"], lid, Dict()), "linecode", "?"))
        mp = 0.0; mn = 0.0
        for (t, c) in lr
            c isa Dict || continue
            i = max(get(c, "cm_fr", 0.0), get(c, "cm_to", 0.0))
            t == "n" ? (mn = max(mn, i)) : (mp = max(mp, i))
        end
        old = get(out, lc, (0.0, 0.0, ""))
        out[lc] = (max(old[1], mp), max(old[2], mn), mp > old[1] ? String(lid) : old[3])
    end
    return out
end

function run_partial_lv3(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    rows = String[]; crows = String[]
    for (sname, prep) in settings
        net = prep(make_net(pu))
        cps = connection_points(net)
        r   = doe(net, cps)
        kw  = r.envelope[cps[1].id][1] / 1000
        phase_of = Dict(cp.id => cp.phase_terminals[1] for cp in cps)
        @printf("\n=== %s, %.3f pu: clean equal DOE %.3f kW ===\n", sname, pu, kw)
        println("  exporting phases | realised max V   customers >253  (who)")
        for (pat,) in PHASE_PATTERNS
            caps = Dict(id => (phase_of[id][1] in pat ? kw : 0.0) for id in keys(phase_of))
            rv = fr_realised(prep(make_net(pu)), caps)
            @printf("  %-16s |   %7.2f          %2d          %s\n", pat, rv.v, rv.n_over, rv.who)
            push!(rows, @sprintf("%s,%.3f,%.6f,%s,%.4f,%d,%.6f,\"%s\"", sname, pu, kw, pat, rv.v, rv.n_over, rv.curtail_kW, rv.who))
        end
        cc = cable_currents(net, r.snapshots[1])
        println("  cable currents at the clean DOE (bound point):")
        for (lc, (ip, ineu, where)) in sort(collect(cc); by = x -> -x[2][1])
            @printf("    %-42s max phase %6.1f A (%s), max neutral %6.1f A\n", lc, ip, where, ineu)
            push!(crows, @sprintf("%s,%.3f,%s,%.3f,%.3f,%s", sname, pu, lc, ip, ineu, where))
        end
    end
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
