# =============================================================================
# doe_severity_sweep.jl: how big must the cable error be? Resistance x k, k = 1 to 3.07
#
# What it does (plain English):
#   Severity sweep ("dirty, then dirtier"): service-cable resistance error factor k.
#   The TRUE street has service-cable conductor resistance x k (diagonal R only; the
#   off-diagonal 0.0493 ohm/km Carson earth-return term is unchanged). Records always
#   say k = 1 (Case A) or the reverse (Case B).
#     DOE(k)        = correct equal export limit on a street with error k
#     Case A (k>1)  : records k=1, truth k  -> issued DOE(1), correct DOE(k): over-promise
#     Case B (k>1)  : records k, truth k=1  -> issued DOE(k), correct DOE(1): lost export
#   Source 1.03 pu, original CSIRO loads, 207-253 V phase-to-neutral at customer
#   connections, equal allocation. The voltage column is the older bound-point reading
#   (everyone exports the issued DOE, Volt-Watt off; "counterfactual" = 5 kVA rating relaxed).
#   Binding label "nameplate" here = the 5 kW export_max (doe_record_errors.jl calls it "other").
# Inputs:   includes doe_common.jl (which loads load_lv3.jl and the LV3 .dss files)
# Outputs:  results/doe_severity_sweep.csv (k, correct_kW, correct_binding, A_issued_kW,
#           A_overpromise_pct, A_true_street_V, A_note, B_issued_kW, B_lost_pct); prints a table
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/doe_severity_sweep.jl")   (calls run_sweep() itself)
# Used for: REPRODUCE.md step 5 and section 6 item 7 (k = 3.07: 2.739 kW vs 2.734 kW
#           with the full line-code swap)
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))

const SVC_LC   = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const PU_SWEEP = 1.03
const KS       = [1.0, 1.1, 1.25, 1.5, 2.0, 2.5, 3.07]

function scale_service_R!(net, k)
    k == 1.0 && return net
    lc = deepcopy(net["linecode"][SVC_LC])
    nd = 0
    for key in collect(keys(lc))
        m = match(r"^R_series_(\d+)_(\d+)$", key)
        m === nothing && continue
        if m[1] == m[2]
            lc[key] = k * Float64(lc[key])
            nd += 1
        end
    end
    @assert nd == 4 "expected 4 diagonal R entries, found $nd"
    newname = SVC_LC * "_Rx" * string(k)
    net["linecode"][newname] = lc
    n = 0
    for l in values(net["line"])
        if l["linecode"] == SVC_LC
            l["linecode"] = newname
            n += 1
        end
    end
    @assert n == 22 "expected 22 service-cable segments, changed $n"
    return net
end

sweep_net(k) = scale_service_R!(make_net(PU_SWEEP), k)

function sweep_eval_copy(net; relax_smax = false, s_big = 1.0e5)
    n = deepcopy(net)
    for b in values(n["bus"])
        delete!(b, "vpn_min"); delete!(b, "vpn_max")
    end
    for p in values(n["control_profile"])
        delete!(p, "volt_watt")
    end
    if relax_smax
        for i in values(n["ibr"])
            i["s_max"] = [s_big]
        end
        vv = n["control_profile"]["invall"]["volt_var"]
        vv["q_limits"] = Float64.(vv["q_limits"]) .* (5000.0 / s_big)
    end
    return n
end

function sweep_v_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(sweep_eval_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return NaN
    v, _ = max_pn(ev.snapshots[1]; only = customer_points(net))
    return v
end

function binding(snap, net)
    smax = 0.0
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "nameplate"
end

function run_sweep()
    doe_k  = Dict{Float64, Float64}()
    bind_k = Dict{Float64, String}()
    for k in KS
        net = sweep_net(k)
        cps = connection_points(net)
        r   = doe(net, cps)
        doe_k[k]  = r.envelope[cps[1].id][1] / 1000
        bind_k[k] = isfinite(r.total_capacity[1]) ? binding(r.snapshots[1], net) : "infeasible"
        @printf("k = %4.2f   correct limit %.3f kW   (%s)   [%s]\n", k, doe_k[k], bind_k[k], r.termination_status[1])
    end
    issuedA = doe_k[1.0]
    println("\n   k   correct  | A: issued  over-promise  real V (customer)      | B: issued  lost")
    rows = String[]
    for k in KS
        net = sweep_net(k)
        cps = connection_points(net)
        v   = sweep_v_at_export(net, cps, issuedA)
        tag = "delivered"
        if !isfinite(v)
            v   = sweep_v_at_export(net, cps, issuedA; relax_smax = true)
            tag = "undeliverable (5 kVA); counterfactual"
        end
        overA = 100 * (issuedA / doe_k[k] - 1)
        lossB = 100 * (doe_k[k] / doe_k[1.0] - 1)
        @printf(" %4.2f  %6.3f  |   %6.3f    %+7.1f %%    %7.2f V %-38s | %6.3f  %+7.1f %%\n",
                k, doe_k[k], issuedA, overA, v, tag, doe_k[k], lossB)
        push!(rows, @sprintf("%.2f,%.6f,%s,%.6f,%.3f,%.4f,%s,%.6f,%.3f",
                             k, doe_k[k], bind_k[k], issuedA, overA, v, tag, doe_k[k], lossB))
    end
    open(joinpath(pwd(), "results", "doe_severity_sweep.csv"), "w") do io
        println(io, "k,correct_kW,correct_binding,A_issued_kW,A_overpromise_pct,A_true_street_V,A_note,B_issued_kW,B_lost_pct")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_severity_sweep.csv")
end

run_sweep()