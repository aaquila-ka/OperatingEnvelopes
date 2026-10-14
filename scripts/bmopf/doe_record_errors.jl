# =============================================================================
# doe_record_errors.jl: realistic cable-record errors, many seeded random draws
#
# What it does (plain English):
#   The RECORDS always show the catalogue: every service cable = 16 mm2 Cu.
#   The TRUE street differs from the records in one of two ways:
#     scatter   : each of the 22 service segments gets its OWN resistance factor
#                 f = 1 + sigma * randn  (diagonal R only), f >= 0.5; sigma = 0.05, 0.10, 0.20
#     wrongtype : m randomly chosen service segments are really 4 mm2 Cu; m = 2, 5, 11 of 22
#                 (chosen from all 22, including the 10 dead-end stubs with no customer,
#                 which carry no current; that is why some 2-cable draws give 0 %)
#   Issued DOE  = DOE on the records (same for every draw)
#   Correct DOE = DOE on that draw's true street (the answer key for that draw)
#   gap_kW = issued - correct; overpromise_pct = (issued / correct - 1) x 100
#   Two ways of reading what the issued DOE does on the true street:
#     bound-point (old): every customer exports exactly the issued DOE, Volt-Watt switched off
#                        (counterfactual if the 5 kVA rating cannot deliver it)
#     realised    (new): every customer MAY export up to the cap; inverters keep Volt-VAr,
#                        Volt-Watt and the 5 kVA rating; no voltage limit is imposed.
#                        -> realised max voltage, customers above 253.005 V, total curtailment
#   Every draw has its own random generator: seed = 20261013 + 100000 x scenario number
#   (1 scatter, 2 wrongtype) + 1000 x level number (1-3) + draw number, so a draw does not
#   depend on n_draws. All 22 scatter factors per draw are saved; another operating point
#   (other loads / source voltage) can be passed through `prep!` and `pu`.
# Inputs:   includes doe_common.jl (-> load_lv3.jl and the LV3 .dss files)
# Outputs:  results/doe_record_errors.csv (or the name given in `out`); prints a table
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   include("scripts/bmopf/doe_record_errors.jl")   then   run_record_errors(n_draws = 20)
#   (the default n_draws = 2 is a quick test and would overwrite the 120-row file with 12 rows)
# Used for: REPRODUCE.md step 7 (1 kW snapshot, 1.03 pu); step 10 reuses it at the
#           12:00 loads through run_record_errors_at(25; n_draws = 20) in doe_timeseries.jl
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt; Julia MersenneTwister random numbers
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))
using Random

const RE_SVC_LC   = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const RE_SMALL_LC = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const RE_PU       = 1.03
const RE_SEED     = 20261013
const RE_SIGMAS   = [0.05, 0.10, 0.20]
const RE_MS       = [2, 5, 11]
const RE_BUS_LIMIT_KEYS = ("vpn_min", "vpn_max", "vpg_min", "vpg_max", "v_min", "v_max", "vm_min", "vm_max")

# ---- the 22 service-cable segments, always in the same (sorted) order
function re_service_ids(net)
    ids = sort([String(id) for (id, l) in net["line"] if l["linecode"] == RE_SVC_LC])
    @assert length(ids) == 22 "expected 22 service segments, found $(length(ids))"
    return ids
end

# ---- scatter: every segment gets its own copy of the line code with R x f
function re_apply_scatter!(net, sigma, rng)
    ids  = re_service_ids(net)
    base = net["linecode"][RE_SVC_LC]
    fs   = Float64[]
    for id in ids
        f  = max(0.5, 1 + sigma * randn(rng))
        lc = deepcopy(base)
        nd = 0
        for key in collect(keys(lc))
            m = match(r"^R_series_(\d+)_(\d+)$", key)
            m === nothing && continue
            if m[1] == m[2]
                lc[key] = f * Float64(lc[key])
                nd += 1
            end
        end
        @assert nd == 4 "expected 4 diagonal R entries, found $nd"
        name = RE_SVC_LC * "_seg_" * id
        net["linecode"][name] = lc
        net["line"][id]["linecode"] = name
        push!(fs, f)
    end
    return fs
end

# ---- wrong type: m random segments are really 4 mm2
function re_apply_wrongtype!(net, m, rng)
    @assert haskey(net["linecode"], RE_SMALL_LC) "4 mm2 line code not found in network"
    ids    = re_service_ids(net)
    chosen = ids[sort(randperm(rng, length(ids))[1:m])]
    for id in chosen
        net["line"][id]["linecode"] = RE_SMALL_LC
    end
    return chosen
end

# ---- OLD bound-point reading (same rules as doe_severity_sweep.jl)
function re_eval_copy(net; relax_smax = false, s_big = 1.0e5)
    n = deepcopy(net)
    for b in values(n["bus"]), k in RE_BUS_LIMIT_KEYS
        delete!(b, k)
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

