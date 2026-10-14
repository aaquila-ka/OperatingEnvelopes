# =============================================================================
# lv9_dropout.jl: LV9 dropout check and dropout-secure DOE (130 cases)
#
# What it does (plain English): same idea as scripts/bmopf/doe_dropout_lv3.jl. On LV3,
#   checking (nobody dropped + 7 phase patterns + every 1 or 2 dropped customers) found the
#   same worst case as checking all 4094 on/off combinations. LV9 has 123 customers, so all
#   combinations (2^123) are impossible and pairs alone are 7503 cases. Here the cases are
#     nobody dropped + 6 phase patterns + each single customer dropped = 1 + 6 + 123 = 130
#   ("dropped" = that customer's export cap is 0; everyone else may export up to the DOE;
#   realised reading, voltage limits only, no thermal limits; fail = above 253.005 V or a
#   failed solve).
#   Step 1 (run_lv9_dropout_check): the PHASE-SECURE DOE from lv9_phase_secure.jl, checked
#     on the correct network for all 130 cases.
#   Step 2 (run_lv9_dropout_secure, further down in this file): a diagnostic comparing
#     verify_operating_envelope with the realised reading per phase pattern, then the
#     DROPOUT-SECURE DOE by bisection, and a final check over all 130 cases.
# Inputs:   results/lv9/lv9_phase_secure.csv (from run_phase_secure_lv9, step 24);
#           data/networks/LV9_258bus_withPV/; includes lv9_common.jl and
#           scripts/bmopf/phase_secure_core.jl (PS_PATTERNS, ps_patterns, ps_doe).
# Outputs:  results/lv9/lv9_dropout_check.csv (step 1); results/lv9/lv9_dropout_secure.csv
#           and lv9_dropout_diagnostic.csv (step 2); progress and failures printed.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_dropout.jl")   then
#   run_lv9_dropout_check()          # 0.94 and 1.00 pu; prints time per case after 10
#   run_lv9_dropout_secure()         # 0.94 and 1.00 pu
# Used for: REPRODUCE.md step 29 (section 4 row "LV9 dropout check / dropout-secure":
#           2.423 kW at 0.94 pu, 1.097 kW at 1.00 pu); its csv is read by step 30.
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))   # PS_PATTERNS

# phase-secure DOE (kW) for each source pu, from the earlier run
function lv9_phase_secure_kw()
    file = joinpath(pwd(), "results", "lv9", "lv9_phase_secure.csv")
    isfile(file) || error("missing $file: run run_phase_secure_lv9() first")
    lines = collect(eachline(file))
    # Find the source_pu and phase_secure_kW columns, then map each pu (3 decimals) to its DOE
    hdr = split(lines[1], ",")
    ipu = findfirst(==("source_pu"), hdr); ikw = findfirst(==("phase_secure_kW"), hdr)
    return Dict(round(parse(Float64, split(l, ",")[ipu]); digits = 3) => parse(Float64, split(l, ",")[ikw])
                for l in lines[2:end])
end

# (name, dropped set) for: nobody, 6 phase patterns, every single customer
function lv9_dropout_sets(net)
    cps = connection_points(net)
    ids = sort([cp.id for cp in cps])
    # Which phase each home is on (a, b or c)
    ph  = Dict(cp.id => cp.phase_terminals[1][1] for cp in cps)
    sets = Tuple{String,Set{String}}[("none", Set{String}())]
    # Phase patterns (skip 'abc' = everyone): homes NOT on an exporting phase are dropped
    for pat in PS_PATTERNS[2:end]
        push!(sets, ("only_$(pat)_export", Set(id for id in ids if !(ph[id] in pat))))
    end
    # One case per home: only that home dropped
    for id in ids
        push!(sets, ("drop_$(id)", Set([id])))
    end
    return ids, sets
end

