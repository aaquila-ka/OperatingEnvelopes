# =============================================================================
# doe_dropout_lv3.jl: LV3 dropout check and the dropout-secure DOE
#
# What it does (plain English):
#   A DOE is normally checked only at the "bound point" (everyone exports their full limit).
#   On an unbalanced four-wire feeder, some customers exporting NOTHING can shift the neutral
#   and push other customers higher. Here an equal DOE is applied on the correct network with
#   some customers dropped to zero export, and the realised voltages are read (Volt-VAr,
#   Volt-Watt, 5 kVA kept; no voltage limit imposed; same reading as fr_realised). A case
#   fails if the realised voltage is above 253.005 V or the solve gives NaN.
#   Idea: B. Liu and J. H. Braslavsky, IEEE Access 2022 (see ACKNOWLEDGEMENTS.md);
#   PowerOptLab doe_dropout_utilizations.
#   Settings: 1 kW snapshot, and 12:00 of the profile day (day index 350), at 1.03 pu.
#
#   run_dropout_lv3()        bound-point and phase-secure DOEs vs nobody dropped + every set of
#                            1 or 2 dropped customers (1 + 12 + 66 = 79 cases)
#                            x 2 DOEs x 2 settings = 316 realised solves (about 2 min)
#   run_dropout_secure_lv3() DROPOUT-SECURE DOE: highest equal limit that passes nobody dropped,
#                            the 6 other phase patterns and every 1- or 2-customer dropout
#                            (85 cases; bisection between 0.9 x and 1 x the phase-secure DOE,
#                            about 5 min)
#   run_dropout_lv3_full()   EVERY on/off combination (2^12 - 2 = 4094 cases: all-on and all-off
#                            left out) for ONE DOE and ONE setting (default: dropout-secure DOE,
#                            12:00); about 15-30 min. Writes as it goes; if stopped, run it again
#                            and it continues. Resuming skips every mask already in the file
#                            (FAIL rows included) and does not check that the file was made with
#                            the same pu or DOE value, so delete the file before changing them.
#                            Other choices: doe = "phase_secure" or "bound_point",
#                            setting = "snapshot_1kW".
#
# Inputs:   LV3 network and house profiles. Includes doe_fairness.jl (fr_realised,
#           read_profiles, ...) and phase_secure_core.jl (ps_doe, PS_PATTERNS).
# Outputs:  results/doe_dropout_lv3.csv (316 rows), results/doe_dropout_secure_lv3.csv (2 rows),
#           results/doe_dropout_lv3_full_<setting>_<doe>.csv (4094 rows; column mask: bit i-1
#           set = customer ids[i] dropped, ids in sorted order).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_dropout_lv3.jl")
#   then   run_dropout_lv3()   run_dropout_secure_lv3()   run_dropout_lv3_full()
# Used for: REPRODUCE.md steps 25, 26, 27 (section 4 rows "LV3 dropout check" and "LV3
#           dropout-secure DOE"; section 6 items 19, 21, 22); DATA_CARD.md files 19-21.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

# Reuse helpers from earlier steps: doe_fairness.jl brings in make_net, the house profiles and
# fr_realised (the realised reading); phase_secure_core.jl brings ps_doe and the 7 phase patterns
include(joinpath(pwd(), "scripts", "bmopf", "doe_fairness.jl"))          # fr_realised, read_profiles, ...
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))     # ps_doe

# Words used below: DOE = export limit every home gets; pu = grid voltage relative to normal (1.03 =
# 3% high); "dropped" = a home exporting nothing.
# Realised reading = homes export up to the cap with the inverter rules on (Volt-VAr and Volt-Watt
# from AS/NZS 4777.2) and no voltage limit imposed, then we read the voltage.
# Bound-point (basic) DOE = checked only with everyone exporting; phase-secure DOE = also safe when
# one or two whole phases export nothing; dropout-secure (safer) DOE = also safe when 1-2 homes or a
# whole phase stop exporting.
# The two settings: the 1 kW-per-home snapshot, and 12:00 on the profile day (time step 25 of the 48
# half-hours)
const DO_SETTINGS = ["snapshot_1kW", "day_1200"]

# prepared network for a setting (fresh copy every call)
function do_net(setting, pu, pmap, P, Q)
    net = make_net(pu)
    # For 12:00, replace the 1 kW loads with each home's real usage at time step 25 (12:00)
    setting == "day_1200" && set_loads!(net, pmap, P, Q, 25)
    return net
end

