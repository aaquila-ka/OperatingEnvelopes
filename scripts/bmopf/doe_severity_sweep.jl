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

# The service-cable code whose resistance gets scaled, the source voltage (pu = grid voltage
# relative to normal, so 1.03 = 3% high), and the error factors k to test (3.07 = the real 4 mm2 vs
# 16 mm2 ratio)
const SVC_LC   = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const PU_SWEEP = 1.03
const KS       = [1.0, 1.1, 1.25, 1.5, 2.0, 2.5, 3.07]

# scale_service_R!: make the 22 service-cable segments k times more resistive. It copies the cable
# code, multiplies only the 4 diagonal resistances (each conductor's own resistance), saves it under
# a new name and points the 22 segments to it. k = 1 changes nothing
function scale_service_R!(net, k)
    k == 1.0 && return net
    lc = deepcopy(net["linecode"][SVC_LC])
    nd = 0
    for key in collect(keys(lc))
        # Keys look like R_series_2_2; only same-number pairs (the diagonal) are scaled, the
        # off-diagonal (shared) terms are left alone
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
    # Point every 16 mm2 service segment to the new, more resistive cable code
    for l in values(net["line"])
        if l["linecode"] == SVC_LC
            l["linecode"] = newname
            n += 1
        end
    end
    @assert n == 22 "expected 22 service-cable segments, changed $n"
    return net
end

# The street with error factor k, at 1.03 pu
sweep_net(k) = scale_service_R!(make_net(PU_SWEEP), k)

# Same idea as evaluation_copy in doe_dirty_snapshot.jl: remove the 253 V limits and Volt-Watt
# (inverter rule from AS/NZS 4777.2 that cuts export at high voltage) so we can read the voltage
# that results; optionally make the inverters huge with the same Volt-VAr var
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

# Every home exports exactly kw on this street (bound-point reading); returns the highest home
# voltage, or NaN if 5 kVA cannot deliver it
function sweep_v_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(sweep_eval_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return NaN
    v, _ = max_pn(ev.snapshots[1]; only = customer_points(net))
    return v
end

# binding: what stops more export in a solved DOE: "inverter" (an inverter at its 5 kVA), "voltage"
# (a home at 253 V), else "nameplate" (the 5 kW cap)
function binding(snap, net)
    smax = 0.0
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "nameplate"
end

# run_sweep: for each k, the correct DOE (DOE = export limit every home gets), then the Case A and
# Case B numbers. Writes the CSV
function run_sweep()
    doe_k  = Dict{Float64, Float64}()
    bind_k = Dict{Float64, String}()
    # Step 1: the correct equal DOE on a street with error k, in kW, and what limits it
    for k in KS
        net = sweep_net(k)
        cps = connection_points(net)
        r   = doe(net, cps)
        doe_k[k]  = r.envelope[cps[1].id][1] / 1000
        bind_k[k] = isfinite(r.total_capacity[1]) ? binding(r.snapshots[1], net) : "infeasible"
        @printf("k = %4.2f   correct limit %.3f kW   (%s)   [%s]\n", k, doe_k[k], bind_k[k], r.termination_status[1])
    end
    # The records always think k = 1, so they always issue this limit (4.529 kW at 1.03 pu)
    issuedA = doe_k[1.0]
    println("\n   k   correct  | A: issued  over-promise  real V (customer)      | B: issued  lost")
    rows = String[]
    # Step 2: for each k, test that issued limit on the TRUE street
    for k in KS
        net = sweep_net(k)
        cps = connection_points(net)
        # Give every home that limit on the TRUE street and read the highest home voltage
        v   = sweep_v_at_export(net, cps, issuedA)
        tag = "delivered"
        # If even a 5 kVA inverter cannot deliver it (Volt-VAr uses too much of the inverter)...
        if !isfinite(v)
            # ...pretend the inverter is bigger, just to see what the voltage WOULD be
            v   = sweep_v_at_export(net, cps, issuedA; relax_smax = true)
            tag = "undeliverable (5 kVA); counterfactual"
        end
        # How much too generous the records' limit is, in %: 100 x (issued / correct - 1)
        overA = 100 * (issuedA / doe_k[k] - 1)
        # Case B: the records say k but the truth is k = 1, so they issue DOE(k) and lose this % of
        # the correct DOE(1)
        lossB = 100 * (doe_k[k] / doe_k[1.0] - 1)
        @printf(" %4.2f  %6.3f  |   %6.3f    %+7.1f %%    %7.2f V %-38s | %6.3f  %+7.1f %%\n",
                k, doe_k[k], issuedA, overA, v, tag, doe_k[k], lossB)
        # One CSV row per k
        push!(rows, @sprintf("%.2f,%.6f,%s,%.6f,%.3f,%.4f,%s,%.6f,%.3f",
                             k, doe_k[k], bind_k[k], issuedA, overA, v, tag, doe_k[k], lossB))
    end
    # Write all rows to the CSV
    open(joinpath(pwd(), "results", "doe_severity_sweep.csv"), "w") do io
        println(io, "k,correct_kW,correct_binding,A_issued_kW,A_overpromise_pct,A_true_street_V,A_note,B_issued_kW,B_lost_pct")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_severity_sweep.csv")
end

# Runs as soon as the file is included
run_sweep()