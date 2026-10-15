# =============================================================================
# doe_service_errors.jl: plausible service-connection record errors (Oct 2026 rework,
#                        after Fred Geth's email on which errors really occur)
#
# What it does (plain English):
#   The RECORDS always show the catalogue street: every service cable = 16 mm2 Cu
#   underground, and every inverter sits right at the meter (no house wiring).
#   The TRUE street differs from the records in ONE of four ways. Only the 12 service
#   segments that feed a home are touched (the 10 dead-end stubs carry no current):
#     type       : m home segments are really overhead 16 mm2 aerial bundled cable
#                  (abc4x16, a line code from LV3's own catalogue, about 1.59 x the
#                  phase resistance of 16 mm2 Cu); m = 1, 3, 6, 12
#     length     : each home segment gets its own length factor f = 1 + sigma * randn,
#                  f >= 0.5; sigma = 0.10, 0.20, 0.30   (PROVISIONAL, waiting on Fred)
#     lengthbias : every home segment is longer by the same factor 1.10, 1.25, 1.50
#                  (PROVISIONAL); one draw per level because nothing is random
#     wiring     : every home has extra house wiring between the meter and the inverter,
#                  sized from the AS/NZS 4777.1 1 % voltage-rise allowance (main
#                  switchboard to inverter terminals):
#                    loop R at 100 % = 0.01 x 230 V / (5000 VA / 230 V) = 0.1058 ohm,
#                    split equally between phase and neutral (0.0529 ohm each);
#                  levels 25, 50, 100 % of that allowance; one draw per level
#   Length scales R, X and the mutual terms together (they are all per metre), which is
#   correct for a length error. The type case uses the abc4x16 line code exactly as the
#   catalogue gives it. The 253 V limit stays at the meter (point of supply) in every case,
#   so in the wiring case the inverter sees a HIGHER voltage than the meter.
#   Issued DOE, correct DOE, gap, bound-point and realised readings are exactly as in
#   doe_record_errors.jl: its functions are reused here, not copied.
#   Seeds: RE_SEED + 100000 x scenario number (3 type, 4 length, 5 lengthbias, 6 wiring;
#   1 and 2 belong to doe_record_errors.jl) + 1000 x level number + draw number.
# Inputs:   includes doe_record_errors.jl (-> doe_common.jl -> load_lv3.jl, LV3 .dss files)
# Outputs:  results/doe_service_errors.csv (or the name given in `out`); prints a table
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, FRESH session):
#   include("scripts/bmopf/doe_service_errors.jl")
#   se_check()                              # sanity check: the 12 segments + wiring R
#   run_service_errors(n_draws = 2)         # quick test (writes the csv)
#   run_service_errors(n_draws = 20)        # full run
#   At a time of the measured day (same loads as doe_timeseries.jl), FRESH session:
#   include("scripts/bmopf/doe_timeseries.jl"); include("scripts/bmopf/doe_service_errors.jl")
#   run_service_errors_at(25; n_draws = 20) # step 25 = 12:00, as in the paper
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt; error types from F. Geth (pers. comm.,
#           Oct 2026); wiring size from the AS/NZS 4777.1 voltage-rise requirement
# =============================================================================

isdefined(Main, :run_record_errors) ||
    include(joinpath(pwd(), "scripts", "bmopf", "doe_record_errors.jl"))

const SE_ABC_LC      = "abc4x16_lv_oh_4w_bundled"
const SE_TYPE_MS     = [1, 3, 6, 12]
const SE_LEN_SIGMAS  = [0.10, 0.20, 0.30]
const SE_LEN_BIAS    = [1.10, 1.25, 1.50]
const SE_WIRE_FRACS  = [0.25, 0.50, 1.00]
const SE_V_NOM       = 230.0
const SE_S_INV       = 5000.0
const SE_R_LOOP_1PCT = 0.01 * SE_V_NOM / (SE_S_INV / SE_V_NOM)   # 0.1058 ohm

# ---- the 12 service segments that have a customer (load) bus at one end
function se_home_ids(net)
    lbus = Set(String(ld["bus"]) for ld in values(net["load"]))
    ids  = sort([id for id in re_service_ids(net)
                 if String(net["line"][id]["bus_to"]) in lbus ||
                    String(net["line"][id]["bus_from"]) in lbus])
    @assert length(ids) == 12 "expected 12 home service segments, found $(length(ids))"
    return ids
end

# ---- type: m random home segments are really overhead 16 mm2 ABC
function se_apply_type!(net, m, rng)
    @assert haskey(net["linecode"], SE_ABC_LC) "abc4x16 line code not found in network"
    ids    = se_home_ids(net)
    chosen = ids[sort(randperm(rng, length(ids))[1:m])]
    for id in chosen
        net["line"][id]["linecode"] = SE_ABC_LC
    end
    return chosen
end

# ---- length scatter: every home segment gets its own factor
function se_apply_length!(net, sigma, rng)
    fs = Float64[]
    for id in se_home_ids(net)
        f = max(0.5, 1 + sigma * randn(rng))
        net["line"][id]["length"] = f * Float64(net["line"][id]["length"])
        push!(fs, f)
    end
    return fs
end

# ---- length bias: every home segment longer by the same factor
function se_apply_lengthbias!(net, f)
    for id in se_home_ids(net)
        net["line"][id]["length"] = f * Float64(net["line"][id]["length"])
    end
    return f
end

# ---- 2-wire (phase + neutral) line code, R only, per metre (used with length = 1 m)
function se_wiring_linecode(r_cond)
    lc = Dict{String,Any}()
    for i in 1:2, j in 1:2
        lc["R_series_$(i)_$(j)"] = i == j ? r_cond : 0.0
        lc["X_series_$(i)_$(j)"] = 0.0
        for k in ("G_from", "B_from", "G_to", "B_to")
            lc["$(k)_$(i)_$(j)"] = 0.0
        end
    end
    lc["i_max"] = [1000.0, 1000.0]
    return lc
end

# ---- wiring: move every inverter behind a short phase + neutral line from its meter bus
function se_apply_wiring!(net, frac)
    r_cond = frac * SE_R_LOOP_1PCT / 2
    name   = @sprintf("house_wiring_%.0fpct", 100 * frac)
    net["linecode"][name] = se_wiring_linecode(r_cond)
    for (id, inv) in sort(collect(net["ibr"]); by = first)
        mbus = String(inv["bus"])
        ph   = String(inv["terminal_map"][1])
        nb   = mbus * "_inv_" * String(id)
        @assert !haskey(net["bus"], nb) "bus $nb already exists"
        net["bus"][nb] = Dict{String,Any}("terminal_names" => [ph, "n"], "neutral_terminal" => "n")
        net["line"]["wiring_" * String(id)] = Dict{String,Any}(
            "length" => 1.0, "bus_from" => mbus, "bus_to" => nb,
            "terminal_map_from" => [ph, "n"], "terminal_map_to" => [ph, "n"],
            "linecode" => name)
        inv["bus"] = nb
    end
    return r_cond
end

# ---- sanity check before any DOE run
function se_check(pu = RE_PU)
    net = make_net(pu)
    println("the 12 home service segments (records = 16 mm2 Cu):")
    for id in se_home_ids(net)
        l = net["line"][id]
        r = Float64(l["length"]) * Float64(net["linecode"][l["linecode"]]["R_series_1_1"])
        @printf("  %-14s %-10s -> %-10s %7.2f m   R_phase %.4f ohm\n",
                id, l["bus_from"], l["bus_to"], Float64(l["length"]), r)
    end
    rc = Float64(net["linecode"][RE_SVC_LC]["R_series_1_1"])
    ra = Float64(net["linecode"][SE_ABC_LC]["R_series_1_1"])
    @printf("abc4x16 / 16 mm2 Cu phase R ratio: %.3f\n", ra / rc)
    @printf("1%% wiring allowance: loop R %.4f ohm (%.4f ohm per conductor)\n",
            SE_R_LOOP_1PCT, SE_R_LOOP_1PCT / 2)
end

# ---- main
function run_service_errors(; n_draws = 2, pu = RE_PU, prep! = identity,
                            setting = "snapshot_1kW", out = "doe_service_errors.csv")
    t0 = time()
    issued, ib, ist = re_doe(prep!(make_net(pu)))
    @printf("[%s, %.3f pu] records (all 16 mm2 Cu, no house wiring): issued DOE %.3f kW (%s) [%s]\n\n",
            setting, pu, issued, ib, ist)
    println("scenario     level  draw   correct kW  binding    gap kW  over-promise  bound V   realised V  >253V  curtail kW")
    rows  = String[]
    scens = (("type", SE_TYPE_MS, true), ("length", SE_LEN_SIGMAS, true),
             ("lengthbias", SE_LEN_BIAS, false), ("wiring", SE_WIRE_FRACS, false))
    for (k, (scen, levels, random)) in enumerate(scens)
        si = k + 2
        for (li, lev) in enumerate(levels)
            nd = (random && !(scen == "type" && lev == 12)) ? n_draws : 1
            for d in 1:nd
                seed   = RE_SEED + 100_000 * si + 1_000 * li + d
                rng    = MersenneTwister(seed)
                truth  = prep!(make_net(pu))
                detail = ""
                if scen == "type"
                    detail = join(se_apply_type!(truth, lev, rng), ";")
                elseif scen == "length"
                    detail = join([@sprintf("%.4f", f) for f in se_apply_length!(truth, lev, rng)], ";")
                elseif scen == "lengthbias"
                    se_apply_lengthbias!(truth, lev)
                    detail = @sprintf("all home segments x %.2f", lev)
                else
                    r = se_apply_wiring!(truth, lev)
                    detail = @sprintf("loop R %.4f ohm per home", 2r)
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
                @printf("%-11s  %5s  %4d   %8.3f    %-9s %+6.3f  %+8.1f %%  %7.2f%s  %7.2f    %3d    %6.3f\n",
                        scen, string(lev), d, kw, b, gap, over, v, note == "delivered" ? " " : "c",
                        rv.v, rv.n_over, rv.curtail_kW)
                push!(rows, @sprintf("%s,%.3f,%s,%s,%d,%d,%.6f,%s,%s,%.6f,%.6f,%.3f,%.4f,%s,%.4f,%d,%.6f,%s,\"%s\"",
                                     setting, pu, scen, string(lev), d, seed, kw, b, st, issued, gap, over,
                                     v, note, rv.v, rv.n_over, rv.curtail_kW, rv.status, detail))
            end
        end
    end
    open(joinpath(pwd(), "results", out), "w") do io
        println(io, "setting,source_pu,scenario,level,draw,seed,correct_kW,correct_binding,correct_status,issued_kW,gap_kW,overpromise_pct,boundpoint_V_noVW,boundpoint_note,realised_V_VW,n_customers_over_253,curtail_kW,realised_status,detail")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/%s  (%d rows, %.0f s)\n", out, length(rows), time() - t0)
end

# ---- same run at one step of the measured day (needs doe_timeseries.jl included FIRST,
#      it provides read_profiles, profile_map, set_loads! and tlabel)
function run_service_errors_at(t; n_draws = 20, pu = RE_PU)
    @assert isdefined(Main, :read_profiles) "include scripts/bmopf/doe_timeseries.jl first"
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    prep!(net) = set_loads!(net, pmap, P, Q, t)
    tag = replace(tlabel(t), ":" => "")
    run_service_errors(; n_draws = n_draws, pu = pu, prep! = prep!,
                       setting = "day_" * tag, out = "doe_service_errors_" * tag * ".csv")
end
