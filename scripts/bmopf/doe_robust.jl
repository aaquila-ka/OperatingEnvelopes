# =============================================================================
# doe_robust.jl: what can a utility do about wrong cable records? (hedge vs check records)
#
# What it does (plain English):
#   Part A, "hedge in advance" (CSIRO-style robust DOE): assume every service cable's
#     resistance may be up to b higher than recorded (b = 5, 10, 20 %) and issue the DOE that is
#     safe for that worst case. Cost = export given up compared with the clean DOE.
#     Cross-check: the same robust DOE solved with PowerOptLab's scenario feature (one envelope
#     valid for R x (1-b), R x 1, R x (1+b), and a MIXED case where the critical customer's cable
#     l_3432 is +b and all others -b) should equal the uniform worst case R x (1+b).
#   Part B, "check the records first": the 12 customer service cables are checked one by one in
#     three orders: longest first (a ranking a utility can make from its GIS without any OPF),
#     OPF-ranked (harm ranking from results/doe_critical_cables.csv) and shortest first
#     (contrast). Unchecked customer cables are assumed to be the thinnest type (4 mm2), checked
#     ones are known to be 16 mm2. We report how much export is recovered after k checks.
#   Note: the DOE is very slightly non-monotone in single-cable resistance (Volt-VAr coupling),
#     so "thinnest everywhere" is the worst case only to within about 0.02 kW; "safe" in Part B
#     is meant in that sense (e.g. k = 11 at 12:00 gives 4.252599 vs clean 4.252542 kW).
#   Settings: CSIRO 1 kW snapshot and the 12:00 loads of the profile day; source 1.03 pu.
#
# Inputs:   LV3 network (data/networks/LV3_55bus_withPV/ via load_lv3.jl), house profiles
#           data/profiles/TeamNando_OE1_LoadShapes.txt. Includes doe_timeseries.jl (which
#           includes doe_record_errors.jl -> doe_common.jl -> load_lv3.jl).
# Outputs:  results/doe_robust.csv (84 rows); prints a table per setting.
#           Column "status": Part A rows hold the scenario-check solve status, Part B rows the
#           status of that row's DOE solve.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_robust.jl")   then   run_robust()
# Used for: REPRODUCE.md step 12 (section 4 row "Robust, 12:00"); DATA_CARD.md file 10.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

# Resistance margins b to hedge against: 5, 10 and 20 % higher than recorded
const RB_BOUNDS = [0.05, 0.10, 0.20]
# ranking by harm from results/doe_critical_cables.csv (one cable at a time, 1 kW snapshot)
const RB_OPF_ORDER = ["l_3432", "l_3656", "l_1243", "l_2791", "l_54", "l_2000",
                      "l_4294", "l_3254", "l_2249", "l_504", "l_2641", "l_4155"]

# each service segment its own copy of the line code with diagonal R x f[id] (default 1)
# Returns the network with segment id's diagonal resistance multiplied by f[id]; segments not in f stay as recorded
function scale_R_each!(net, f::Dict)
    ids  = re_service_ids(net)
    base = net["linecode"][RE_SVC_LC]
    for id in ids
        # Factor for this segment; 1 means "as recorded", so nothing to do
        fi = get(f, id, 1.0)
        fi == 1.0 && continue
        # Own copy of the line code, so the change only affects this segment
        lc = deepcopy(base)
        for key in collect(keys(lc))
            # Only the diagonal resistances R_series_i_i (each wire's own resistance) are scaled
            m = match(r"^R_series_(\d+)_(\d+)$", key)
            m === nothing && continue
            m[1] == m[2] && (lc[key] = fi * Float64(lc[key]))
        end
        # Save the copy under a new name and point this segment at it
        name = RE_SVC_LC * "_seg_" * id
        net["linecode"][name] = lc
        net["line"][id]["linecode"] = name
    end
    return net
end
# The MIXED test case: the critical cable l_3432 is b too high, every other service cable b too low
mixed_f(b, ids) = Dict(id => (id == "l_3432" ? 1 + b : 1 - b) for id in ids)

# all 22 service segments: diagonal R x f (one shared copy of the line code)
# Returns the network with ALL 22 service cables' diagonal resistance multiplied by the same f
function scale_R_all!(net, f)
    f == 1.0 && return net
    ids = re_service_ids(net)
    lc  = deepcopy(net["linecode"][RE_SVC_LC])
    nd  = 0
    for key in collect(keys(lc))
        m = match(r"^R_series_(\d+)_(\d+)$", key)
        m === nothing && continue
        if m[1] == m[2]
            lc[key] = f * Float64(lc[key])
            nd += 1
        end
    end
    @assert nd == 4 "expected 4 diagonal R entries, found $nd"
    # One shared scaled line code (named e.g. "..._x1.1"), then point all 22 segments at it
    name = RE_SVC_LC * "_x" * string(f)
    net["linecode"][name] = lc
    for id in ids
        net["line"][id]["linecode"] = name
    end
    return net
end

