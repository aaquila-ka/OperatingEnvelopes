# =============================================================================
# doe_clean_snapshot.jl: correct ("clean") DOEs on the true LV3 network, 1 kW snapshot
#
# What it does (plain English):
#   Computes the answer key: the equal export limit for all 12 customers on LV3 with
#   correct cable records, original CSIRO loads (1 kW, power factor 0.88 per house),
#   207-253 V phase-to-neutral at customer connections, AS/NZS 4777.2 inverters.
#   Done at source 1.00 pu (original) and 1.03 pu. Prints a per-house table and what
#   limits export (inverter rating, voltage, or 5 kW nameplate).
# Inputs:   includes doe_common.jl (which loads load_lv3.jl and the LV3 .dss files)
# Outputs:  results/doe_clean_snapshot.csv (source_pu, house, export_limit_kW, status; 24 rows)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/doe_clean_snapshot.jl")   (calls run_clean_snapshot() itself)
# Used for: REPRODUCE.md step 3; 4.906 kW at 1.00 pu, 4.529 kW at 1.03 pu (both inverter-limited)
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by
#           Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_common.jl"))

# run_clean_snapshot(): the answer key. Solve the equal DOE (DOE = export limit every home gets) on
# the TRUE street with correct cable records, at 1.00 pu and 1.03 pu (pu = grid voltage relative to
# normal, so 1.03 = 3% high). Writes one CSV row per home per voltage
function run_clean_snapshot()
    rows = String[]
    println("\nLIMIT_MODE = $LIMIT_MODE   loads = original CSIRO (1 kW, pf 0.88)")
    for pu in (1.00, 1.03)
        # Fresh LV3 street at this source voltage, with the 207-253 V phase-to-neutral limits on the
        # 12 homes
        net = make_net(pu)
        # The 12 solar connection points (each may export up to 5 kW)
        cps = connection_points(net)
        # Solve the bound-point (basic) equal DOE: checked only with everyone exporting at once
        r   = doe(net, cps)
        println("\n================ CLEAN, source $(pu) pu ================")
        println("solver: $(r.termination_status[1])   feasible: $(r.diagnostics[1]["feasible"])")
        @printf("total export allowed: %.2f kW\n", r.total_capacity[1] / 1000)
        # Only if the solve found an answer: print the highest home voltage and the highest
        # anywhere, then the per-home table and what limits export (REPRODUCE.md: 4.906 kW at 1.00
        # pu, 4.529 kW at 1.03 pu, both limited by the 5 kVA inverter)
        if isfinite(r.total_capacity[1])
            vc, wc = max_pn(r.snapshots[1]; only = customer_points(net))
            va, wa = max_pn(r.snapshots[1])
            @printf("highest V at a customer: %.2f V (%s)   anywhere: %.2f V (%s)\n", vc, wc, va, wa)
            house_report(r.snapshots[1], net, r)
        end
        # One CSV row per home: source pu, home id, its limit in kW (envelope is in W, so / 1000),
        # solver status
        for cp in cps
            push!(rows, @sprintf("%.2f,%s,%.6f,%s", pu, cp.id, r.envelope[cp.id][1] / 1000, r.termination_status[1]))
        end
    end
    # Write all 24 rows (12 homes x 2 voltages) to the CSV
    open(joinpath(pwd(), "results", "doe_clean_snapshot.csv"), "w") do io
        println(io, "source_pu,house,export_limit_kW,status")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_clean_snapshot.csv")
end

# Runs as soon as the file is included
run_clean_snapshot()