# scripts/bmopf/doe_record_errors.jl
#
# STEP 2: realistic cable-record errors with many random draws ("dirty", "dirtier").
#
# The RECORDS always show the catalogue: every service cable = 16 mm2 Cu.
# The TRUE street differs from the records in one of two ways:
#   scatter   : each of the 22 service segments gets its OWN resistance factor
#               f = 1 + sigma * randn  (diagonal R only, like the severity sweep), f >= 0.5
#               levels sigma = 0.05, 0.10, 0.20
#   wrongtype : m randomly chosen service segments are really 4 mm2 Cu
#               (whole line code swapped, like Case A); levels m = 2, 5, 11 of 22
# Issued DOE  = DOE on the records (the same for every draw)
# Correct DOE = DOE on that draw's true street (the answer key for that draw)
# The issued DOE is then applied to the true street to read the real customer voltage.
# Source 1.03 pu, original CSIRO loads, 207-253 V PN at customers, equal allocation.
# Every draw has its own seed, so any single draw can be rebuilt exactly.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> include("scripts/bmopf/doe_record_errors.jl")
#   julia> run_record_errors(n_draws = 2)      # quick test first
#   julia> run_record_errors(n_draws = 20)     # full run
# OUTPUT results/doe_record_errors.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))
using Random

const RE_SVC_LC   = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"
const RE_SMALL_LC = "uglv_4cu_xlpe/pvc_ug_4w_bundled"
const RE_PU       = 1.03
const RE_SEED     = 20261013
const RE_SIGMAS   = [0.05, 0.10, 0.20]
const RE_MS       = [2, 5, 11]

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

# ---- same evaluation rules as doe_severity_sweep.jl (copied, renamed)
function re_eval_copy(net; relax_smax = false, s_big = 1.0e5)
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

function re_v_at_export(net, cps, kw; relax_smax = false)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(re_eval_copy(net; relax_smax = relax_smax), cps, caps;
                                   solver_options = OPTS)
    ev.feasible[1] || return NaN
    v, _ = max_pn(ev.snapshots[1]; only = customer_points(net))
    return v
end

function re_binding(snap, net)
    smax = 0.0
    for (id, inv) in net["ibr"]
        g = snap["ibr"][id][String(inv["terminal_map"][1])]
        smax = max(smax, hypot(g["pg"], g["qg"]) / inv["s_max"][1])
    end
    vc, _ = max_pn(snap; only = customer_points(net))
    return smax > 0.999 ? "inverter" : vc >= V_MAX_PN - 0.01 ? "voltage" : "nameplate"
end

function re_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    kw  = r.envelope[cps[1].id][1] / 1000
    b   = isfinite(r.total_capacity[1]) ? re_binding(r.snapshots[1], net) : "infeasible"
    return kw, b, string(r.termination_status[1])
end

function re_street(net, kw)
    cps = connection_points(net)
    v = re_v_at_export(net, cps, kw)
    isfinite(v) && return v, "delivered"
    v = re_v_at_export(net, cps, kw; relax_smax = true)
    return v, "undeliverable (5 kVA); counterfactual"
end

# ---- main
function run_record_errors(; n_draws = 2)
    t0 = time()
    issued, ib, ist = re_doe(make_net(RE_PU))
    @printf("records (all 16 mm2): issued DOE %.3f kW (%s) [%s]\n\n", issued, ib, ist)
    println("scenario   level  draw   correct kW  binding    over-promise   real V    note")
    rows = String[]
    for (si, (scen, levels)) in enumerate((("scatter", RE_SIGMAS), ("wrongtype", RE_MS)))
        for (li, lev) in enumerate(levels), d in 1:n_draws
            seed  = RE_SEED + 100_000 * si + 1_000 * li + d
            rng   = MersenneTwister(seed)
            truth = make_net(RE_PU)
            meanf = ""; maxf = ""; changed = ""
            if scen == "scatter"
                fs    = re_apply_scatter!(truth, lev, rng)
                meanf = @sprintf("%.4f", sum(fs) / length(fs))
                maxf  = @sprintf("%.4f", maximum(fs))
            else
                changed = join(re_apply_wrongtype!(truth, lev, rng), ";")
            end
            kw = NaN; b = "error"; st = "error"; v = NaN; note = "error"
            try
                kw, b, st = re_doe(truth)
                v, note   = re_street(truth, issued)
            catch err
                note = "error: " * first(replace(sprint(showerror, err), "," => " ", "\n" => " ", "\"" => "'"), 120)
            end
            over = 100 * (issued / kw - 1)
            @printf("%-9s  %5s  %4d   %8.3f    %-9s  %+8.1f %%   %7.2f   %s\n",
                    scen, string(lev), d, kw, b, over, v, note)
            push!(rows, @sprintf("%s,%s,%d,%d,%.6f,%s,%s,%.6f,%.3f,%.4f,%s,%s,%s,\"%s\"",
                                 scen, string(lev), d, seed, kw, b, st, issued, over, v, note,
                                 meanf, maxf, changed))
        end
    end
    open(joinpath(pwd(), "results", "doe_record_errors.csv"), "w") do io
        println(io, "scenario,level,draw,seed,correct_kW,correct_binding,correct_status,issued_kW,overpromise_pct,true_street_max_vpn_V,note,mean_factor,max_factor,changed_segments")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_record_errors.csv  (%d rows, %.0f s)\n", length(rows), time() - t0)
end