# the two DOEs (kW, equal for every customer)
function do_does(setting, pu, pmap, P, Q)
    # Bound-point DOE (kW) and what limits it
    bound, b, _, _ = ts_doe(do_net(setting, pu, pmap, P, Q))
    # Phase-secure DOE: lowered by bisection until it is also safe when one or two whole phases
    # export nothing
    sec, _ = ps_doe(do_net(setting, pu, pmap, P, Q), bound)
    return [("bound_point", bound, b), ("phase_secure", sec, "7 patterns")]
end

# realised voltages when the customers in `dropped` export nothing and the rest export up to kw
function do_case(net, ids, dropped, kw)
    # Dropped homes get a cap of 0 (fr_realised then lets them export at most 1 W), everyone else
    # gets kw; then take the realised reading. Returns v (highest home voltage), n_over (homes above
    # 253 V) and who
    caps = Dict(id => (id in dropped ? 0.0 : kw) for id in ids)
    return fr_realised(net, caps)
end

# label like "ld1668_load_a+ld24_load_a" (customer ids sorted; "none" if nobody dropped)
do_label(dropped) = isempty(dropped) ? "none" : join(sort(collect(dropped)), "+")

# ---------------------------------------------------------------------------------------------
# DROPOUT-SECURE DOE: highest equal limit that stays <= 253 V (realised reading) for
#   nobody dropped + the 7 phase patterns + every set of 1 or 2 dropped customers (6 + 12 + 66
#   + 1 = 85 cases on LV3; the "abc" pattern is the same as nobody dropped).
# ---------------------------------------------------------------------------------------------

# all dropped-sets to check: phase patterns (customers NOT on the exporting phases are dropped)
# plus every set of up to `depth` customers
function ds_sets(net, depth)
    cps = connection_points(net)
    ids = sort([cp.id for cp in cps])
    # Which phase (a, b or c) each home is on: the first letter of its phase terminal
    ph  = Dict(cp.id => cp.phase_terminals[1][1] for cp in cps)
    # Case 1: nobody dropped (everyone exports)
    sets = [Set{String}()]
    # Next 6 cases: a phase pattern says which phases export; homes on the other phases are dropped
    for pat in PS_PATTERNS[2:end]                         # "bc","ac","ab","a","b","c"
        push!(sets, Set(id for id in ids if !(ph[id] in pat)))
    end
    # 12 cases: each single home dropped
    for i in eachindex(ids)
        push!(sets, Set([ids[i]]))
    end
    # 66 cases: every pair of homes dropped (12 x 11 / 2)
    if depth >= 2
        for i in eachindex(ids), j in i+1:length(ids)
            push!(sets, Set([ids[i], ids[j]]))
        end
    end
    # unique() removes any repeated case (1 + 6 + 12 + 66 = 85 cases on LV3)
    return ids, unique(sets)
end

# check one limit against all sets; stop at the first failure when early_stop
function ds_check(setting, pu, pmap, P, Q, ids, sets, kw; early_stop = true)
    worst_v = -Inf; worst = ""; nfail = 0
    for dropped in sets
        # Fresh network every time, then the realised reading with these homes dropped
        rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
        # Fails if the highest home voltage is above 253.005 V (a tiny 0.005 V margin); NaN (solve
        # failed) also fails, because NaN <= x is always false
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail
        # Remember the worst (highest) voltage and which case caused it
        rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
        # With early_stop, give up at the first failing case (saves time during the bisection)
        fail && early_stop && return (ok = false, v = rv.v, worst = do_label(dropped), nfail = nfail)
    end
    return (ok = nfail == 0, v = worst_v, worst = worst, nfail = nfail)
end

# bisection between 0.9 x hi and hi (hi = phase-secure DOE); falls back to 0 .. hi if needed
function ds_doe(setting, pu, pmap, P, Q, hi; depth = 2, iters = 8)
    # Build the list of cases once
    ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
    # If the phase-secure DOE already passes every case, it is also the dropout-secure DOE
    ds_check(setting, pu, pmap, P, Q, ids, sets, hi).ok && return hi
    # Otherwise search between 0.9 x and 1 x the phase-secure DOE; if even 0.9 x fails, widen the
    # search to 0 .. hi with more steps
    lo = 0.9 * hi
    if !ds_check(setting, pu, pmap, P, Q, ids, sets, lo).ok
        lo = 0.0; iters = 12
    end
    # Bisection: try the middle; if safe, raise the floor (lo), if not, lower the ceiling (hi). lo
    # is always a limit that passed (or 0), so the answer is on the safe side
    for it in 1:iters
        mid = (lo + hi) / 2
        r = ds_check(setting, pu, pmap, P, Q, ids, sets, mid)
        @printf("    bisection %2d: %.4f kW -> %s\n", it, mid, r.ok ? "safe" : @sprintf("fails (%.2f V, %s)", r.v, r.worst))
        r.ok ? (lo = mid) : (hi = mid)
    end
    return lo