function re_v_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(re_eval_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return NaN
    v, _ = max_pn(ev.snapshots[1]; only = customer_points(net))
    return v
end

function re_street(net, kw)
    cps = connection_points(net)
    v = re_v_at_export(net, cps, kw)
    isfinite(v) && return v, "delivered"
    v = re_v_at_export(net, cps, kw; relax_smax = true)
    return v, "undeliverable (5 kVA); counterfactual"
end

# ---- NEW realised reading: customers may export up to cap_kW; inverters keep
#      Volt-VAr, Volt-Watt and 5 kVA; no voltage limit imposed (only physics + inverter laws)
function re_realised(net, cap_kW)
    if !(cap_kW > 1e-6)
        return (v = NaN, n_over = 0, curtail_kW = 0.0, status = "no export")
    end
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in RE_BUS_LIMIT_KEYS
        delete!(b, k)
    end
    cps = connection_points(ev; export_max = 1000.0 * cap_kW)
    r   = solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                   security = :bound_point, solver_options = OPTS)
    st  = string(r.termination_status[1])
    isfinite(r.total_capacity[1]) || return (v = NaN, n_over = -1, curtail_kW = NaN, status = st)
    snap = r.snapshots[1]
    v, _ = max_pn(snap; only = customer_points(net))
    nover = count(pt -> max_pn(snap; only = [pt])[1] > V_MAX_PN + 0.005, collect(customer_points(net)))
    curtail = sum(cap_kW - r.envelope[cp.id][1] / 1000 for cp in cps)
    return (v = v, n_over = nover, curtail_kW = curtail, status = st)
end

function re_binding(snap, net)
    smax = 0.0
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "other"
end

function re_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    kw  = r.envelope[cps[1].id][1] / 1000
    b   = isfinite(r.total_capacity[1]) ? re_binding(r.snapshots[1], net) : "infeasible"
    return kw, b, string(r.termination_status[1])
end

# ---- main
function run_record_errors(; n_draws = 2, pu = RE_PU, prep! = identity,
                           setting = "snapshot_1kW", out = "doe_record_errors.csv")
    t0 = time()
    issued, ib, ist = re_doe(prep!(make_net(pu)))
    @printf("[%s, %.3f pu] records (all 16 mm2): issued DOE %.3f kW (%s) [%s]\n\n", setting, pu, issued, ib, ist)
    println("scenario   level  draw   correct kW  binding    gap kW  over-promise  bound V   realised V  >253V  curtail kW")
    rows = String[]
    for (si, (scen, levels)) in enumerate((("scatter", RE_SIGMAS), ("wrongtype", RE_MS)))
        for (li, lev) in enumerate(levels), d in 1:n_draws
            seed  = RE_SEED + 100_000 * si + 1_000 * li + d
            rng   = MersenneTwister(seed)
            truth = prep!(make_net(pu))
            meanf = ""; maxf = ""; factors = ""; changed = ""
            if scen == "scatter"
                fs      = re_apply_scatter!(truth, lev, rng)
                meanf   = @sprintf("%.4f", sum(fs) / length(fs))
                maxf    = @sprintf("%.4f", maximum(fs))
                factors = join([@sprintf("%.6f", f) for f in fs], ";")
            else
                changed = join(re_apply_wrongtype!(truth, lev, rng), ";")
            end
            kw = NaN; b = "error"; st = "error"; v = NaN; note = "error"
            rv = (v = NaN, n_over = -1, curtail_kW = NaN, status = "error")
            try
                kw, b, st = re_doe(truth)
                v, note   = re_street(truth, issued)
                rv        = re_realised(truth, issued)
            catch err
                note = "error: " * first(replace(sprint(showerror, err), "," => " ", "\n" => " ", "\"" => "'"), 120)
            end
            over = 100 * (issued / kw - 1)
            gap  = issued - kw
            @printf("%-9s  %5s  %4d   %8.3f    %-9s %+6.3f  %+8.1f %%  %7.2f%s  %7.2f    %3d    %6.3f\n",
                    scen, string(lev), d, kw, b, gap, over, v, note == "delivered" ? " " : "c",
                    rv.v, rv.n_over, rv.curtail_kW)
            push!(rows, @sprintf("%s,%.3f,%s,%s,%d,%d,%.6f,%s,%s,%.6f,%.6f,%.3f,%.4f,%s,%.4f,%d,%.6f,%s,%s,%s,\"%s\",\"%s\"",
                                 setting, pu, scen, string(lev), d, seed, kw, b, st, issued, gap, over,
                                 v, note, rv.v, rv.n_over, rv.curtail_kW, rv.status,
                                 meanf, maxf, factors, changed))
        end
    end
    open(joinpath(pwd(), "results", out), "w") do io
        println(io, "setting,source_pu,scenario,level,draw,seed,correct_kW,correct_binding,correct_status,issued_kW,gap_kW,overpromise_pct,boundpoint_V_noVW,boundpoint_note,realised_V_VW,n_customers_over_253,curtail_kW,realised_status,mean_factor,max_factor,factors,changed_segments")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/%s  (%d rows, %.0f s)\n", out, length(rows), time() - t0)
end