# the 12 service segments that touch a customer bus, longest first
# Returns the 12 service cables that connect to a home, sorted longest first
function customer_cables(net)
    # Buses where a home is connected (lower case, so the name match is safe)
    lb  = Set(lowercase(String(l["bus"])) for l in values(net["load"]))
    # Keep a service cable if either end is a home bus
    ids = [id for id in re_service_ids(net)
           if lowercase(String(net["line"][id]["bus_from"])) in lb ||
              lowercase(String(net["line"][id]["bus_to"])) in lb]
    @assert length(ids) == 12 "expected 12 customer service cables, found $(length(ids))"
    return sort(ids; by = id -> -Float64(net["line"][id]["length"]))
end

# one envelope valid for several network scenarios (PowerOptLab scenario feature)
# Solves ONE equal-share DOE (DOE = the export limit every home gets) that must be safe on every street
# in the list at once; returns the per-home limit in kW and the solver status
function doe_scenarios(nets)
    cps = connection_points(nets[1])
    # Passing the list of streets (as [nets]) is how PowerOptLab's scenario feature is asked for one shared envelope
    r = solve_operating_envelope([nets], cps; fairness = :equal, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    return r.envelope[cps[1].id][1] / 1000, string(r.termination_status[1])
end

# Main run: for the 1 kW snapshot and the 12:00 loads, Part A (hedge) and Part B (check records), then write the CSV
function run_robust(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # Two settings: the snapshot keeps the CSIRO loads; "day_1200" puts on the half-hour 25 (12:00) loads
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    rows = String[]
    for (name, prep) in settings
        # Clean DOE (records right, all 16 mm2) and the DOE if every service cable were 4 mm2
        clean, cb, _, cst = ts_doe(prep(make_net(pu)))
        small, _, _, _    = ts_doe(all_small!(prep(make_net(pu))))
        @printf("\n=== %s, %.3f pu: clean DOE %.3f kW (%s), all 4 mm2 %.3f kW ===\n", name, pu, clean, cb, small)

        println("Part A: hedge against +b resistance on every service cable")
        println("   b      robust kW   cost vs clean   scenario check kW  [status]")
        # Part A: the robust DOE assumes every service cable is (1 + b) times its recorded resistance
        for b in RB_BOUNDS
            rob, _, _, rst = ts_doe(scale_R_all!(prep(make_net(pu)), 1 + b))
            # Cross-check: one envelope valid for R x (1-b), R x 1, R x (1+b) and the mixed case; it should equal the robust DOE
            ids22 = re_service_ids(prep(make_net(pu)))
            chk, cst2 = doe_scenarios([scale_R_all!(prep(make_net(pu)), 1 - b), prep(make_net(pu)),
                                       scale_R_all!(prep(make_net(pu)), 1 + b),
                                       scale_R_each!(prep(make_net(pu)), mixed_f(b, ids22))])
            # Cost of hedging in %: 100 x (robust / clean - 1), negative = export given up
            cost = 100 * (rob / clean - 1)
            @printf("  %4.2f    %7.3f      %+7.1f %%        %7.3f          [%s]\n", b, rob, cost, chk, cst2)
            # Part A CSV row (param = b; the verified_segments column is left empty)
            push!(rows, @sprintf("%s,%.3f,A_hedge,%.2f,,%.6f,%.6f,%.6f,%.3f,%.6f,%s",
                                 name, pu, b, clean, small, rob, cost, chk, cst2))
        end

        # Part B: the 12 home cables in three checking orders
        net0 = prep(make_net(pu))
        ids  = customer_cables(net0)
        println("Part B: verify customer cables one by one (unverified = 4 mm2)")
        # Safety check that the OPF ranking lists exactly the same 12 cables
        @assert Set(RB_OPF_ORDER) == Set(ids) "OPF ranking does not match the 12 customer cables"
        for (oname, order) in (("longest_first", ids), ("opf_ranked", RB_OPF_ORDER), ("shortest_first", reverse(ids)))
            @printf("  order %s: %s\n", oname, join(order, " "))
            println("   k checked   safe DOE kW   cost vs clean")
            # k = how many cables have been checked so far (0 to 12)
            for k in 0:12
                # Fresh street: the first k cables in this order are checked (left at 16 mm2), the rest are assumed 4 mm2
                net = prep(make_net(pu))
                for id in order[k+1:end]
                    net["line"][id]["linecode"] = RE_SMALL_LC
                end
                # The DOE that is safe given what is known, and its cost vs the clean DOE in %
                kw, _, _, st = ts_doe(net)
                cost = 100 * (kw / clean - 1)
                @printf("   %2d          %7.3f      %+7.1f %%\n", k, kw, cost)
                # Part B CSV row: param = k, plus the list of cables checked so far
                push!(rows, @sprintf("%s,%.3f,B_verify_%s,%d,\"%s\",%.6f,%.6f,%.6f,%.3f,,%s",
                                     name, pu, oname, k, join(order[1:k], ";"), clean, small, kw, cost, st))
            end
        end
    end
    # Write the header and all rows
    open(joinpath(pwd(), "results", "doe_robust.csv"), "w") do io
        println(io, "setting,source_pu,part,param,verified_segments,clean_kW,all_4mm2_kW,safe_DOE_kW,cost_vs_clean_pct,scenario_check_kW,status")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_robust.csv (%d rows, %.0f s)\n", length(rows), time() - t0)
end
