# scripts/bmopf/doe_dirty_snapshot.jl
#
# Wrong cable records experiment (one snapshot), source 1.03 pu, original CSIRO loads,
# equal allocation, 207-253 V phase-to-neutral at customer connections.
#   Service cables: records say 16 mm2 Cu (ugsc_16cu, 22 segments) vs 4 mm2 Cu (uglv_4cu, R about 3.07x).
#   CASE A (dangerous): truth 4 mm2, records 16 mm2 -> issued DOE too generous.
#   CASE B (wasteful):  truth 16 mm2, records 4 mm2 -> issued DOE too cautious.
# The issued (wrong-records) DOE is applied to the TRUE network with limits and Volt-Watt
# removed (P fixed exactly at the issued limit; verify pins P by equality, checked in
# PowerOptLab 953e45c). If that is impossible within the 5 kVA inverter rating under
# Volt-VAr, it is reported as "undeliverable", and a counterfactual voltage is computed
# with the inverter rating relaxed but the SAME Volt-VAr reactive power in var.
# RUN    julia> include("scripts/bmopf/doe_dirty_snapshot.jl")
# OUTPUT results/doe_dirty_snapshot.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))

const SERVICE_LC = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SMALL_LC   = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const PU_DIRTY   = 1.03

function make_dirty_net(; swapped::Bool)
    net = make_net(PU_DIRTY)
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

function evaluation_copy(net; relax_smax = false, s_big = 1.0e5)
    n = deepcopy(net)
    for b in values(n["bus"])
        delete!(b, "vpn_min"); delete!(b, "vpn_max")
    end
    for p in values(n["control_profile"])
        delete!(p, "volt_watt")
    end
    if relax_smax
        @assert all(Float64.(i["s_max"]) == [5000.0] for i in values(n["ibr"])) "unexpected s_max"
        for i in values(n["ibr"])
            i["s_max"] = [s_big]
        end
        vv = n["control_profile"]["invall"]["volt_var"]
        vv["q_limits"] = Float64.(vv["q_limits"]) .* (5000.0 / s_big)   # same Q in var (base = s_max)
    end
    return n
end

function voltage_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(evaluation_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return (NaN, string(ev.termination_status[1]))
    return max_pn(ev.snapshots[1]; only = customer_points(net))
end

function run_case(label, true_net, model_net)
    cps   = connection_points(true_net)
    truth = doe(true_net, cps)
    dirty = doe(model_net, cps)
    t1 = cps[1].id
    println("\n================ $label ================")
    println("solver: truth $(truth.termination_status[1]), wrong-records $(dirty.termination_status[1])")
    if isfinite(truth.total_capacity[1])
        println("ANSWER KEY (DOE on the true network):")
        house_report(truth.snapshots[1], true_net, truth)
    end
    if isfinite(dirty.total_capacity[1])
        println("ISSUED (DOE on the wrong-records model):")
        house_report(dirty.snapshots[1], model_net, dirty)
    end
    kt = truth.envelope[t1][1] / 1000
    kd = dirty.envelope[t1][1] / 1000
    @printf("correct %.3f kW | issued %.3f kW | difference %+.3f kW (%+.1f %%)\n", kt, kd, kd - kt, 100 * (kd / kt - 1))
    v, w, note = NaN, "", "not checked"
    if isfinite(kd)
        v, w = voltage_at_export(true_net, cps, kd)
        if isfinite(v)
            note = "delivered"
            @printf("real street, houses export the issued %.3f kW: %.2f V at %s (%+.2f V vs 253 V)\n", kd, v, w, v - V_MAX_PN)
        else
            note = "undeliverable within 5 kVA under Volt-VAr"
            println("real street: issued export is UNDELIVERABLE within the 5 kVA rating under Volt-VAr ($w)")
            v, w = voltage_at_export(true_net, cps, kd; relax_smax = true)
            @printf("  counterfactual (rating relaxed, same Volt-VAr Q): %.2f V at %s (%+.2f V vs 253 V)\n", v, w, v - V_MAX_PN)
        end
    end
    return @sprintf("%s,%.6f,%.6f,%.4f,%s,%s", label, kt, kd, v, w, note)
end

function run_dirty_snapshot()
    base    = make_dirty_net(swapped = false)
    swapped = make_dirty_net(swapped = true)
    rows = String[]
    push!(rows, run_case("CASE A: truth 4 mm2, records say 16 mm2", swapped, base))
    push!(rows, run_case("CASE B: truth 16 mm2, records say 4 mm2", base, swapped))
    open(joinpath(pwd(), "results", "doe_dirty_snapshot.csv"), "w") do io
        println(io, "case,correct_limit_kW,issued_limit_kW,true_street_max_vpn_V,where,note")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_dirty_snapshot.csv")
end

run_dirty_snapshot()