# Step 1: check the phase-secure DOE (DOE = export limit every home gets) on the correct street
# for all 130 cases. A case fails if the highest home voltage is above 253.005 V or the solve fails
function run_lv9_dropout_check(; pus = [0.94, 1.00])
    t0 = time()
    sec = lv9_phase_secure_kw()
    rows = String[]
    for pu in pus
        # The phase-secure DOE saved earlier for this source voltage
        kw  = sec[round(pu; digits = 3)]
        net = make_net(pu)                         # realised() works on a copy, so one net is enough
        ids, sets = lv9_dropout_sets(net)
        @printf("\n=== LV9 %.3f pu, phase-secure DOE %.3f kW: %d cases ===\n", pu, kw, length(sets))
        worst_v = -Inf; worst = ""; nfail = 0; tb = time()
        for (k, (name, dropped)) in enumerate(sets)
            # Dropped homes get cap 0, everyone else may export up to the DOE
            caps = Dict(id => (id in dropped ? 0.0 : kw) for id in ids)
            # Realised reading: homes export up to the cap with inverter rules (Volt-VAr / Volt-Watt) on
            # and no voltage limit imposed, then we read the highest home voltage
            rv = realised(net, caps)
            # Fail if above 253 V + 0.005 V. A failed solve gives NaN, and !(NaN <= x) is true, so it fails too
            fail = !(rv.v <= V_MAX_PN + 0.005)
            nfail += fail
            rv.v > worst_v && (worst_v = rv.v; worst = name)
            fail && @printf("  FAIL  %-28s %.2f V, %d customers over 253 V\n", name, rv.v, rv.n_over)
            push!(rows, @sprintf("%.3f,%.6f,%s,%d,%.4f,%d,%s,\"%s\"", pu, kw, name, length(dropped),
                                 rv.v, rv.n_over, fail ? "FAIL" : "ok", rv.who))
            # Progress: the nobody-dropped result, and after 10 cases an estimate of the time needed
            k == 1  && @printf("  nobody dropped: %.2f V, %d over 253 V\n", rv.v, rv.n_over)
            k == 10 && @printf("  ... %.1f s per case, about %.0f min for this pu\n",
                               (time() - tb) / 10, (time() - tb) / 10 * length(sets) / 60)
        end
        @printf("  worst: %.2f V (%s);  cases over 253 V: %d of %d  (%.0f min)\n",
                worst_v, worst, nfail, length(sets), (time() - tb) / 60)
    end
    # Write lv9_dropout_check.csv
    open(joinpath(pwd(), "results", "lv9", "lv9_dropout_check.csv"), "w") do io
        println(io, "source_pu,phase_secure_kW,case,n_dropped,realised_V_VW,n_customers_over_253,result,customers_over_253")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_dropout_check.csv (%.0f min)\n", (time() - t0) / 60)
end

# =============================================================================================
# STEP 2: DROPOUT-SECURE DOE on LV9 (realised reading), plus a diagnostic.
# The check above showed: no single-customer dropout fails, but the phase pattern
# "only b and c export" fails in the realised reading (253.1-253.2 V) although the phase-secure
# search (verify_operating_envelope) had accepted it. Here we
#  (1) DIAGNOSE: for each phase pattern at the phase-secure DOE, what verify_operating_envelope
#      says (feasible yes/no) next to the realised voltage, so the two checks can be compared;
#  (2) find the highest equal DOE that passes the realised reading for nobody + 6 phase patterns
#      (bisection; single dropouts all passed at the higher DOE, so they are re-checked only at
#      the end);
#  (3) FINAL CHECK of that DOE over all 130 cases.
#
#   julia> run_lv9_dropout_secure()       # 0.94 and 1.00 pu (~20-30 min)
# OUTPUT results/lv9/lv9_dropout_secure.csv, results/lv9/lv9_dropout_diagnostic.csv
# =============================================================================================

# Realised reading of every case at the equal limit kw. Returns ok (no case over 253.005 V),
# the worst voltage and case, and the number of fails. With early_stop it stops at the first fail
function lv9_check(net, ids, sets, kw; early_stop = true)
    worst_v = -Inf; worst = ""; nfail = 0
    for (name, dropped) in sets
        rv = realised(net, Dict(id => (id in dropped ? 0.0 : kw) for id in ids))
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail
        rv.v > worst_v && (worst_v = rv.v; worst = name)
        fail && early_stop && return (ok = false, v = rv.v, worst = name, nfail = nfail)
    end
    return (ok = nfail == 0, v = worst_v, worst = worst, nfail = nfail)
end

