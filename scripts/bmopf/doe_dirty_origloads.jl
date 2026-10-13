# scripts/bmopf/doe_dirty_origloads.jl
#
# PURPOSE (sensitivity check)
#   Repeat the clean/dirty DOE experiment with the ORIGINAL CSIRO loads
#   (Master.dss `batchedit load..* kw=1`, OpenDSS default pf 0.88; the same fix
#   Geth applies in PowerOptLab studies/australian_pv/prepare.jl) instead of my
#   edited Loads.dss values. If the conclusions hold for both load sets, the
#   result does not depend on the uncertain origin of my edited loads.
#
# RUN    julia> include("scripts/bmopf/doe_dirty_origloads.jl")
# OUTPUT results/doe_dirty_snapshot_origloads.csv

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