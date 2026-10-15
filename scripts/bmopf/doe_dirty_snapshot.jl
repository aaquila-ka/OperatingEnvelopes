# =============================================================================
# doe_dirty_snapshot.jl: wrong cable records, Case A and Case B, 1 kW snapshot (bound-point)
#
# What it does (plain English):
#   Source 1.03 pu, original CSIRO loads, equal allocation, 207-253 V phase-to-neutral
#   at customer connections. Service cables: records say 16 mm2 Cu (ugsc_16cu, 22
#   segments) vs 4 mm2 Cu (uglv_4cu, resistance about 3.07x).
#     CASE A (dangerous): truth 4 mm2, records 16 mm2 -> issued DOE too generous.
#     CASE B (wasteful):  truth 16 mm2, records 4 mm2 -> issued DOE too cautious.
#   The issued (wrong-records) DOE is then applied to the TRUE network with voltage
#   limits and Volt-Watt removed (P fixed exactly at the issued limit; verify pins P by
#   equality, checked in PowerOptLab 953e45c). If that is impossible within the 5 kVA
#   inverter rating under Volt-VAr, it is reported as "undeliverable", and a
#   counterfactual voltage is computed with the inverter rating relaxed but the SAME
#   Volt-VAr reactive power in var. This is the older "bound-point" reading; the
#   realised reading (Volt-Watt on) for Case A is in doe_critical_cables.csv,
#   doe_record_errors.csv and doe_source_sweep.csv (254.60 V).
# Inputs:   includes doe_common.jl (which loads load_lv3.jl and the LV3 .dss files)
# Outputs:  results/doe_dirty_snapshot.csv (case, correct_limit_kW,
#           issued_limit_kW, true_street_max_vpn_V = bound-point reading, where, note);
#           prints per-house tables
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/doe_dirty_snapshot.jl")   (calls run_dirty_snapshot() itself)
# Used for: REPRODUCE.md step 4; Case A correct 2.734 kW, issued 4.529 kW (+65.6 %),
#           bound-point 255.12 V (counterfactual); Case B -39.6 % (mirror of Case A)
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))

# The two cable types in the dataset: 16 mm2 copper service cable (what the records say) and 4 mm2
# copper (about 3.07 x the resistance)
const SERVICE_LC = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const SMALL_LC   = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
# Source at 1.03 pu (pu = grid voltage relative to normal, so 1.03 = 3% high)
const PU_DIRTY   = 1.03

# make_dirty_net: build LV3 at 1.03 pu. swapped = false: all service cables 16 mm2, as in the files.
# swapped = true: all 22 service-cable segments changed to 4 mm2
function make_dirty_net(; swapped::Bool)
    net = make_net(PU_DIRTY)
    if swapped
        @assert haskey(net["linecode"], SMALL_LC) "linecode $SMALL_LC not found"
        n = 0
        # Find every line using the 16 mm2 service-cable code, switch it to the 4 mm2 code, and
        # count them
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

# evaluation_copy: a copy of the street used only to SEE what voltage an issued limit causes. It
# removes the 253 V limits (so the solver cannot hide a breach) and switches Volt-Watt off (so
# export is not cut back). Volt-VAr and the 5 kVA rating stay.
# Volt-VAr / Volt-Watt = inverter rules from AS/NZS 4777.2 (Volt-VAr soaks up reactive power at high
# voltage, Volt-Watt cuts real export at very high voltage)
function evaluation_copy(net; relax_smax = false, s_big = 1.0e5)
    n = deepcopy(net)
    for b in values(n["bus"])
        delete!(b, "vpn_min"); delete!(b, "vpn_max")
    end
    for p in values(n["control_profile"])
        delete!(p, "volt_watt")
    end
    # Optional: make the inverters huge (100 kVA) to see the voltage when 5 kVA cannot deliver the
    # limit. The Volt-VAr fraction is scaled by 5000 / s_big so the reactive power in var stays the
    # same as a 5 kVA inverter's
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

