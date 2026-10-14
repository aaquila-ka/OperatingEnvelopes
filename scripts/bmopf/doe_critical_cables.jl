# =============================================================================
# doe_critical_cables.jl: which service cables matter? One wrong cable at a time
#
# What it does (plain English):
#   One cable at a time: the record says 16 mm2 (catalogue) but THIS ONE segment is
#   really 4 mm2; the other 21 segments are correct. For each of the 22 segments it
#   computes the correct DOE, the over-promise of the issued (catalogue) DOE, the old
#   bound-point voltage, and the realised voltage with Volt-Watt on (customers may
#   export up to the issued DOE), customers above 253 V and curtailment.
#   Uses the same functions and settings as doe_record_errors.jl (1.03 pu, 1 kW
#   snapshot, equal allocation).
# Inputs:   includes doe_record_errors.jl (-> doe_common.jl -> load_lv3.jl)
# Outputs:  results/doe_critical_cables.csv (sorted, most harmful segment first;
#           `length` is in metres); prints a table and how many segments give > 1 %
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   include("scripts/bmopf/doe_critical_cables.jl")   then   run_critical_cables()
# Used for: REPRODUCE.md step 8 (12 of 22 segments matter; l_3432 alone gives the same
#           DOE as all 22 wrong, realised 254.60 V, 1 customer above 253 V)
# Credits:  CSIRO LV3 data and line codes (CC BY-NC-SA 4.0); BMOPFTools.jl and
#           PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_record_errors.jl"))

# Main run: for each of the 22 service segments, make ONLY that one 4 mm2 and see how wrong the
# issued DOE (DOE = the export limit every home gets) is there; writes the CSV, most harmful first
function run_critical_cables()
    t0 = time()
    # Issued DOE from the records (all 16 mm2, 1.03 pu); it is the same for every segment
    issued, _, _ = re_doe(make_net(RE_PU))
    # The 22 segment names, in sorted order
    ids = re_service_ids(make_net(RE_PU))
    @printf("issued DOE (records, all 16 mm2): %.3f kW\n\n", issued)
    println("segment            from -> to            length   correct kW  binding    over-promise   bound V   realised V(VW) >253V curtail kW")
    res = []
    for id in ids
        # Fresh true street with only this one segment made 4 mm2
        truth = make_net(RE_PU)
        l = truth["line"][id]
        l["linecode"] = RE_SMALL_LC
        # Correct DOE on that true street (the answer key)
        kw, b, st = re_doe(truth)
        # Bound-point reading: everyone exports exactly the issued DOE, Volt-Watt off
        # (Volt-Watt = AS/NZS 4777.2 inverter rule that cuts real power when voltage is high)
        v, note   = re_street(truth, issued)
        # Realised reading: homes export up to the issued cap with the inverter rules on, then we read the voltage
        rv        = re_realised(truth, issued)
        # How much too generous the records' limit is, in %: 100 x (issued / correct - 1)
        over = 100 * (issued / kw - 1)
        # The segment's end buses and length, just for the table
        fb = string(get(l, "bus_from", "?")); tb = string(get(l, "bus_to", "?"))
        len = get(l, "length", NaN)
        @printf("%-18s %-9s -> %-9s %8.4f   %8.3f    %-9s  %+8.1f %%   %7.2f%s  %7.2f        %3d   %6.3f\n",
                id, fb, tb, len, kw, b, over, v, note == "delivered" ? " " : "c", rv.v, rv.n_over, rv.curtail_kW)
        push!(res, (id = id, fb = fb, tb = tb, len = len, kw = kw, b = b, st = st,
                    over = over, v = v, note = note, rv = rv))
    end
    # Most harmful segment first (largest over-promise)
    sort!(res; by = r -> -r.over)
    # One CSV row per segment; gap_kW = issued - correct
    open(joinpath(pwd(), "results", "doe_critical_cables.csv"), "w") do io
        println(io, "segment,bus_from,bus_to,length,correct_kW,correct_binding,correct_status,issued_kW,gap_kW,overpromise_pct,boundpoint_V_noVW,boundpoint_note,realised_V_VW,n_customers_over_253,curtail_kW")
        for r in res
            @printf(io, "%s,%s,%s,%.6f,%.6f,%s,%s,%.6f,%.6f,%.3f,%.4f,%s,%.4f,%d,%.6f\n",
                    r.id, r.fb, r.tb, r.len, r.kw, r.b, r.st, issued, issued - r.kw, r.over, r.v, r.note,
                    r.rv.v, r.rv.n_over, r.rv.curtail_kW)
        end
    end
    # Count segments that on their own make the issued DOE more than 1 % too generous
    n_harm = count(r -> r.over > 1.0, res)
    @printf("\n%d of %d segments cause more than 1 %% over-promise on their own\n", n_harm, length(res))
    @printf("written results/doe_critical_cables.csv  (%.0f s)\n", time() - t0)
end
