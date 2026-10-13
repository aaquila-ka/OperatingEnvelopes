# scripts/bmopf/doe_fairness.jl
#
# STEP 5: does the sharing rule decide who pays for a wrong record?
# Policies (PowerOptLab fairness): :equal (used so far), :proportional (maximise sum of log),
# :max_min (raise the smallest limit first, then the total).
# Cases on the TRUE street (records always say all 16 mm2):
#   l_3432 wrong  : only customer Ld1291's service cable is really 4 mm2 (the critical one)
#   l_4155 wrong  : only customer Ld1668's cable is really 4 mm2 (the mildest one)
#   all 22 wrong  : every service cable is really 4 mm2 (Case A)
# For each policy: issued limits = policy DOE on the records; correct limits = policy DOE on the
# true street. Per customer gap = issued - correct. Then the issued limits are applied on the
# true street (realised: inverters keep Volt-VAr, Volt-Watt, 5 kVA; no voltage limit imposed).
# Settings: CSIRO 1 kW snapshot and the 12:00 loads of the real day; source 1.03 pu.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_fairness.jl")
#   julia> run_fairness()
# OUTPUT results/doe_fairness_summary.csv, results/doe_fairness_customers.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

const FR_POLICIES = [:equal, :proportional, :max_min]

function fr_doe(net, policy)
    cps = connection_points(net)
    r = solve_operating_envelope(net, cps; fairness = policy, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    ok = isfinite(r.total_capacity[1])
    caps = Dict(cp.id => (ok ? r.envelope[cp.id][1] / 1000 : NaN) for cp in cps)
    return caps, string(r.termination_status[1])
end

# issued per-customer limits applied on a street: physical outcome
function fr_realised(net, caps)
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in RE_BUS_LIMIT_KEYS
        delete!(b, k)
    end
    cps = [ConnectionPoint(id = cp.id, bus = cp.bus, phase_terminals = cp.phase_terminals,
                           neutral = cp.neutral, export_max = max(1000.0 * caps[cp.id], 1.0),
                           ibr_id = cp.ibr_id) for cp in connection_points(ev)]
    r = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, curtail_kW = NaN)
    snap = r.snapshots[1]
    v, _ = max_pn(snap; only = customer_points(net))
    nover = count(pt -> max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005, collect(customer_points(net)))
    curtail = sum(caps[cp.id] - r.envelope[cp.id][1] / 1000 for cp in cps)
    return (v = v, n_over = nover, curtail_kW = curtail)
end

function one_wrong!(net, seg)
    net["line"][seg]["linecode"] = RE_SMALL_LC
    return net
end

function run_fairness(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    cases = [("l_3432_wrong", net -> one_wrong!(net, "l_3432")),
             ("l_4155_wrong", net -> one_wrong!(net, "l_4155")),
             ("all22_wrong",  net -> all_small!(net))]
    srows = String[]; crows = String[]
    for (sname, prep) in settings, policy in FR_POLICIES
        issued, ist = fr_doe(prep(make_net(pu)), policy)
        ids = sort(collect(keys(issued)))
        @printf("\n=== %s, %s: issued total %.2f kW, min %.3f, max %.3f kW [%s] ===\n", sname, policy,
                sum(values(issued)), minimum(values(issued)), maximum(values(issued)), ist)
        println("  case           correct total  min     | customers changed  total gap  max gap (who)          | realised V  >253  curtail")
        for (cname, wrong) in cases
            truth = wrong(prep(make_net(pu)))
            correct, cst = fr_doe(truth, policy)
            gaps = Dict(id => issued[id] - correct[id] for id in ids)
            nchg = count(id -> abs(gaps[id]) > 0.05, ids)
            worst = ids[argmax([gaps[id] for id in ids])]
            rv = fr_realised(truth, issued)
            @printf("  %-13s  %7.2f  %6.3f   |   %2d of 12        %+6.2f     %+6.3f (%-14s) |  %7.2f    %2d   %6.3f\n",
                    cname, sum(values(correct)), minimum(values(correct)), nchg,
                    sum(values(gaps)), gaps[worst], worst, rv.v, rv.n_over, rv.curtail_kW)
            push!(srows, @sprintf("%s,%.3f,%s,%s,%.6f,%.6f,%.6f,%.6f,%d,%.6f,%.6f,%s,%.4f,%d,%.6f,%s,%s",
                                  sname, pu, policy, cname, sum(values(issued)), minimum(values(issued)),
                                  sum(values(correct)), minimum(values(correct)), nchg,
                                  sum(values(gaps)), gaps[worst], worst, rv.v, rv.n_over, rv.curtail_kW, ist, cst))
            for id in ids
                push!(crows, @sprintf("%s,%.3f,%s,%s,%s,%.6f,%.6f,%.6f",
                                      sname, pu, policy, cname, id, issued[id], correct[id], gaps[id]))
            end
        end
    end
    open(joinpath(pwd(), "results", "doe_fairness_summary.csv"), "w") do io
        println(io, "setting,source_pu,policy,case,issued_total_kW,issued_min_kW,correct_total_kW,correct_min_kW,n_customers_changed,total_gap_kW,max_gap_kW,max_gap_customer,realised_V_VW,n_customers_over_253,curtail_kW,issued_status,correct_status")
        foreach(l -> println(io, l), srows)
    end
    open(joinpath(pwd(), "results", "doe_fairness_customers.csv"), "w") do io
        println(io, "setting,source_pu,policy,case,customer,issued_kW,correct_kW,gap_kW")
        foreach(l -> println(io, l), crows)
    end
    @printf("\nwritten results/doe_fairness_summary.csv (%d rows) and doe_fairness_customers.csv (%d rows)  (%.0f s)\n",
            length(srows), length(crows), time() - t0)
end
