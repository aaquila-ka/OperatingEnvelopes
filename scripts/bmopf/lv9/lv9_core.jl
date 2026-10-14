# =============================================================================
# lv9_core.jl: main LV9 record-error experiments (by segment kind, one at a time, sharing rules)
#
# What it does (plain English): on LV9 the 16 mm2 line code is used for three kinds of
#   segment, found by tracing the radial tree from the transformer LV bus (b342):
#     drops    : the 123 segments that end at a customer bus (the customer's own service cable)
#     upstream : the 12 segments that do not end at a customer bus but have customers behind
#                them (shared mains; 11 carry 2-43 customers, l_3156 carries 1). A separate
#                check found the same 12 (l_72 l_1557 l_1752 l_2373 l_2525 l_2783 l_2897
#                l_3156 l_3443 l_3542 l_3635 l_4010); the script warns if the trace differs.
#     stubs    : 44 dead-end segments with no customer behind them (carry no current)
#   Records always say 16 mm2. Cases on the TRUE street: drops / upstream / all 179 really
#   4 mm2. Equal allocation unless stated. Gap = DOE from records minus correct DOE.
#   Realised reading as on LV3 (everyone may export up to the issued DOE; Volt-VAr,
#   Volt-Watt, 5 kVA kept; no voltage limit).
# Inputs:   data/networks/LV9_258bus_withPV/; includes lv9_common.jl.
# Outputs:  results/lv9/lv9_sweep.csv and lv9_segments.csv (run_lv9_sweep),
#           lv9_single_drops_<pu>.csv (run_lv9_single), lv9_single_upstream_<pu>.csv
#           (run_lv9_upstream), lv9_fairness.csv (run_lv9_fairness); tables printed.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_core.jl")   then
#   run_lv9_sweep()           # 0.94 / 0.97 / 1.00 pu x {drops, upstream, all}   (~10 min)
#   run_lv9_upstream(0.94)    # each of the 12 shared segments alone              (~3 min)
#   run_lv9_single(0.94)      # each of the 123 drops alone                       (~30 min)
#   run_lv9_fairness(0.94)    # equal vs proportional, longest drop and upstream_12
#   (the functions default to 1.00 pu; the thesis results use 0.94 pu as above)
# Used for: REPRODUCE.md step 21 (section 4 rows "LV9 shared vs drops").
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))

const LV_ROOT = "b342"
const AUDIT_UPSTREAM = Set(["l_72", "l_1557", "l_1752", "l_2373", "l_2525", "l_2783",
                            "l_2897", "l_3156", "l_3443", "l_3542", "l_3635", "l_4010"])

# ---- radial tree: for every 16 mm2 segment, how many customers are downstream, and its kind
function classify_segments(net)
    adj = Dict{String,Vector{Tuple{String,String}}}()          # bus => [(neighbour, edge id)]
    addedge(a, b, id) = (push!(get!(adj, a, Tuple{String,String}[]), (b, id));
                         push!(get!(adj, b, Tuple{String,String}[]), (a, id)))
    for (id, l) in net["line"]
        addedge(lowercase(String(l["bus_from"])), lowercase(String(l["bus_to"])), String(id))
    end
    for (id, s) in get(net, "switch", Dict())
        get(s, "open_switch", false) && continue
        addedge(lowercase(String(s["bus_from"])), lowercase(String(s["bus_to"])), "switch:" * String(id))
    end
    parent = Dict{String,Tuple{String,String}}(); dist = Dict(LV_ROOT => 0.0)
    queue = [LV_ROOT]; seen = Set([LV_ROOT])
    while !isempty(queue)
        a = popfirst!(queue)
        for (b, id) in get(adj, a, Tuple{String,String}[])
            b in seen && continue
            push!(seen, b); parent[b] = (a, id)
            len = startswith(id, "switch:") ? 0.0 : Float64(get(net["line"][id], "length", 0.0))
            dist[b] = dist[a] + len
            push!(queue, b)
        end
    end
    custbus = Dict(lowercase(String(l["bus"])) => String(lid) for (lid, l) in net["load"])
    ncust = Dict{String,Int}(); path_of = Dict{String,Vector{String}}()
    for (cb, lid) in custbus
        @assert haskey(parent, cb) || cb == LV_ROOT "customer bus $cb not reachable from $LV_ROOT"
        b = cb; p = String[]
        while b != LV_ROOT
            (a, id) = parent[b]; push!(p, id); ncust[id] = get(ncust, id, 0) + 1; b = a
        end
        path_of[lid] = p
    end
    kinds = Dict{String,String}()
    for id in service_ids(net)
        l = net["line"][id]
        touches = lowercase(String(l["bus_from"])) in keys(custbus) || lowercase(String(l["bus_to"])) in keys(custbus)
        n = get(ncust, id, 0)
        kinds[id] = n == 0 ? "stub" : (touches && n == 1) ? "drop" : "upstream"
    end
    return kinds, ncust, dist, custbus, path_of