# voltage_at_export: every home exports EXACTLY kw on the street `net` (bound-point reading:
# everyone at the limit, Volt-Watt off). Returns (highest home voltage, where), or (NaN, solver
# status) if that export is impossible
function voltage_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    # verify_operating_envelope (PowerOptLab) fixes each home's export at its cap and solves the
    # physics
    ev = verify_operating_envelope(evaluation_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return (NaN, string(ev.termination_status[1]))
    return max_pn(ev.snapshots[1]; only = customer_points(net))
end

# run_case: one case. true_net = the real street; model_net = the street as the records describe it.
# Returns one CSV row
function run_case(label, true_net, model_net)
    cps   = connection_points(true_net)
    # Answer key: the correct DOE, solved on the TRUE street
    truth = doe(true_net, cps)
    # Issued DOE: what the utility would give out, solved on the RECORDS street
    dirty = doe(model_net, cps)
    # Equal DOE, so every home has the same limit: read it from the first home
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
    # Both limits in kW (envelope is in W)
    kt = truth.envelope[t1][1] / 1000
    kd = dirty.envelope[t1][1] / 1000
    # Gap in % = 100 x (issued / correct - 1); positive = too generous (REPRODUCE.md: Case A correct
    # 2.734 kW, issued 4.529 kW, +65.6 %)
    @printf("correct %.3f kW | issued %.3f kW | difference %+.3f kW (%+.1f %%)\n", kt, kd, kd - kt, 100 * (kd / kt - 1))
    v, w, note = NaN, "", "not checked"
    # Now give every home the issued limit on the TRUE street and read the highest home voltage;
    # above 253 V means the issued limit is unsafe
    if isfinite(kd)
        v, w = voltage_at_export(true_net, cps, kd)
        if isfinite(v)
            note = "delivered"
            @printf("real street, houses export the issued %.3f kW: %.2f V at %s (%+.2f V vs 253 V)\n", kd, v, w, v - V_MAX_PN)
        else
            # If the 5 kVA inverter cannot deliver the issued export (Volt-VAr uses part of the
            # inverter)...
            note = "undeliverable within 5 kVA under Volt-VAr"
            println("real street: issued export is UNDELIVERABLE within the 5 kVA rating under Volt-VAr ($w)")
            # ...pretend the inverter is bigger (same Volt-VAr var), just to see what the voltage
            # WOULD be (REPRODUCE.md: 255.12 V for Case A)
            v, w = voltage_at_export(true_net, cps, kd; relax_smax = true)
            @printf("  counterfactual (rating relaxed, same Volt-VAr Q): %.2f V at %s (%+.2f V vs 253 V)\n", v, w, v - V_MAX_PN)
        end
    end
    # CSV row: case, correct kW, issued kW, voltage, where, note
    return @sprintf("%s,%.6f,%.6f,%.4f,%s,%s", label, kt, kd, v, w, note)
end

# run_dirty_snapshot: build the 16 mm2 street and the 4 mm2 street, then run both cases
function run_dirty_snapshot()
    base    = make_dirty_net(swapped = false)
    swapped = make_dirty_net(swapped = true)
    rows = String[]
    # Case A (dangerous): truth is 4 mm2 but the records say 16 mm2
    push!(rows, run_case("CASE A: truth 4 mm2, records say 16 mm2", swapped, base))
    # Case B (wasteful): truth is 16 mm2 but the records say 4 mm2
    push!(rows, run_case("CASE B: truth 16 mm2, records say 4 mm2", base, swapped))
    # Write both rows to the CSV
    open(joinpath(pwd(), "results", "doe_dirty_snapshot.csv"), "w") do io
        println(io, "case,correct_limit_kW,issued_limit_kW,true_street_max_vpn_V,where,note")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_dirty_snapshot.csv")
end

# Runs as soon as the file is included
run_dirty_snapshot()