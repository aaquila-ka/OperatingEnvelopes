# =============================================================================
# doe_dirty_origloads.jl: older sensitivity check, Case A/B with the original CSIRO loads
#
# What it does (plain English):
#   Repeats the clean/dirty DOE experiment of doe_dirty_snapshot.jl with the ORIGINAL
#   CSIRO loads (Master.dss `batchedit load..* kw=1`, OpenDSS default power factor 0.88;
#   the same step Geth applies in PowerOptLab scripts/australian_pv/prepare.jl, a later
#   commit than the pinned 953e45c) instead of an earlier edited set of loads, to show
#   the conclusion does not depend on the load values.
# Inputs:   includes doe_dirty_snapshot.jl (which itself runs run_dirty_snapshot() again
#           and rewrites results/doe_dirty_snapshot.csv)
# Outputs:  results/doe_dirty_snapshot_origloads.csv
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/doe_dirty_origloads.jl")   (calls run_origloads() itself)
# Used for: not part of REPRODUCE.md (superseded: Loads.dss now holds the original
#           CSIRO loads, so doe_dirty_snapshot.jl already is this check)
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by
#           Frederik Geth; Ipopt
#
# REVIEW NOTES (state of this file):
#   - run_origloads() calls build_net(swapped = ...), but doe_dirty_snapshot.jl names
#     that helper make_dirty_net(swapped = ...), so the run stops there as written.
#   - The CSV header below has 5 columns; run_case() now returns 6 fields (it adds `note`).
#   - make_net() already checks every load is 1000 W / 539.743 var, so original_loads!()
#     changes nothing now.
#   - The existing results/doe_dirty_snapshot_origloads.csv comes from an earlier version
#     (Case A voltage NaN there; doe_dirty_snapshot.csv has 255.12 V counterfactual).
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_dirty_snapshot.jl"))   # helpers (also reruns edited-load case)

const ORIG_P_W   = 1000.0
const ORIG_Q_VAR = 1000.0 * tan(acos(0.88))     # 539.7 var

function original_loads!(net)
    for ld in values(net["load"])
        ld["p_nom"] = Any[ORIG_P_W]
        ld["q_nom"] = Any[ORIG_Q_VAR]
    end
    return net
end

function run_origloads()
    base    = original_loads!(build_net(swapped = false))   # 16 mm2 services
    swapped = original_loads!(build_net(swapped = true))    # 4 mm2 services
    @printf("\n######## ORIGINAL LOADS: 12 x %.0f W, %.1f var (pf 0.88) ########\n", ORIG_P_W, ORIG_Q_VAR)
    rows = String[]
    push!(rows, run_case("ORIG LOADS CASE A: truth 4 mm2, records say 16 mm2", swapped, base))
    push!(rows, run_case("ORIG LOADS CASE B: truth 16 mm2, records say 4 mm2", base, swapped))
    open(joinpath(pwd(), "results", "doe_dirty_snapshot_origloads.csv"), "w") do io
        println(io, "case,correct_limit_kW,wrong_records_limit_kW,real_max_vpn_V,where")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_dirty_snapshot_origloads.csv")
end

run_origloads()