end

# run_dropout_secure_lv3: for both settings, compute the bound-point, phase-secure and
# dropout-secure DOEs, re-check the dropout-secure one on ALL 85 cases, and write 2 rows to
# doe_dropout_secure_lv3.csv (REPRODUCE.md: 4.203 kW snapshot, 3.664 kW at 12:00)
function run_dropout_secure_lv3(; pu = RE_PU, depth = 2)
    t0 = time()
    # Read the 99 house-usage profiles and the sun shape, and fix which profile each of the 12 homes
    # gets (the same seeded choice every run)
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for setting in DO_SETTINGS
        # does[1] = bound-point DOE, does[2] = phase-secure DOE (both in kW)
        does = do_does(setting, pu, pmap, P, Q)
        bound = does[1][2]; sec = does[2][2]
        @printf("\n=== %s, %.3f pu: bound-point %.3f kW, phase-secure %.3f kW ===\n", setting, pu, bound, sec)
        # Search for the dropout-secure DOE, starting from the phase-secure one
        ds = ds_doe(setting, pu, pmap, P, Q, sec; depth = depth)
        ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
        # Final check: run all 85 cases (no early stop) to report the worst voltage and how many
        # fail
        chk = ds_check(setting, pu, pmap, P, Q, ids, sets, ds; early_stop = false)
        # % change vs the other two DOEs = 100 x (dropout-secure / other - 1); negative = smaller
        # (safer)
        @printf("  dropout-secure DOE %.3f kW (%+.1f %% vs bound point, %+.1f %% vs phase-secure)\n",
                ds, 100 * (ds / bound - 1), 100 * (ds / sec - 1))
        @printf("  final check over %d cases: worst %.2f V (%s), over 253 V: %d\n",
                length(sets), chk.v, chk.worst, chk.nfail)
        # CSV row: setting, pu, the three DOEs, the two % changes, number of cases, worst V and
        # case, number failing
        push!(rows, @sprintf("LV3,%s,%.3f,%.6f,%.6f,%.6f,%.3f,%.3f,%d,%.4f,%s,%d",
                             setting, pu, bound, sec, ds, 100 * (ds / bound - 1), 100 * (ds / sec - 1),
                             length(sets), chk.v, chk.worst, chk.nfail))
    end
    open(joinpath(pwd(), "results", "doe_dropout_secure_lv3.csv"), "w") do io
        println(io, "feeder,setting,source_pu,bound_point_kW,phase_secure_kW,dropout_secure_kW,change_vs_bound_pct,change_vs_phase_secure_pct,n_cases_checked,worst_V_VW,worst_case,n_fail")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_dropout_secure_lv3.csv (%.0f min)\n", (time() - t0) / 60)
end

# run_dropout_lv3: test the bound-point and phase-secure DOEs (as they are, not changed) on nobody
# dropped + every 1 or 2 dropped homes (79 cases), in both settings. Writes doe_dropout_lv3.csv
# (REPRODUCE.md: bound-point 13 and 28 cases over 253 V; phase-secure 8 and 2)
function run_dropout_lv3(; pu = RE_PU, depth = 2)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    ids  = sort([cp.id for cp in connection_points(make_net(pu))])
    n    = length(ids)
    sets = [Set{String}()]                                   # none dropped = bound point itself
    # Add every single home dropped (12) and every pair of homes dropped (66)
    for i in 1:n
        push!(sets, Set([ids[i]]))
    end
    if depth >= 2
        for i in 1:n, j in i+1:n
            push!(sets, Set([ids[i], ids[j]]))
        end
    end
    rows = String[]
    for setting in DO_SETTINGS
        # For each setting and each of the two DOEs...
        for (dname, kw, bind) in do_does(setting, pu, pmap, P, Q)
            @printf("\n=== %s, %.3f pu, %s DOE = %.3f kW (%s): %d cases ===\n",
                    setting, pu, dname, kw, bind, length(sets))
            worst_v = -Inf; worst = ""; nfail = 0; tb = time()
            for (k, dropped) in enumerate(sets)
                # ...take the realised reading with these homes dropped, and mark FAIL if above
                # 253.005 V
                rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
                fail = !(rv.v <= V_MAX_PN + 0.005)          # NaN (solver failure) also counts as fail
                nfail += fail
                rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
                # One CSV row per case: setting, pu, DOE type and kW, how many dropped, who, highest
                # V, homes over 253 V, ok/FAIL, which homes
                push!(rows, @sprintf("%s,%.3f,%s,%.6f,%d,%s,%.4f,%d,%s,\"%s\"",
                                     setting, pu, dname, kw, length(dropped), do_label(dropped),
                                     rv.v, rv.n_over, fail ? "FAIL" : "ok", rv.who))
                # Print the nobody-dropped result, and after 10 cases the time per case
                k == 1 && @printf("  nobody dropped (bound point): %.2f V, %d over 253 V\n", rv.v, rv.n_over)
                k == 10 && @printf("  ... %.1f s per case\n", (time() - tb) / 10)
            end
            @printf("  worst: %.2f V with %s dropped;  cases over 253 V: %d of %d\n",
                    worst_v, worst, nfail, length(sets))
        end
    end
    open(joinpath(pwd(), "results", "doe_dropout_lv3.csv"), "w") do io
        println(io, "setting,source_pu,doe_type,doe_kW,n_dropped,dropped,realised_V_VW,n_customers_over_253,result,customers_over_253")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_dropout_lv3.csv (%.0f s)\n", time() - t0)