end

function set_small!(net, ids)
    for id in ids
        net["line"][id]["linecode"] = SMALL_LC
    end
    return net
end

function segment_sets(net)
    kinds, ncust, dist, custbus, path_of = classify_segments(net)
    drops = sort([k for (k, v) in kinds if v == "drop"])
    up    = sort([k for (k, v) in kinds if v == "upstream"])
    stubs = sort([k for (k, v) in kinds if v == "stub"])
    @printf("16 mm2 segments: %d drops, %d upstream (shared), %d stubs\n", length(drops), length(up), length(stubs))
    println("upstream: ", join(up, " "))
    @assert length(drops) == N_CUST "expected $N_CUST drops"
    Set(up) == AUDIT_UPSTREAM || println("WARNING: upstream set differs from the independent audit")
    return drops, up, stubs, kinds, ncust, dist, custbus, path_of
end

function run_lv9_sweep(; pus = [0.94, 0.97, 1.00])
    t0 = time()
    mkpath(joinpath(pwd(), "results", "lv9"))
    net1 = make_net(1.00)
    drops, up, stubs, kinds, ncust, dist, _, _ = segment_sets(net1)
    open(joinpath(pwd(), "results", "lv9", "lv9_segments.csv"), "w") do io
        println(io, "segment,kind,customers_downstream,length_m")
        for id in sort(collect(keys(kinds)))
            @printf(io, "%s,%s,%d,%.4f\n", id, kinds[id], get(ncust, id, 0), Float64(net1["line"][id]["length"]))
        end
    end
    cases = [("drops_123", drops), ("upstream_12", up), ("all_179", vcat(drops, up, stubs))]
    println("\n  pu    (LV3-eq) | clean kW  bind     | case          correct kW  gap kW  over-prom | realised V  >253  curtail kW")
    rows = String[]
    for pu in pus
        clean, cb, cv, cst, _ = eq_doe(make_net(pu))
        for (cname, ids) in cases
            truth = set_small!(make_net(pu), ids)
            a, ab, _, ast, _ = eq_doe(truth)
            rv = realised(truth, clean)
            @printf(" %5.3f  (%5.3f)  | %7.3f  %-8s | %-12s  %7.3f   %+6.3f  %+7.1f %% |  %7.2f    %3d    %6.3f\n",
                    pu, pu * LV9_EQUIV, clean, cb, cname, a, clean - a, 100 * (clean / a - 1), rv.v, rv.n_over, rv.curtail_kW)
            push!(rows, @sprintf("%.3f,%.4f,%.6f,%s,%s,%.6f,%s,%.6f,%.3f,%.4f,%d,%.6f,%s,%s",
                                 pu, pu * LV9_EQUIV, clean, cb, cname, a, ab, clean - a, 100 * (clean / a - 1),
                                 rv.v, rv.n_over, rv.curtail_kW, cst, ast))
        end
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_sweep.csv"), "w") do io
        println(io, "source_pu,lv3_equiv_pu,clean_kW,clean_binding,case,correct_kW,correct_binding,gap_kW,overpromise_pct,realised_V_VW,n_customers_over_253,curtail_kW,clean_status,correct_status")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_sweep.csv and lv9_segments.csv  (%.0f s)\n", time() - t0)
end

# each drop alone at one source voltage: does LV3's screening rule (length + headroom) hold?
function run_lv9_single(pu = 1.00)
    t0 = time()
    net0 = make_net(pu)
    drops, _, _, _, _, dist, custbus, _ = segment_sets(net0)
    clean, cb, _, _, r = eq_doe(net0)
    snap = r.snapshots[1]
    @printf("clean equal DOE %.3f kW (%s) at %.3f pu\n", clean, cb, pu)
    bus2cust = Dict(b => lid for (b, lid) in custbus)
    rows = String[]
    println("  drop        customer          length m  dist m  headroom V | correct kW  gap kW | realised V  >253")
    for (i, id) in enumerate(drops)
        l  = net0["line"][id]
        bf = lowercase(String(l["bus_from"])); bt = lowercase(String(l["bus_to"]))
        cbus = haskey(bus2cust, bf) ? bf : bt
        lid = bus2cust[cbus]; ph = String(net0["load"][lid]["terminal_map"][1])
        head = V_MAX_PN - vpn(snap["bus"][cbus], ph)
        try
            truth = set_small!(make_net(pu), [id])
            a, _, _, _, _ = eq_doe(truth)
            rv = realised(truth, clean)
            @printf("  %-10s  %-16s  %7.2f  %6.1f   %6.3f    |  %7.3f  %+6.3f |  %7.2f    %3d   (%d/%d)\n",
                    id, lid, Float64(l["length"]), dist[cbus], head, a, clean - a, rv.v, rv.n_over, i, length(drops))
            push!(rows, @sprintf("%.3f,%s,%s,%s,%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.4f,%d,%.6f,\"%s\"",
                                 pu, id, lid, cbus, Float64(l["length"]), dist[cbus], head, clean, a, clean - a,
                                 rv.v, rv.n_over, rv.curtail_kW, rv.who))
        catch err
            println("  ", id, "  ERROR: ", first(sprint(showerror, err), 100))
        end
    end
    open(joinpath(pwd(), "results", "lv9", @sprintf("lv9_single_drops_%.2f.csv", pu)), "w") do io
        println(io, "source_pu,segment,customer,customer_bus,length_m,distance_from_tx_m,clean_headroom_V,clean_kW,correct_kW,gap_kW,realised_V_VW,n_customers_over_253,curtail_kW,customers_over_253")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_single_drops_%.2f.csv (%d rows, %.0f s)\n", pu, length(rows), time() - t0)
