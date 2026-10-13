# scripts/bmopf/doe_robust.jl
#
# STEP 4: what can a utility DO about wrong cable records?
# Part A, "hedge in advance" (CSIRO-style robust DOE): assume every service cable's resistance
#   may be up to b higher than recorded (b = 5, 10, 20 %) and issue the DOE that is safe for the
#   worst case. Cost = export given up compared with the clean DOE.
#   Check: the same robust DOE solved with PowerOptLab's scenario feature
#   (one envelope valid for R x (1-b), R x 1, R x (1+b), and a MIXED case where the critical
#   customer's cable l_3432 is +b and all others -b) should equal the uniform worst case R x (1+b).
#   v2: mixed scenario added; Part B adds an OPF-ranked order (from doe_critical_cables.csv).
#   Note (second review): the DOE is very slightly non-monotone in single-cable resistance
#   (Volt-VAr coupling), so 'thinnest everywhere' is the worst case only to within ~0.02 kW.
# Part B, "check the records first": the 12 customer service cables are verified one by one,
#   longest first (a ranking a utility can make from its GIS without any OPF) or shortest first
#   (contrast). Unverified customer cables are assumed to be the thinnest type (4 mm2), verified
#   ones are known to be 16 mm2. The DOE is safe by construction; we report how much export is
#   recovered after k checks.
# Settings: CSIRO 1 kW snapshot and the 12:00 loads of the real day; source 1.03 pu.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_robust.jl")
#   julia> run_robust()
# OUTPUT results/doe_robust.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

const RB_BOUNDS = [0.05, 0.10, 0.20]
# ranking by harm from results/doe_critical_cables.csv (one cable at a time, 1 kW snapshot)
const RB_OPF_ORDER = ["l_3432", "l_3656", "l_1243", "l_2791", "l_54", "l_2000",
                      "l_4294", "l_3254", "l_2249", "l_504", "l_2641", "l_4155"]

# each service segment its own copy of the line code with diagonal R x f[id] (default 1)
function scale_R_each!(net, f::Dict)
    ids  = re_service_ids(net)
    base = net["linecode"][RE_SVC_LC]
    for id in ids
        fi = get(f, id, 1.0)
        fi == 1.0 && continue
        lc = deepcopy(base)
        for key in collect(keys(lc))
            m = match(r"^R_series_(\d+)_(\d+)$", key)
            m === nothing && continue
            m[1] == m[2] && (lc[key] = fi * Float64(lc[key]))
        end
        name = RE_SVC_LC * "_seg_" * id
        net["linecode"][name] = lc
        net["line"][id]["linecode"] = name
    end
    return net
end
mixed_f(b, ids) = Dict(id => (id == "l_3432" ? 1 + b : 1 - b) for id in ids)

# all 22 service segments: diagonal R x f (one shared copy of the line code)
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
    name = RE_SVC_LC * "_x" * string(f)
    net["linecode"][name] = lc
    for id in ids
        net["line"][id]["linecode"] = name
    end
    return net
end

# the 12 service segments that touch a customer bus, longest first
function customer_cables(net)
    lb  = Set(lowercase(String(l["bus"])) for l in values(net["load"]))
    ids = [id for id in re_service_ids(net)
           if lowercase(String(net["line"][id]["bus_from"])) in lb ||
              lowercase(String(net["line"][id]["bus_to"])) in lb]
    @assert length(ids) == 12 "expected 12 customer service cables, found $(length(ids))"
    return sort(ids; by = id -> -Float64(net["line"][id]["length"]))
end

# one envelope valid for several network scenarios (PowerOptLab scenario feature)
function doe_scenarios(nets)
    cps = connection_points(nets[1])
    r = solve_operating_envelope([nets], cps; fairness = :equal, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    return r.envelope[cps[1].id][1] / 1000, string(r.termination_status[1])
end

function run_robust(; pu = RE_PU)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    settings = [("snapshot_1kW", net -> net), ("day_1200", net -> set_loads!(net, pmap, P, Q, 25))]
    rows = String[]
    for (name, prep) in settings
        clean, cb, _, cst = ts_doe(prep(make_net(pu)))
        small, _, _, _    = ts_doe(all_small!(prep(make_net(pu))))
        @printf("\n=== %s, %.3f pu: clean DOE %.3f kW (%s), all 4 mm2 %.3f kW ===\n", name, pu, clean, cb, small)

        println("Part A: hedge against +b resistance on every service cable")
        println("   b      robust kW   cost vs clean   scenario check kW  [status]")
        for b in RB_BOUNDS
            rob, _, _, rst = ts_doe(scale_R_all!(prep(make_net(pu)), 1 + b))
            ids22 = re_service_ids(prep(make_net(pu)))
            chk, cst2 = doe_scenarios([scale_R_all!(prep(make_net(pu)), 1 - b), prep(make_net(pu)),
                                       scale_R_all!(prep(make_net(pu)), 1 + b),
                                       scale_R_each!(prep(make_net(pu)), mixed_f(b, ids22))])
            cost = 100 * (rob / clean - 1)
            @printf("  %4.2f    %7.3f      %+7.1f %%        %7.3f          [%s]\n", b, rob, cost, chk, cst2)
            push!(rows, @sprintf("%s,%.3f,A_hedge,%.2f,,%.6f,%.6f,%.6f,%.3f,%.6f,%s",
                                 name, pu, b, clean, small, rob, cost, chk, cst2))
        end

        net0 = prep(make_net(pu))
        ids  = customer_cables(net0)
        println("Part B: verify customer cables one by one (unverified = 4 mm2)")
        @assert Set(RB_OPF_ORDER) == Set(ids) "OPF ranking does not match the 12 customer cables"
        for (oname, order) in (("longest_first", ids), ("opf_ranked", RB_OPF_ORDER), ("shortest_first", reverse(ids)))
            @printf("  order %s: %s\n", oname, join(order, " "))
            println("   k checked   safe DOE kW   cost vs clean")
            for k in 0:12
                net = prep(make_net(pu))
                for id in order[k+1:end]
                    net["line"][id]["linecode"] = RE_SMALL_LC
                end
                kw, _, _, st = ts_doe(net)
                cost = 100 * (kw / clean - 1)
                @printf("   %2d          %7.3f      %+7.1f %%\n", k, kw, cost)
                push!(rows, @sprintf("%s,%.3f,B_verify_%s,%d,\"%s\",%.6f,%.6f,%.6f,%.3f,,%s",
                                     name, pu, oname, k, join(order[1:k], ";"), clean, small, kw, cost, st))
            end
        end
    end
    open(joinpath(pwd(), "results", "doe_robust.csv"), "w") do io
        println(io, "setting,source_pu,part,param,verified_segments,clean_kW,all_4mm2_kW,safe_DOE_kW,cost_vs_clean_pct,scenario_check_kW,status")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_robust.csv (%d rows, %.0f s)\n", length(rows), time() - t0)
end
