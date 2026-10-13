# scripts/bmopf/doe_clearsky.jl
#
# STEP (c): a clear-sky day as an upper bound for the sun-limited results.
# Same 12 house profiles and settings as doe_timeseries.jl (1.03 pu, equal allocation, Case A =
# all 22 service cables really 4 mm2). Only the solar shape changes:
#   clear(t) = PEAK x sin(pi x (h - rise) / (set - rise)) between rise and set, else 0
#   rise and set are taken from the measured Team-Nando shape (first/last half-hour with sun),
#   h = middle of the half-hour; PEAK = 0.85 of the 5 kW rating (ASSUMPTION: typical clear-sky
#   summer peak of rooftop PV after temperature and system losses; the measured day peaks at 0.72).
# The DOEs do not depend on the sun (they are permissions); only the sun-limited reading changes.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> using Logging; disable_logging(Logging.Warn)
#   julia> include("scripts/bmopf/doe_clearsky.jl")
#   julia> run_clearsky()                      # PEAK = 0.85
# OUTPUT results/doe_clearsky.csv  (same columns as results/doe_timeseries.csv)

include(joinpath(pwd(), "scripts", "bmopf", "doe_timeseries.jl"))

function clear_shape(pv_measured; peak = 0.85)
    sunny = findall(>(0), pv_measured)
    rise  = (first(sunny) - 1) / 2            # start of first sunny half-hour (h)
    set   = last(sunny) / 2                   # end of last sunny half-hour (h)
    shape = zeros(48)
    for i in 1:48
        h = (i - 1) / 2 + 0.25
        rise < h < set && (shape[i] = peak * sin(pi * (h - rise) / (set - rise)))
    end
    return shape, rise, set
end

function run_clearsky(; peak = 0.85, pu = RE_PU, out = "doe_clearsky.csv")
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    cs, rise, set = clear_shape(pv; peak = peak)
    @printf("clear-sky shape: sun from %.1f h to %.1f h, peak %.2f x 5 kW = %.2f kW per house\n\n",
            rise, set, peak, PV_KW * peak)
    println("time   sun cap | clean kW  | gap kW  | sun-limited: V(VW) >253 curtail   (measured day: V)")
    rows = String[]
    steps = [t for t in 1:48 if cs[t] > 0]
    nover = 0; vmax = -Inf
    for t in steps
        load_kw = sum(P[sh][t] for (_, sh) in pmap)
        try
            s = ts_step(t, pmap, P, Q, cs; pu = pu)
            m = re_realised(all_small!(set_loads!(make_net(pu), pmap, P, Q, t)), min(s.c_kw, PV_KW * pv[t]))
            @printf("%s  %5.2f  | %7.3f   | %+6.3f  |   %7.2f  %3d  %6.3f      (%7.2f)\n",
                    tlabel(t), s.pvc, s.c_kw, s.gap, s.p.v, s.p.n_over, s.p.curtail_kW, m.v)
            s.p.n_over > 0 && (nover += 1)
            isfinite(s.p.v) && (vmax = max(vmax, s.p.v))
            push!(rows, ts_row(s, pu, load_kw))
        catch err
            msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " "), 120)
            println(tlabel(t), "  ERROR: ", msg)
        end
    end
    open(joinpath(pwd(), "results", out), "w") do io
        println(io, TS_HEADER)
        foreach(l -> println(io, l), rows)
    end
    @printf("\nclear-sky day: %d half-hours with a customer above 253 V, peak %.2f V\n", nover, vmax)
    @printf("written results/%s (%d rows, %.0f s)\n", out, length(rows), time() - t0)
end
