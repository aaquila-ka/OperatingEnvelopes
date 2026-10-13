# scripts/bmopf/doe_timeseries.jl
#
# STEP 3: one full day, 48 half-hour steps.
# House usage: 12 of the 99 real anonymised Victorian smart-meter profiles (P and Q, 5-min)
# from Team-Nando OE1-Ideal (BSD-3, commit 96abbab), averaged to 30 min.
# The 12 profiles are picked with a fixed seed and the mapping is written to a CSV.
# At every step:
#   clean   : records = truth = catalogue (all 16 mm2)        -> answer key DOE
#   Case A  : truth all 22 service cables 4 mm2, records 16   -> issued = clean DOE (over-promise)
#   Case B  : truth 16 mm2, records all 4 mm2                 -> issued = Case A DOE (lost export)
# Source fixed at 1.03 pu, 207-253 V PN at customers, equal allocation, 5 kVA inverters.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_timeseries.jl")
#   julia> run_timeseries(steps = [1, 25])     # quick test: 00:00 and 12:00
#   julia> run_timeseries()                    # full day, 48 steps
# OUTPUT results/doe_timeseries.csv, results/timeseries_profile_map.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_record_errors.jl"))

const TS_FILE = joinpath(pwd(), "data", "profiles", "TeamNando_OE1_LoadShapes.txt")

# ---- read the 5-min shapes and average to 48 half-hours
parse_vec(s) = [parse(Float64, strip(x)) for x in split(s, ",")]
halfhour(v) = (@assert length(v) == 288 "expected 288 five-minute points"; [sum(v[6i-5:6i]) / 6 for i in 1:48])

function read_profiles()
    P = Dict{String, Vector{Float64}}(); Q = Dict{String, Vector{Float64}}(); pv = Float64[]
    for line in eachline(TS_FILE)
        m = match(r"^New Loadshape\.(\S+)"i, line)
        m === nothing && continue
        name = m[1]
        if startswith(name, "Load_shape_")
            P[name] = halfhour(parse_vec(match(r"Pmult=\[([^\]]*)\]", line)[1]))
            Q[name] = halfhour(parse_vec(match(r"Qmult=\[([^\]]*)\]", line)[1]))
        elseif name == "pvshape1"
            pv = halfhour(parse_vec(match(r" mult=\[([^\]]*)\]", line)[1]))
        end
    end
    @assert length(P) == 99 "expected 99 house profiles, found $(length(P))"
    @assert length(pv) == 48 "pvshape1 not found"
    return P, Q, pv
end

# ---- fixed, seeded choice of 12 profiles for the 12 customers
function profile_map(net, P)
    loads  = sort(collect(keys(net["load"])))
    @assert length(loads) == 12 "expected 12 loads, found $(length(loads))"
    shapes = sort(collect(keys(P)); by = s -> parse(Int, replace(s, "Load_shape_" => "")))
    pick   = shapes[randperm(MersenneTwister(RE_SEED), length(shapes))[1:12]]
    return [(load = loads[i], shape = pick[i]) for i in 1:12]
end

function set_loads!(net, pmap, P, Q, t)
    for (ld, sh) in pmap
        l = net["load"][ld]
        l["p_nom"] = fill(1000.0 * P[sh][t], length(l["p_nom"]))
        l["q_nom"] = fill(1000.0 * Q[sh][t], length(l["q_nom"]))
    end
    return net
end

function all_small!(net)
    for id in re_service_ids(net)
        net["line"][id]["linecode"] = RE_SMALL_LC
    end
    return net
end

function ts_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    kw  = r.envelope[cps[1].id][1] / 1000
    ok  = isfinite(r.total_capacity[1])
    b   = ok ? re_binding(r.snapshots[1], net) : "infeasible"
    v   = ok ? max_pn(r.snapshots[1]; only = customer_points(net))[1] : NaN
    return kw, b, v, string(r.termination_status[1])
end

tlabel(t) = @sprintf("%02d:%02d", div(t - 1, 2), 30 * mod(t - 1, 2))

function run_timeseries(; steps = 1:48)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(RE_PU), P)
    open(joinpath(pwd(), "results", "timeseries_profile_map.csv"), "w") do io
        println(io, "load,profile,daily_kWh")
        for (ld, sh) in pmap
            @printf(io, "%s,%s,%.3f\n", ld, sh, sum(P[sh]) / 2)
        end
    end
    println("time   pv   load kW | clean kW  bind      V     | A: correct  over-prom  real V   | B: issued  lost")
    rows = String[]
    for t in steps
        load_kw = sum(P[sh][t] for (_, sh) in pmap)
        row = try
            clean = set_loads!(make_net(RE_PU), pmap, P, Q, t)
            small = all_small!(set_loads!(make_net(RE_PU), pmap, P, Q, t))
            c_kw, c_b, c_v, c_st = ts_doe(clean)
            a_kw, a_b, a_v, a_st = ts_doe(small)
            a_vreal, a_note = re_street(small, c_kw)       # Case A: issued clean DOE on 4 mm2 street
            b_vreal, b_note = re_street(clean, a_kw)       # Case B: issued 4 mm2 DOE on 16 mm2 street
            overA = 100 * (c_kw / a_kw - 1)
            lossB = 100 * (a_kw / c_kw - 1)
            @printf("%s  %4.2f  %6.2f  | %7.3f  %-9s %6.2f | %7.3f   %+7.1f %%  %6.2f %-3s | %7.3f  %+6.1f %%\n",
                    tlabel(t), pv[t], load_kw, c_kw, c_b, c_v, a_kw, overA, a_vreal,
                    a_note == "delivered" ? "" : "(c)", a_kw, lossB)
            @sprintf("%d,%s,%.4f,%.4f,%.6f,%s,%.4f,%s,%.6f,%s,%s,%.3f,%.4f,%s,%.3f,%.4f,%s",
                     t, tlabel(t), pv[t], load_kw, c_kw, c_b, c_v, c_st, a_kw, a_b, a_st,
                     overA, a_vreal, a_note, lossB, b_vreal, b_note)
        catch err
            msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " "), 120)
            println(tlabel(t), "  ERROR: ", msg)
            @sprintf("%d,%s,%.4f,%.4f,NaN,error,NaN,error,NaN,error,error,NaN,NaN,%s,NaN,NaN,error",
                     t, tlabel(t), pv[t], load_kw, "error: " * msg)
        end
        push!(rows, row)
    end
    open(joinpath(pwd(), "results", "doe_timeseries.csv"), "w") do io
        println(io, "step,time,pv_shape,total_load_kW,clean_kW,clean_binding,clean_max_vpn_V,clean_status,A_correct_kW,A_binding,A_status,A_overpromise_pct,A_true_street_V,A_note,B_lost_pct,B_true_street_V,B_note")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_timeseries.csv (%d rows) and results/timeseries_profile_map.csv  (%.0f s)\n",
            length(rows), time() - t0)
end