# =============================================================================
# doe_timeseries.jl: one full day (48 half-hours) of clean vs Case A DOEs with real house usage
#
# What it does (plain English):
#   House usage: 12 of the 99 anonymised Victorian smart-meter profiles (P and Q, 5-min) from
#   Team-Nando OE1-Ideal (commit 96abbab), averaged to 30 min; the profile day is day index 350,
#   the lowest-demand day in the dataset. The 12 profiles are picked with a fixed seed and the
#   mapping is written to a CSV. At every half-hour step (step 1 = 00:00, step 25 = 12:00):
#     clean   : records = truth = catalogue (all 16 mm2)        -> answer-key DOE
#     Case A  : truth all 22 service cables 4 mm2, records 16   -> issued = clean DOE
#               gap = issued - correct; over-promise % = gap / correct x 100
#     (Case B is the mirror of Case A: lost % = 1/(1 + over-promise) - 1; for completeness)
#   What the issued DOE does on the Case A street, read three ways:
#     boundpoint_noVW : everyone exports exactly the DOE, Volt-Watt off (old, worst case)
#     worst_VW        : everyone MAY export up to the DOE, inverters keep Volt-Watt/Volt-VAr/5 kVA
#     pv_VW           : as worst_VW but nobody can export more than the sun gives:
#                       cap = min(DOE, 5 kW x pv_shape) -> the realistic number; NaN at night
#                       (no export; n_over 0 there, while a failed solve gives n_over -1)
#   Source fixed at pu (default 1.03), 207-253 V phase-to-neutral at customers, equal sharing.
#   Also defines the shared helpers used by many later scripts (read_profiles, profile_map,
#   set_loads!, all_small!, ts_doe, ts_step, tlabel) and run_record_errors_at().
#   A half-hour whose solve throws an error is printed as ERROR and left out of the CSV.
#
# Inputs:   data/profiles/TeamNando_OE1_LoadShapes.txt, LV3 network (via load_lv3.jl).
#           Includes doe_record_errors.jl (-> doe_common.jl -> load_lv3.jl).
# Outputs:  results/doe_timeseries.csv (48 rows), results/timeseries_profile_map.csv;
#           run_record_errors_at(25) writes results/doe_record_errors_1200.csv.
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_timeseries.jl")   then   run_timeseries()
#   (same session)   run_record_errors_at(25; n_draws = 20)     # record errors at 12:00 loads
# Used for: REPRODUCE.md steps 9 and 10 (section 4 rows "Full day, 1.03 pu" and "Record
#           errors, 12:00 loads"); DATA_CARD.md files 5, 7 and 8.
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Ipopt; Team-Nando OE1-Ideal / MV-LV-Networks profiles (BSD-3, AusNet
#           smart-meter data).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_record_errors.jl"))

# Where the house-usage and sun shapes live, and the solar inverter size (5 kW) used for the sun limit
const TS_FILE = joinpath(pwd(), "data", "profiles", "TeamNando_OE1_LoadShapes.txt")
const PV_KW   = 5.0

# ---- read the 5-min shapes and average to 48 half-hours
# Turns a text list like "0.1, 0.2, ..." into numbers
parse_vec(s) = [parse(Float64, strip(x)) for x in split(s, ",")]
# 288 five-minute values -> 48 half-hour values (average of each group of 6)
halfhour(v) = (@assert length(v) == 288 "expected 288 five-minute points"; [sum(v[6i-5:6i]) / 6 for i in 1:48])

# Reads the 99 house shapes (P = real power, Q = reactive power, per kW) and the sun shape "pvshape1",
# all averaged to half-hours; returns P, Q (dictionaries by shape name) and pv (48 numbers)
function read_profiles()
    P = Dict{String, Vector{Float64}}(); Q = Dict{String, Vector{Float64}}(); pv = Float64[]
    for line in eachline(TS_FILE)
        # Only lines that define a Loadshape matter; the name tells us if it is a house or the sun
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
# Picks 12 of the 99 house shapes for the 12 homes with a fixed seed, so every run picks the same ones;
# returns a list of (load name, shape name) pairs
function profile_map(net, P)
    loads  = sort(collect(keys(net["load"])))
    @assert length(loads) == 12 "expected 12 loads, found $(length(loads))"
    # Put the shapes in number order (Load_shape_1, 2, ...), so the pick does not depend on file order
    shapes = sort(collect(keys(P)); by = s -> parse(Int, replace(s, "Load_shape_" => "")))
    # Shuffle with the fixed seed and keep the first 12
    pick   = shapes[randperm(MersenneTwister(RE_SEED), length(shapes))[1:12]]
    return [(load = loads[i], shape = pick[i]) for i in 1:12]
end

# Sets every home's load to its shape's value at half-hour t (the shapes are per kW, so x 1000 gives W)
function set_loads!(net, pmap, P, Q, t)
    for (ld, sh) in pmap
        l = net["load"][ld]
        l["p_nom"] = fill(1000.0 * P[sh][t], length(l["p_nom"]))
        l["q_nom"] = fill(1000.0 * Q[sh][t], length(l["q_nom"]))
    end
    return net
end

# Case A street: makes all 22 service cables the thin 4 mm2 cable
function all_small!(net)
    for id in re_service_ids(net)
        net["line"][id]["linecode"] = RE_SMALL_LC
    end
    return net
end

# Solves the equal-share DOE (DOE = the export limit every home gets) on a street; returns the per-home
# limit in kW, what limits it, the highest customer voltage, and the solver status
function ts_doe(net)
    cps = connection_points(net)
    r   = doe(net, cps)
    kw  = r.envelope[cps[1].id][1] / 1000
    ok  = isfinite(r.total_capacity[1])
    b   = ok ? re_binding(r.snapshots[1], net) : "infeasible"
    # Highest phase-to-neutral voltage (what a home feels) at a customer, only if the solve worked
    v   = ok ? max_pn(r.snapshots[1]; only = customer_points(net))[1] : NaN
    return kw, b, v, string(r.termination_status[1])
end

# Half-hour number -> clock time: step 1 = 00:00, step 2 = 00:30, ..., step 25 = 12:00
tlabel(t) = @sprintf("%02d:%02d", div(t - 1, 2), 30 * mod(t - 1, 2))

# ---- one time step, any source voltage; used by the day run and the source sweep
# Everything for one half-hour t: build the clean street and the Case A street with that half-hour's loads,
# solve both DOEs, and read what the clean (issued) DOE does on the Case A street three ways
function ts_step(t, pmap, P, Q, pv; pu = RE_PU)
    # Clean street = the records (all 16 mm2): its DOE is the one issued, and the answer key for "clean"
    clean = set_loads!(make_net(pu), pmap, P, Q, t)
    # Case A true street: same loads but all 22 service cables 4 mm2
    small = all_small!(set_loads!(make_net(pu), pmap, P, Q, t))
    c_kw, c_b, c_v, c_st = ts_doe(clean)
    a_kw, a_b, a_v, a_st = ts_doe(small)
    bp_v, bp_note = re_street(small, c_kw)                 # old bound-point, Volt-Watt off
    w   = re_realised(small, c_kw)                         # may export up to DOE, Volt-Watt on
    # Sun limit: nobody can export more than a 5 kW system makes at this half-hour (pv[t] is 0 to 1)
    pvc = min(c_kw, PV_KW * pv[t])
    p   = re_realised(small, pvc)                          # limited by available sun, Volt-Watt on
    # Gap = issued - correct; over = 100 x (issued / correct - 1);
    # lossB = the mirror Case B (records 4 mm2, truth 16 mm2): 100 x (a_kw / c_kw - 1), a negative % = export lost
    return (t = t, pv = pv[t], c_kw = c_kw, c_b = c_b, c_v = c_v, c_st = c_st,
            a_kw = a_kw, a_b = a_b, a_st = a_st,
            gap = c_kw - a_kw, over = 100 * (c_kw / a_kw - 1), lossB = 100 * (a_kw / c_kw - 1),
            bp_v = bp_v, bp_note = bp_note, w = w, pvc = pvc, p = p)
end

# Column names of results/doe_timeseries.csv, in the same order as ts_row writes them
const TS_HEADER = "step,time,source_pu,pv_shape,daylight,total_load_kW,clean_kW,clean_binding,clean_max_vpn_V,clean_status,A_correct_kW,A_binding,A_status,A_gap_kW,A_overpromise_pct,A_boundpoint_V_noVW,A_boundpoint_note,A_worst_V_VW,A_worst_n_over_253,A_worst_curtail_kW,pv_cap_kW,A_pv_V_VW,A_pv_n_over_253,A_pv_curtail_kW,B_lost_pct_mirror"

# Turns one ts_step result into one CSV line (daylight = yes when the sun shape is above 0)
function ts_row(s, pu, load_kw)
    @sprintf("%d,%s,%.3f,%.4f,%s,%.4f,%.6f,%s,%.4f,%s,%.6f,%s,%s,%.6f,%.3f,%.4f,%s,%.4f,%d,%.6f,%.6f,%.4f,%d,%.6f,%.3f",
             s.t, tlabel(s.t), pu, s.pv, s.pv > 0 ? "yes" : "no", load_kw, s.c_kw, s.c_b, s.c_v, s.c_st,
             s.a_kw, s.a_b, s.a_st, s.gap, s.over, s.bp_v, s.bp_note,
             s.w.v, s.w.n_over, s.w.curtail_kW, s.pvc, s.p.v, s.p.n_over, s.p.curtail_kW, s.lossB)
end

# Main day run: for each of the 48 half-hours, run ts_step and print/save the results;
# also saves which house shape went to which home
function run_timeseries(; steps = 1:48, pu = RE_PU, out = "doe_timeseries.csv")
    t0 = time()
    P, Q, pv = read_profiles()
    # Same 12 shapes for every half-hour (fixed seed)
    pmap = profile_map(make_net(pu), P)
    # Save the home -> shape mapping with each shape's daily energy (sum of half-hour kW / 2 = kWh)
    open(joinpath(pwd(), "results", "timeseries_profile_map.csv"), "w") do io
        println(io, "load,profile,daily_kWh")
        for (ld, sh) in pmap
            @printf(io, "%s,%s,%.3f\n", ld, sh, sum(P[sh]) / 2)
        end
    end
    println("time   pv cap | clean kW  bind    | A kW   gap kW  over-prom | bound V  worst V(VW) | sun-limited: V(VW) >253 curtail")
    rows = String[]
    for t in steps
        # Total house load at this half-hour (kW), saved with the row
        load_kw = sum(P[sh][t] for (_, sh) in pmap)
        try
            # Solve this half-hour; a "c" after the bound-point voltage marks a counterfactual (pretend-big inverter) reading
            s = ts_step(t, pmap, P, Q, pv; pu = pu)
            @printf("%s %5.2f  | %7.3f  %-7s | %6.3f %+6.3f  %+7.1f %% | %7.2f%s  %7.2f    | %7.2f  %3d  %6.3f\n",
                    tlabel(t), s.pvc, s.c_kw, s.c_b, s.a_kw, s.gap, s.over, s.bp_v,
                    s.bp_note == "delivered" ? " " : "c", s.w.v, s.p.v, s.p.n_over, s.p.curtail_kW)
            push!(rows, ts_row(s, pu, load_kw))
        # If this half-hour fails, print a short message and leave it out of the CSV
        catch err
            msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " "), 120)
            println(tlabel(t), "  ERROR: ", msg)
        end
    end
    # Write the header and all rows
    open(joinpath(pwd(), "results", out), "w") do io
        println(io, TS_HEADER)
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/%s (%d rows) and results/timeseries_profile_map.csv  (%.0f s)\n",
            out, length(rows), time() - t0)
end

# ---- record-error draws (step 2) at the loads of one half-hour of the day
# Reruns the record-error draws of doe_record_errors.jl, but with the house loads of half-hour t
# (t = 25 is 12:00); writes results/doe_record_errors_HHMM.csv
function run_record_errors_at(t; n_draws = 20, pu = RE_PU)
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    # prep! puts this half-hour's loads on every street that run_record_errors builds (records and each true street)
    prep!(net) = set_loads!(net, pmap, P, Q, t)
    tag = replace(tlabel(t), ":" => "")
    run_record_errors(; n_draws = n_draws, pu = pu, prep! = prep!,
                      setting = "day_" * tag, out = "doe_record_errors_" * tag * ".csv")
end
