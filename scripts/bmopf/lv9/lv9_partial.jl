# scripts/bmopf/lv9/lv9_partial.jl
#
# Same two checks as scripts/bmopf/doe_partial_lv3.jl, on LV9:
# (1) PARTIAL EXPORT: clean equal DOE applied on the correct network for the 7 phase patterns
#     (each subset of phases exporting); realised voltages with Volt-VAr, Volt-Watt, 5 kVA kept.
# (2) CABLE CURRENTS at the clean DOE (bound point), by segment kind (drops / shared 16 mm2 /
#     other line codes), to compare with cable ratings (no current limits are modelled).
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/lv9/lv9_partial.jl")
#   julia> run_lv9_partial()                 # 0.94 and 1.00 pu
# OUTPUT results/lv9/lv9_partial.csv, results/lv9/lv9_cable_currents.csv

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_core.jl"))

const PHASE_PATTERNS9 = ["abc", "bc", "ac", "ab", "a", "b", "c"]

function run_lv9_partial(; pus = [0.94, 1.00])
    t0 = time()
    rows = String[]; crows = String[]
    for pu in pus
        net = make_net(pu)
        _, up, _, kinds, ncust, _, _, _ = segment_sets(net)
        kw, b, _, _, r = eq_doe(net)
        cps = connection_points(net)
        phase_of = Dict(cp.id => cp.phase_terminals[1] for cp in cps)
        @printf("\n=== %.3f pu: clean equal DOE %.3f kW (%s) ===\n", pu, kw, b)
        println("  exporting phases | realised max V   customers >253")
        for pat in PHASE_PATTERNS9
            caps = Dict(id => (phase_of[id][1] in pat ? kw : 0.0) for id in keys(phase_of))
            rv = realised(make_net(pu), caps)
            @printf("  %-16s |   %7.2f          %3d\n", pat, rv.v, rv.n_over)
            push!(rows, @sprintf("%.3f,%.6f,%s,%.4f,%d,%.6f", pu, kw, pat, rv.v, rv.n_over, rv.curtail_kW))
        end
        # cable currents by kind
        snap = r.snapshots[1]
        best = Dict{String,Tuple{Float64,Float64,String}}()
        for (lid, lr) in get(snap, "line", Dict())
            lc = String(get(get(net["line"], lid, Dict()), "linecode", "?"))
            kind = lc == SVC_LC ? get(kinds, String(lid), "?") : lc
            mp = 0.0; mn = 0.0
            for (t, c) in lr
                c isa Dict || continue
                i = max(get(c, "cm_fr", 0.0), get(c, "cm_to", 0.0))
                t == "n" ? (mn = max(mn, i)) : (mp = max(mp, i))
            end
            old = get(best, kind, (0.0, 0.0, ""))
            best[kind] = (max(old[1], mp), max(old[2], mn), mp > old[1] ? String(lid) : old[3])
        end
        println("  cable currents at the clean DOE (bound point):")
        for (k, (ip, ineu, where)) in sort(collect(best); by = x -> -x[2][1])
            extra = haskey(ncust, where) ? @sprintf(" (%d customers behind)", ncust[where]) : ""
            @printf("    %-42s max phase %6.1f A at %s%s, max neutral %6.1f A\n", k, ip, where, extra, ineu)
            push!(crows, @sprintf("%.3f,%s,%.3f,%.3f,%s", pu, k, ip, ineu, where))
        end
    end
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