function run_lv9_dropout_secure(; pus = [0.94, 1.00], iters = 8)
    t0 = time()
    sec = lv9_phase_secure_kw()
    rows = String[]; drows = String[]
    for pu in pus
        # Upper end of the search: the phase-secure DOE
        hi  = sec[round(pu; digits = 3)]
        net = make_net(pu)
        cps = connection_points(net)
        ids, sets = lv9_dropout_sets(net)
        psets = sets[1:7]                                   # nobody + 6 phase patterns
        @printf("\n=== LV9 %.3f pu, phase-secure DOE %.3f kW ===\n", pu, hi)
        # (1) diagnostic: verify_operating_envelope vs realised reading, pattern by pattern
        println("  pattern            verify says   realised V   >253")
        # Same limit for every home, in W, as verify_operating_envelope expects
        caps = Dict(cp.id => 1000.0 * hi for cp in cps)
        pats = ps_patterns(cps)                             # same order as PS_PATTERNS
        for (j, pat) in enumerate(PS_PATTERNS)
            # What the phase-secure check says for this one pattern (feasible or not)
            ev = verify_operating_envelope(net, cps, caps; utilizations = [pats[j]], solver_options = OPTS)
            # The same pattern in the realised reading (pattern 1 = nobody dropped)
            dropped = j == 1 ? Set{String}() : psets[j][2]
            rv = realised(net, Dict(id => (id in dropped ? 0.0 : hi) for id in ids))
            @printf("  %-17s  %-12s  %8.2f    %3d   %s\n", pat, ev.feasible[1] ? "feasible" : "INFEASIBLE",
                    rv.v, rv.n_over, rv.who)
            push!(drows, @sprintf("%.3f,%.6f,%s,%s,%s,%.4f,%d,\"%s\"", pu, hi, pat, ev.feasible[1],
                                  string(ev.termination_status[1]), rv.v, rv.n_over, rv.who))
        end
        # (2) bisection on the realised reading (phase patterns only), between 0.9 x (or 0) and the
        #     phase-secure DOE, so the result is never above the phase-secure DOE. Note: the
        #     `iters += 4` fallback below also carries over to the next source voltage.
        # Lower end: 90 % of the phase-secure DOE; if even that fails, start at 0 and do 4 more steps
        lo = 0.9 * hi
        if !lv9_check(net, ids, psets, lo).ok
            lo = 0.0; iters += 4
        end
        # If the phase-secure DOE already passes, keep it; otherwise halve the range iters times,
        # keeping the safe end (lo) each time
        if lv9_check(net, ids, psets, hi).ok
            lo = hi
        else
            for it in 1:iters
                mid = (lo + hi) / 2
                r = lv9_check(net, ids, psets, mid)
                @printf("    bisection %2d: %.4f kW -> %s\n", it, mid,
                        r.ok ? "safe" : @sprintf("fails (%.2f V, %s)", r.v, r.worst))
                r.ok ? (lo = mid) : (hi = mid)
            end
        end
        # The dropout-secure (safer) DOE: the highest safe value found. On LV9 it is checked for nobody
        # dropped, whole phases silent, and any one home silent
        ds = lo
        # (3) final check over all 130 cases
        tb = time()
        chk = lv9_check(net, ids, sets, ds; early_stop = false)
        # Compare with the phase-secure DOE: 100 x (dropout-secure / phase-secure - 1)
        s0 = sec[round(pu; digits = 3)]
        @printf("  dropout-secure DOE %.3f kW (%+.1f %% vs phase-secure %.3f kW)\n", ds, 100 * (ds / s0 - 1), s0)
        @printf("  final check over %d cases: worst %.2f V (%s), over 253 V: %d  (%.0f min)\n",
                length(sets), chk.v, chk.worst, chk.nfail, (time() - tb) / 60)
        push!(rows, @sprintf("LV9,clean_1kW,%.3f,%.6f,%.6f,%.3f,%d,%.4f,%s,%d", pu, s0, ds,
                             100 * (ds / s0 - 1), length(sets), chk.v, chk.worst, chk.nfail))
    end
    # Write the DOE results and the diagnostic table
    open(joinpath(pwd(), "results", "lv9", "lv9_dropout_secure.csv"), "w") do io
        println(io, "feeder,setting,source_pu,phase_secure_kW,dropout_secure_kW,change_vs_phase_secure_pct,n_cases_checked,worst_V_VW,worst_case,n_fail")
        foreach(l -> println(io, l), rows)
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_dropout_diagnostic.csv"), "w") do io
        println(io, "source_pu,phase_secure_kW,pattern,verify_feasible,verify_status,realised_V_VW,n_customers_over_253,customers_over_253")
        foreach(l -> println(io, l), drows)
    end
    @printf("\nwritten results/lv9/lv9_dropout_secure.csv and lv9_dropout_diagnostic.csv (%.0f min)\n", (time() - t0) / 60)
end
