# scripts/bmopf/lv9/lv9_thermal.jl
#
# STEP: add cable current (thermal) limits to LV9 and redo the core comparison.
# Ratings (4-core Cu XLPE 0.6/1 kV, 90 C conductor, Prysmian 4C-XLPE circular datasheet,
# 25 C ground, 1.2 K.m/W, 0.5 m): 16 mm2 = 110 A buried direct / 81 A in duct;
# 120 mm2 = 345 A buried / 275 A in duct. Applied per conductor (phases and neutral).
# Aluminium mains (240 mm2, 400 mm2 triplex) and the "generic/lv" code have no limit here
# (rating not sourced yet). The 4 mm2 cable used as the "true" wrong cable gets no limit
# either (not in the datasheet), so the correct DOE on a 4 mm2 street is slightly optimistic.
# Realised readings remove ALL limits (voltage and current): real cables do not curtail;
# instead we report the highest current in the shared 16 mm2 cables at the issued DOE.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/lv9/lv9_thermal.jl")
#   julia> run_lv9_thermal()            # 0.94 and 1.00 pu, 110 A and 81 A   (~10 min)
# OUTPUT results/lv9/lv9_thermal.csv

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_core.jl"))

const LC_120CU = "uglv_120cu_xlpe/nyl/pvc_ug_4w_bundled"

function add_thermal!(net; i16 = 110.0, i120 = 345.0)
    net["linecode"][SVC_LC]["i_max"] = fill(i16, 4)
    haskey(net["linecode"], LC_120CU) && (net["linecode"][LC_120CU]["i_max"] = fill(i120, 4))
    return net
end

function strip_limits!(net)
    for b in values(net["bus"]), k in ("vpn_min", "vpn_max", "vpg_min", "vpg_max", "v_min", "v_max", "vm_min", "vm_max")
        delete!(b, k)
    end
    for lc in values(net["linecode"])
        lc isa Dict && delete!(lc, "i_max")
    end
    for l in values(net["line"])
        delete!(l, "i_max")
    end
    return net
end

function max_current(snap, ids)
    best = 0.0; where = ""
    for id in ids
        lr = get(get(snap, "line", Dict()), id, nothing)
        lr === nothing && continue
        for (t, c) in lr
            (c isa Dict && t != "n") || continue
            i = max(get(c, "cm_fr", 0.0), get(c, "cm_to", 0.0))
            i > best && (best = i; where = id)
        end
    end
    return best, where
end

# equal DOE + binding including thermal
function eq_doe_thermal(net, i16)
    cps = connection_points(net)
    r = doe(net, cps)
    ok = isfinite(r.total_capacity[1])
    ok || return NaN, "infeasible", NaN, ""
    kw = r.envelope[cps[1].id][1] / 1000
    imax, where = max_current(r.snapshots[1], service_ids(net))
    b = imax >= i16 - 0.05 ? "thermal" : binding(r.snapshots[1], net)
    return kw, b, imax, where
end

# realised: everyone may export up to cap; no voltage or current limits; report V and current
function realised_thermal(net, cap_kW, shared)
    ev = strip_limits!(deepcopy(net))
    cps = connection_points(ev; export_max = 1000.0 * cap_kW)
    r = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                 security = :bound_point, solver_options = OPTS)
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, imax = NaN, where = "")
    snap = r.snapshots[1]
    v, _ = max_pn(snap; only = customer_points(net))
    nover = count(pt -> max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005, collect(customer_points(net)))
    imax, where = max_current(snap, shared)
    return (v = v, n_over = nover, imax = imax, where = where)
end

function run_lv9_thermal(; pus = [0.94, 1.00], i16s = [110.0, 81.0])
    t0 = time()
    drops, up, _, _, _, _, _, _ = segment_sets(make_net(1.00))
    rows = String[]
    println("\n  pu   I16 A | clean kW no-thermal | clean kW thermal (bind, I max) | case         correct kW  gap kW | realised V  >253  I shared max")
    for pu in pus
        nothermal, _, _, _, _ = eq_doe(make_net(pu))
        for i16 in i16s
            clean, cb, ci, cw = eq_doe_thermal(add_thermal!(make_net(pu); i16 = i16), i16)
            for (cname, ids) in (("drops_123", drops), ("upstream_12", up))
                truth = set_small!(add_thermal!(make_net(pu); i16 = i16), ids)
                a, ab, _, _ = eq_doe_thermal(truth, i16)
                rv = realised_thermal(truth, clean, up)
                @printf(" %4.2f  %5.0f |      %6.3f         |   %6.3f (%-8s %5.1f A %-7s) | %-11s  %7.3f   %+6.3f |  %7.2f    %3d   %6.1f A (%s)\n",
                        pu, i16, nothermal, clean, cb, ci, cw, cname, a, clean - a, rv.v, rv.n_over, rv.imax, rv.where)
                push!(rows, @sprintf("%.3f,%.1f,%.6f,%.6f,%s,%.3f,%s,%s,%.6f,%s,%.6f,%.4f,%d,%.3f,%s",
                                     pu, i16, nothermal, clean, cb, ci, cw, cname, a, ab, clean - a,
                                     rv.v, rv.n_over, rv.imax, rv.where))
            end
        end
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_thermal.csv"), "w") do io
        println(io, "source_pu,i16_rating_A,clean_kW_no_thermal,clean_kW_thermal,clean_binding,clean_max_16mm2_current_A,clean_max_current_segment,case,correct_kW,correct_binding,gap_kW,realised_V,n_customers_over_253,realised_max_shared_current_A,realised_max_current_segment")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/lv9_thermal.csv (%.0f s)\n", time() - t0)
end
