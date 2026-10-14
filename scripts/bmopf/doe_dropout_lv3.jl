# scripts/bmopf/doe_dropout_lv3.jl
#
# DROPOUT CHECK on LV3 (Liu & Braslavsky 2022; PowerOptLab doe_dropout_utilizations idea).
# A DOE is only checked at the "bound point" (everyone exports their full limit). On an
# unbalanced four-wire feeder, some customers exporting NOTHING can shift the neutral and push
# other customers higher. Here we take an issued equal DOE and apply it on the correct network
# with some customers dropped to zero export, and read the realised voltages
# (Volt-VAr, Volt-Watt, 5 kVA kept; no voltage limit imposed; same reading as fr_realised).
#
# Two DOEs are tested:  bound-point equal DOE, and our phase-secure DOE (7 phase patterns).
# Two settings:         1 kW snapshot, and 12:00 of the profile day (day 350), at 1.03 pu.
#
#  run_dropout_lv3()       every set of 1 or 2 dropped customers (12 + 66 = 78 cases)
#                          x 2 DOEs x 2 settings = 312 solves (about 10-20 min)
#  run_dropout_secure_lv3() DROPOUT-SECURE DOE: highest equal limit that passes the 7 phase
#                          patterns AND every 1- or 2-customer dropout (bisection; ~5-10 min)
#  run_dropout_lv3_full()  EVERY on/off combination (2^12 - 2 = 4094 cases) for ONE DOE and
#                          ONE setting (default: dropout-secure DOE, 12:00). About 30 min
#                          (~0.4 s per case). Writes as it goes; if stopped, run it again and it
#                          continues. Other choices: doe = "phase_secure" or "bound_point",
#                          setting = "snapshot_1kW".
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_dropout_lv3.jl")
#   julia> run_dropout_lv3()
#   julia> run_dropout_secure_lv3()
#   julia> run_dropout_lv3_full()
# OUTPUT results/doe_dropout_lv3.csv, results/doe_dropout_secure_lv3.csv,
#        results/doe_dropout_lv3_full_<setting>_<doe>.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_fairness.jl"))          # fr_realised, read_profiles, ...
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))     # ps_doe

const DO_SETTINGS = ["snapshot_1kW", "day_1200"]

# prepared network for a setting (fresh copy every call)
function do_net(setting, pu, pmap, P, Q)
    net = make_net(pu)
    setting == "day_1200" && set_loads!(net, pmap, P, Q, 25)
    return net
end

# the two DOEs (kW, equal for every customer)
function do_does(setting, pu, pmap, P, Q)
    bound, b, _, _ = ts_doe(do_net(setting, pu, pmap, P, Q))
    sec, _ = ps_doe(do_net(setting, pu, pmap, P, Q), bound)
    return [("bound_point", bound, b), ("phase_secure", sec, "7 patterns")]
end

# realised voltages when the customers in `dropped` export nothing and the rest export up to kw
function do_case(net, ids, dropped, kw)
    caps = Dict(id => (id in dropped ? 0.0 : kw) for id in ids)
    return fr_realised(net, caps)
end

# label like "c3+c7" (customer ids sorted)
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
    ph  = Dict(cp.id => cp.phase_terminals[1][1] for cp in cps)
    sets = [Set{String}()]
    for pat in PS_PATTERNS[2:end]                         # "bc","ac","ab","a","b","c"
        push!(sets, Set(id for id in ids if !(ph[id] in pat)))
    end
    for i in eachindex(ids)
        push!(sets, Set([ids[i]]))
    end
    if depth >= 2
        for i in eachindex(ids), j in i+1:length(ids)
            push!(sets, Set([ids[i], ids[j]]))
        end
    end
    return ids, unique(sets)
end

# check one limit against all sets; stop at the first failure when early_stop
function ds_check(setting, pu, pmap, P, Q, ids, sets, kw; early_stop = true)
    worst_v = -Inf; worst = ""; nfail = 0
    for dropped in sets
        rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail
        rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
        fail && early_stop && return (ok = false, v = rv.v, worst = do_label(dropped), nfail = nfail)
    end
    return (ok = nfail == 0, v = worst_v, worst = worst, nfail = nfail)
end

# bisection between 0.9 x hi and hi (hi = phase-secure DOE); falls back to 0 .. hi if needed
function ds_doe(setting, pu, pmap, P, Q, hi; depth = 2, iters = 8)
    ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
    ds_check(setting, pu, pmap, P, Q, ids, sets, hi).ok && return hi
    lo = 0.9 * hi
    if !ds_check(setting, pu, pmap, P, Q, ids, sets, lo).ok
        lo = 0.0; iters = 12
    end
    for it in 1:iters
        mid = (lo + hi) / 2
        r = ds_check(setting, pu, pmap, P, Q, ids, sets, mid)
        @printf("    bisection %2d: %.4f kW -> %s\n", it, mid, r.ok ? "safe" : @sprintf("fails (%.2f V, %s)", r.v, r.worst))
        r.ok ? (lo = mid) : (hi = mid)
    end
    return lo
