# scripts/bmopf/doe_critical_cables.jl
#
# STEP 2.5 (v2): which service cables are critical?  v2 adds the realised voltage with
# Volt-Watt on (customers may export up to the issued DOE), customers above 253 V and curtailment.
# One cable at a time: the record says 16 mm2 (catalogue) but THIS ONE segment is really
# 4 mm2; all other 21 segments are correct. For each segment we compute the correct DOE,
# the over-promise of the issued (catalogue) DOE, and the real street voltage.
# Uses the same functions and settings as doe_record_errors.jl (1.03 pu, equal allocation).
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> include("scripts/bmopf/doe_critical_cables.jl")
#   julia> run_critical_cables()
# OUTPUT results/doe_critical_cables.csv   (sorted, most harmful segment first)

include(joinpath(pwd(), "scripts", "bmopf", "doe_record_errors.jl"))

function run_critical_cables()
    t0 = time()
    issued, _, _ = re_doe(make_net(RE_PU))
    ids = re_service_ids(make_net(RE_PU))
    @printf("issued DOE (records, all 16 mm2): %.3f kW\n\n", issued)
    println("segment            from -> to            length   correct kW  binding    over-promise   bound V   realised V(VW) >253V curtail kW")
    res = []
    for id in ids
        truth = make_net(RE_PU)
        l = truth["line"][id]
        l["linecode"] = RE_SMALL_LC
        kw, b, st = re_doe(truth)
        v, note   = re_street(truth, issued)
        rv        = re_realised(truth, issued)
        over = 100 * (issued / kw - 1)
        fb = string(get(l, "bus_from", "?")); tb = string(get(l, "bus_to", "?"))
        len = get(l, "length", NaN)
        @printf("%-18s %-9s -> %-9s %8.4f   %8.3f    %-9s  %+8.1f %%   %7.2f%s  %7.2f        %3d   %6.3f\n",
                id, fb, tb, len, kw, b, over, v, note == "delivered" ? " " : "c", rv.v, rv.n_over, rv.curtail_kW)
        push!(res, (id = id, fb = fb, tb = tb, len = len, kw = kw, b = b, st = st,
                    over = over, v = v, note = note, rv = rv))
    end
    sort!(res; by = r -> -r.over)
    open(joinpath(pwd(), "results", "doe_critical_cables.csv"), "w") do io
        println(io, "segment,bus_from,bus_to,length,correct_kW,correct_binding,correct_status,issued_kW,gap_kW,overpromise_pct,boundpoint_V_noVW,boundpoint_note,realised_V_VW,n_customers_over_253,curtail_kW")
        for r in res
            @printf(io, "%s,%s,%s,%.6f,%.6f,%s,%s,%.6f,%.6f,%.3f,%.4f,%s,%.4f,%d,%.6f\n",
                    r.id, r.fb, r.tb, r.len, r.kw, r.b, r.st, issued, issued - r.kw, r.over, r.v, r.note,
                    r.rv.v, r.rv.n_over, r.rv.curtail_kW)
        end
    end
    n_harm = count(r -> r.over > 1.0, res)
    @printf("\n%d of %d segments cause more than 1 %% over-promise on their own\n", n_harm, length(res))
    @printf("written results/doe_critical_cables.csv  (%.0f s)\n", time() - t0)
end