end

# run_dropout_lv3_full: check ONE DOE (by default the dropout-secure one at 12:00) against every
# possible on/off mix of the 12 homes (4094 cases). Saves each case as it goes, so it can be resumed
# (REPRODUCE.md: 0 over 253 V, worst 253.00 V)
function run_dropout_lv3_full(; pu = RE_PU, setting = "day_1200", doe = "dropout_secure")
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    ids  = sort([cp.id for cp in connection_points(make_net(pu))])
    n    = length(ids)
    does = do_does(setting, pu, pmap, P, Q)
    # Pick the DOE to test: compute the dropout-secure one, or take the bound-point / phase-secure
    # one from do_does
    if doe == "dropout_secure"
        println("computing the dropout-secure DOE first (a few minutes)...")
        kw = ds_doe(setting, pu, pmap, P, Q, does[2][2])
    else
        _, kw, _ = only(filter(d -> d[1] == doe, does))
    end
    @printf("%s, %.3f pu, %s DOE = %.3f kW; checking all %d on/off combinations\n", setting, pu, doe, kw, 2^n - 2)
    # The output file name includes the setting and the DOE type
    file = joinpath(pwd(), "results", "doe_dropout_lv3_full_$(setting)_$(doe).csv")
    done = Set{Int}()
    if isfile(file)                                       # resume
        # Collect the mask numbers already in the file so they are skipped
        for l in Iterators.drop(eachline(file), 1)
            push!(done, parse(Int, split(l, ",")[1]))
        end
        @printf("resuming: %d already done\n", length(done))
    else
        # New file: write the header row
        open(file, "w") do io
            println(io, "mask,setting,source_pu,doe_type,doe_kW,n_dropped,dropped,realised_V_VW,n_customers_over_253,result")
        end
    end
    worst_v = -Inf; worst = ""; nfail = 0; count = 0; t1 = time()
    # Each mask number 1..4094 is a 12-bit on/off pattern; 0 (nobody dropped) and 4095 (everyone
    # dropped) are left out
    for mask in 1:(2^n - 2)                               # bit i set = customer ids[i] dropped
        mask in done && continue
        # Turn the mask's bits into the set of dropped homes
        dropped = Set(ids[i] for i in 1:n if (mask >> (i - 1)) & 1 == 1)
        rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail; count += 1
        rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
        # Append this case to the file straight away, so nothing is lost if the run is stopped
        open(file, "a") do io
            println(io, @sprintf("%d,%s,%.3f,%s,%.6f,%d,%s,%.4f,%d,%s", mask, setting, pu, doe, kw,
                                 length(dropped), do_label(dropped), rv.v, rv.n_over, fail ? "FAIL" : "ok"))
        end
        # Every 100 cases, print progress and a time estimate
        if count % 100 == 0
            left = 2^n - 2 - length(done) - count
            @printf("  %d done, %d left, about %.0f min to go; worst so far %.2f V (%s); fails %d\n",
                    count, left, left * (time() - t1) / count / 60, worst_v, worst, nfail)
        end
    end
    @printf("\nthis run: %d cases, worst %.2f V (%s), over 253 V: %d   (%.0f min)\n",
            count, worst_v, worst, nfail, (time() - t0) / 60)
    println("full results (including any earlier runs) in ", file)
end