end

# equal vs proportional for one wrong drop (given) and for the 12 upstream segments
function run_lv9_fairness(pu = 1.00; drop = "")
    t0 = time()
    net0 = make_net(pu)
    drops, up, _, _, _, _, _, _ = segment_sets(net0)
    if isempty(drop)       # default: the longest customer drop
        drop = sort(drops; by = id -> -Float64(net0["line"][id]["length"]))[1]
    end
    rows = String[]
    for policy in (:equal, :proportional)
        cps = connection_points(net0)
        ri  = doe(make_net(pu), cps; fairness = policy)
        issued = Dict(cp.id => ri.envelope[cp.id][1] / 1000 for cp in cps)
        @printf("\n=== %s: issued total %.1f kW, min %.3f kW ===\n", policy, sum(values(issued)), minimum(values(issued)))
        for (cname, ids) in (("drop_" * drop, [drop]), ("upstream_12", up))
            truth = set_small!(make_net(pu), ids)
            rc = doe(truth, connection_points(truth); fairness = policy)
            correct = Dict(cp.id => rc.envelope[cp.id][1] / 1000 for cp in cps)
            gaps = [issued[k] - correct[k] for k in keys(issued)]
            nchg = count(g -> abs(g) > 0.05, gaps)
            rv = realised(truth, issued)
            @printf("  %-16s changed %3d of %d | total gap %+7.2f kW | realised %7.2f V, %3d over 253 V, curtail %.2f kW\n",
                    cname, nchg, N_CUST, sum(gaps), rv.v, rv.n_over, rv.curtail_kW)
            push!(rows, @sprintf("%.3f,%s,%s,%.6f,%.6f,%d,%.6f,%.4f,%d,%.6f,\"%s\"",
                                 pu, policy, cname, sum(values(issued)), sum(values(correct)), nchg, sum(gaps),
                                 rv.v, rv.n_over, rv.curtail_kW, rv.n_over > 10 ? "" : rv.who))
        end
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_fairness.csv"), "w") do io
        println(io, "source_pu,policy,case,issued_total_kW,correct_total_kW,n_customers_changed,total_gap_kW,realised_V_VW,n_customers_over_253,curtail_kW,customers_over_253")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_fairness.csv (%.0f s)\n", time() - t0)
end

# each of the 12 shared (upstream) 16 mm2 segments alone
function run_lv9_upstream(pu = 1.00)
    t0 = time()
    net0 = make_net(pu)
    _, up, _, _, ncust, _, _, _ = segment_sets(net0)
    clean, cb, _, _, _ = eq_doe(net0)
    @printf("clean equal DOE %.3f kW (%s) at %.3f pu\n", clean, cb, pu)
    println("  segment   customers behind  length m | correct kW  gap kW | realised V  >253  curtail kW")
    rows = String[]
    for id in sort(up; by = id -> -get(ncust, id, 0))
        truth = set_small!(make_net(pu), [id])
        a, _, _, _, _ = eq_doe(truth)
        rv = realised(truth, clean)
        @printf("  %-8s   %4d             %7.2f  |  %7.3f   %+6.3f |  %7.2f    %3d    %6.3f\n",
                id, get(ncust, id, 0), Float64(net0["line"][id]["length"]), a, clean - a, rv.v, rv.n_over, rv.curtail_kW)
        push!(rows, @sprintf("%.3f,%s,%d,%.4f,%.6f,%.6f,%.6f,%.4f,%d,%.6f",
                             pu, id, get(ncust, id, 0), Float64(net0["line"][id]["length"]), clean, a, clean - a,
                             rv.v, rv.n_over, rv.curtail_kW))
    end
    open(joinpath(pwd(), "results", "lv9", @sprintf("lv9_single_upstream_%.2f.csv", pu)), "w") do io
        println(io, "source_pu,segment,customers_downstream,length_m,clean_kW,correct_kW,gap_kW,realised_V_VW,n_customers_over_253,curtail_kW")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_single_upstream_%.2f.csv (%.0f s)\n", pu, time() - t0)
end