end

function run_dropout_secure_lv3(; pu = RE_PU, depth = 2)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for setting in DO_SETTINGS
        does = do_does(setting, pu, pmap, P, Q)
        bound = does[1][2]; sec = does[2][2]
        @printf("\n=== %s, %.3f pu: bound-point %.3f kW, phase-secure %.3f kW ===\n", setting, pu, bound, sec)
        ds = ds_doe(setting, pu, pmap, P, Q, sec; depth = depth)
        ids, sets = ds_sets(do_net(setting, pu, pmap, P, Q), depth)
        chk = ds_check(setting, pu, pmap, P, Q, ids, sets, ds; early_stop = false)
        @printf("  dropout-secure DOE %.3f kW (%+.1f %% vs bound point, %+.1f %% vs phase-secure)\n",
                ds, 100 * (ds / bound - 1), 100 * (ds / sec - 1))
        @printf("  final check over %d cases: worst %.2f V (%s), over 253 V: %d\n",
                length(sets), chk.v, chk.worst, chk.nfail)
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

function run_dropout_lv3(; pu = RE_PU, depth = 2)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    ids  = sort([cp.id for cp in connection_points(make_net(pu))])
    n    = length(ids)
    sets = [Set{String}()]                                   # none dropped = bound point itself
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
        for (dname, kw, bind) in do_does(setting, pu, pmap, P, Q)
            @printf("\n=== %s, %.3f pu, %s DOE = %.3f kW (%s): %d cases ===\n",
                    setting, pu, dname, kw, bind, length(sets))
            worst_v = -Inf; worst = ""; nfail = 0; tb = time()
            for (k, dropped) in enumerate(sets)
                rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
                fail = !(rv.v <= V_MAX_PN + 0.005)          # NaN (solver failure) also counts as fail
                nfail += fail
                rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
                push!(rows, @sprintf("%s,%.3f,%s,%.6f,%d,%s,%.4f,%d,%s,\"%s\"",
                                     setting, pu, dname, kw, length(dropped), do_label(dropped),
                                     rv.v, rv.n_over, fail ? "FAIL" : "ok", rv.who))
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

function run_dropout_lv3_full(; pu = RE_PU, setting = "day_1200", doe = "dropout_secure")
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    ids  = sort([cp.id for cp in connection_points(make_net(pu))])
    n    = length(ids)
    does = do_does(setting, pu, pmap, P, Q)
    if doe == "dropout_secure"
        println("computing the dropout-secure DOE first (a few minutes)...")
        kw = ds_doe(setting, pu, pmap, P, Q, does[2][2])
    else
        _, kw, _ = only(filter(d -> d[1] == doe, does))
    end
    @printf("%s, %.3f pu, %s DOE = %.3f kW; checking all %d on/off combinations\n", setting, pu, doe, kw, 2^n - 2)
    file = joinpath(pwd(), "results", "doe_dropout_lv3_full_$(setting)_$(doe).csv")
    done = Set{Int}()
    if isfile(file)                                       # resume
        for l in Iterators.drop(eachline(file), 1)
            push!(done, parse(Int, split(l, ",")[1]))
        end
        @printf("resuming: %d already done\n", length(done))
    else
        open(file, "w") do io
            println(io, "mask,setting,source_pu,doe_type,doe_kW,n_dropped,dropped,realised_V_VW,n_customers_over_253,result")
        end
    end
    worst_v = -Inf; worst = ""; nfail = 0; count = 0; t1 = time()
    for mask in 1:(2^n - 2)                               # bit i set = customer ids[i] dropped
        mask in done && continue
        dropped = Set(ids[i] for i in 1:n if (mask >> (i - 1)) & 1 == 1)
        rv = do_case(do_net(setting, pu, pmap, P, Q), ids, dropped, kw)
        fail = !(rv.v <= V_MAX_PN + 0.005)
        nfail += fail; count += 1
        rv.v > worst_v && (worst_v = rv.v; worst = do_label(dropped))
        open(file, "a") do io
            println(io, @sprintf("%d,%s,%.3f,%s,%.6f,%d,%s,%.4f,%d,%s", mask, setting, pu, doe, kw,
                                 length(dropped), do_label(dropped), rv.v, rv.n_over, fail ? "FAIL" : "ok"))
        end
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
