# scripts/bmopf/doe_dirty_snapshot.jl
#
# PURPOSE (Aims 4/5, first snapshot)
#   What happens when the operator's cable records are WRONG?
#   Service cables: records say 16 mm2 copper (ugsc_16cu, 22 segments);
#   wrong alternative: 4 mm2 copper (uglv_4cu), resistance about 3.07 times higher.
#
#   CASE A (dangerous): cable in the ground is really 4 mm2, records say 16 mm2.
#       Operator's DOE is too generous -> what voltage does the real street reach?
#   CASE B (wasteful):  cable in the ground is really 16 mm2, records say 4 mm2.
#       Operator's DOE is too cautious -> how much export is lost?
#
#   truth = DOE on the TRUE network (answer key)
#   dirty = DOE on the operator's WRONG model (what would be issued)
#   The dirty DOE is then applied to the TRUE network with limits and Volt-Watt
#   removed (so P = issued limit exactly) and the real voltage is read.
#   If a DOE has no solution, the true network is checked at 0 kW and 1 kW
#   export per house to see whether the limit is violated even at low export.
#
# Source 1.03 pu (voltage-limited case). Equal allocation. 207-253 V phase-to-neutral.
# RUN    julia> include("scripts/bmopf/doe_dirty_snapshot.jl")
# OUTPUT results/doe_dirty_snapshot.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_clean_snapshot.jl"))   # helpers (also reruns clean)

const SERVICE_LC = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SMALL_LC   = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const PU_DIRTY   = 1.03

function build_net(; swapped::Bool)
    net = load_lv3()
    scale_source!(net, PU_DIRTY)
    add_pn_limits!(net)
    if swapped
        @assert haskey(net["linecode"], SMALL_LC) "linecode $SMALL_LC not found"
        n = 0
        for l in values(net["line"])
            if l["linecode"] == SERVICE_LC
                l["linecode"] = SMALL_LC
                n += 1
            end
        end
        @assert n == 22 "expected 22 service-cable segments, swapped $n"
    end
    return net
end

# Copy with the 207-253 V limits and Volt-Watt removed, so a fixed export equal
# to the issued limit can be applied and the resulting voltage read.
function evaluation_copy(net)
    n = deepcopy(net)
    for b in values(n["bus"])
        delete!(b, "vpn_min"); delete!(b, "vpn_max")
    end
    for p in values(n["control_profile"])
        delete!(p, "volt_watt")
    end
    return n
end

doe(net, cps) = solve_operating_envelope(net, cps; fairness = :equal, direction = :export,
                                         security = :bound_point, solver_options = OPTS)

# Voltage on a network when every house exports `kw` (limits removed).
function voltage_at_export(net, cps, kw)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(evaluation_copy(net), cps, caps; solver_options = OPTS)
    ev.feasible[1] || return (NaN, "power flow not solved ($(ev.termination_status[1]))")
        return max_pn(ev.snapshots[1], net; only = customer_points(net))
end

function explain_failure(name, r, net, cps)
    println("  !! $name DOE has no solution ($(r.termination_status[1])). Diagnostics:")
    for (k, v) in r.diagnostics[1]
        v isa Union{Number, String, Bool, Symbol} && println("       ", k, " = ", v)
    end
    for kw in (0.0, 1.0)
        v, w = voltage_at_export(net, cps, kw)
        @printf("     this network with %.1f kW export per house: highest voltage %.2f V at %s\n", kw, v, w)
    end
end

function run_case(label, true_net, model_net)
    cps   = connection_points(true_net)
    truth = doe(true_net, cps)
    dirty = doe(model_net, cps)
    t1 = cps[1].id
    println("\n================ $label ================")
    println("status: truth $(truth.termination_status[1]), dirty $(dirty.termination_status[1])")
    isfinite(truth.total_capacity[1]) || explain_failure("truth (true network)", truth, true_net, cps)
    isfinite(dirty.total_capacity[1]) || explain_failure("dirty (wrong-records model)", dirty, model_net, cps)
    @printf("correct limit (answer key):  %.3f kW per house   total %.2f kW\n",
            truth.envelope[t1][1] / 1000, truth.total_capacity[1] / 1000)
    @printf("limit from wrong records:    %.3f kW per house   total %.2f kW\n",
            dirty.envelope[t1][1] / 1000, dirty.total_capacity[1] / 1000)
    vreal, where = NaN, "not checked"
    if isfinite(dirty.total_capacity[1])
        vreal, where = voltage_at_export(true_net, cps, dirty.envelope[t1][1] / 1000)
        if isfinite(truth.total_capacity[1])
            @printf("difference:                  %+.3f kW per house  (%+.1f %%)\n",
                    (dirty.envelope[t1][1] - truth.envelope[t1][1]) / 1000,
                    100 * (dirty.envelope[t1][1] / truth.envelope[t1][1] - 1))
        end
        @printf("real street voltage if houses export the wrong-records limit: %.2f V at %s  (%+.2f V vs 253 V)\n",
                vreal, where, vreal - V_MAX_PN)
    end
    return @sprintf("%s,%.6f,%.6f,%.4f,%s", label, truth.envelope[t1][1] / 1000,
                    dirty.envelope[t1][1] / 1000, vreal, where)
end

function run_dirty_snapshot()
    base    = build_net(swapped = false)   # 16 mm2 services
    swapped = build_net(swapped = true)    # 4 mm2 services
    rows = String[]
    push!(rows, run_case("CASE A: truth 4 mm2, records say 16 mm2", swapped, base))
    push!(rows, run_case("CASE B: truth 16 mm2, records say 4 mm2", base, swapped))
    open(joinpath(pwd(), "results", "doe_dirty_snapshot.csv"), "w") do io
        println(io, "case,correct_limit_kW,wrong_records_limit_kW,real_max_vpn_V,where")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_dirty_snapshot.csv")
end

run_dirty_snapshot()