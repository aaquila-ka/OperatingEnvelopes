# scripts/bmopf/doe_clean_snapshot.jl
#
# Clean DOEs (answer key) on corrected LV3, original CSIRO loads, equal allocation,
# 207-253 V phase-to-neutral at customer connections, AS/NZS 4777.2 inverters.
# Source 1.00 pu (original) and 1.03 pu.
# RUN    julia> include("scripts/bmopf/doe_clean_snapshot.jl")
# OUTPUT results/doe_clean_snapshot.csv

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))

function run_clean_snapshot()
    rows = String[]
    println("\nLIMIT_MODE = $LIMIT_MODE   loads = original CSIRO (1 kW, pf 0.88)")
    for pu in (1.00, 1.03)
        net = make_net(pu)
        cps = connection_points(net)
        r   = doe(net, cps)
        println("\n================ CLEAN, source $(pu) pu ================")
        println("solver: $(r.termination_status[1])   feasible: $(r.diagnostics[1]["feasible"])")
        @printf("total export allowed: %.2f kW\n", r.total_capacity[1] / 1000)
        if isfinite(r.total_capacity[1])
            vc, wc = max_pn(r.snapshots[1]; only = customer_points(net))
            va, wa = max_pn(r.snapshots[1])
            @printf("highest V at a customer: %.2f V (%s)   anywhere: %.2f V (%s)\n", vc, wc, va, wa)
            house_report(r.snapshots[1], net, r)
        end
        for cp in cps
            push!(rows, @sprintf("%.2f,%s,%.6f,%s", pu, cp.id, r.envelope[cp.id][1] / 1000, r.termination_status[1]))
        end
    end
    open(joinpath(pwd(), "results", "doe_clean_snapshot.csv"), "w") do io
        println(io, "source_pu,house,export_limit_kW,status")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_clean_snapshot.csv")
end

run_clean_snapshot()