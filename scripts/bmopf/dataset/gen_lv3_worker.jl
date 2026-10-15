# scripts/bmopf/dataset/gen_lv3_worker.jl
#
# Loaded on every Julia process by gen_lv3.jl. Solves ONE dataset scenario on LV3:
#   records network (all service cables 16 mm2) -> issued equal DOE (bound point)
#   each "true" feeder (some customer cables really 4 mm2) -> correct equal DOE, and what the
#   issued DOE really does there: realised voltages when customers may export up to the DOE
#   ("full") and when limited by the sun available ("sun"), Volt-VAr/Volt-Watt/5 kVA kept.
# Same functions as the thesis scripts: ts_doe, re_realised (doe_timeseries.jl / doe_record_errors.jl).

include(joinpath(pwd(), "scripts", "bmopf", "doe_robust.jl"))     # make_net, ts_doe, re_realised, customer_cables

const GEN_LABEL_HEADER = "sid,truth,records_doe_kW,records_binding,records_status,true_doe_kW,true_binding,true_status,gap_kW,pv_cap_kW,issued_full_V,issued_full_n_over_253,issued_full_curtail_kW,issued_sun_V,issued_sun_n_over_253,issued_sun_curtail_kW,seconds,error"

# sc: (sid, pu, pv, loads = [(load, P_kW, Q_kvar), ...]); truths: [(name, [segment ids that are really 4 mm2]), ...]
function gen_one(sc, truths)
    t0 = time()
    function loaded()
        net = make_net(sc.pu)
        for (ld, p, q) in sc.loads
            l = net["load"][ld]
            l["p_nom"] = fill(1000.0 * p, length(l["p_nom"]))
            l["q_nom"] = fill(1000.0 * q, length(l["q_nom"]))
        end
        return net
    end
    rows = String[]
    try
        kw_r, b_r, _, st_r = ts_doe(loaded())
        pvc = isfinite(kw_r) ? min(kw_r, PV_KW * sc.pv) : NaN
        for (tname, ids) in truths
            tnet = loaded()
            for id in ids
                tnet["line"][id]["linecode"] = RE_SMALL_LC
            end
            kw_t, b_t, st_t = if isempty(ids)
                kw_r, b_r, st_r
            else
                k, b, _, s = ts_doe(tnet); (k, b, s)
            end
            full = re_realised(tnet, kw_r)
            sun  = re_realised(tnet, pvc)
            push!(rows, @sprintf("%d,%s,%.6f,%s,%s,%.6f,%s,%s,%.6f,%.6f,%.4f,%d,%.6f,%.4f,%d,%.6f,%.1f,",
                                 sc.sid, tname, kw_r, b_r, st_r, kw_t, b_t, st_t, kw_r - kw_t, pvc,
                                 full.v, full.n_over, full.curtail_kW, sun.v, sun.n_over, sun.curtail_kW,
                                 time() - t0))
        end
    catch err
        msg = first(replace(sprint(showerror, err), "," => " ", "\n" => " ", "\"" => "'"), 150)
        rows = [@sprintf("%d,%s,,,,,,,,,,,,,,,%.1f,\"%s\"", sc.sid, tname, time() - t0, msg) for (tname, _) in truths]
    end
    return rows
end
