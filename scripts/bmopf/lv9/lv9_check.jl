# =============================================================================
# lv9_check.jl: check the LV9 network model in BMOPFTools against OpenDSS
#
# What it does (plain English): runs BMOPFTools' analyze() on LV9, computes the clean equal
#   DOE at one source voltage, then rebuilds the same operating point in OpenDSS: the 123
#   inverter outputs (P and Q from the BMOPF DOE solution) are pinned as fixed generators
#   (PVSystems and InvControl disabled) and the phase-to-neutral voltages of all LV buses
#   (774 values) are compared. Option ideal_switches = true makes the OpenDSS switches
#   (1 mOhm in the dataset) near-ideal, matching BMOPFTools' ideal switches.
# Inputs:   data/networks/LV9_258bus_withPV/; includes lv9_common.jl; uses OpenDSSDirect.jl.
# Outputs:  results/lv9/analyze_lv9.txt, results/lv9/lv9_check.csv (default) or
#           results/lv9/lv9_check_idealsw.csv (ideal_switches = true); prints the DOE, the
#           voltage ranges, mean / max difference and OpenDSS losses. (The final "written"
#           message always names lv9_check.csv, also in the ideal-switch run.)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/lv9/lv9_check.jl")   then
#   run_lv9_check(1.00)                            # dataset switches (1 mOhm in OpenDSS)
#   run_lv9_check(1.00; ideal_switches = true)     # near-ideal switches in both tools
#   (LV9 1.00 pu gives the same transformer no-load voltage as LV3 1.025 pu)
# Used for: REPRODUCE.md step 20 (section 4 row "LV9 clean DOE"; known issue 16).
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt;
#           OpenDSS (EPRI) via OpenDSSDirect.jl
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
using OpenDSSDirect
const ODD = OpenDSSDirect

# OpenDSS numbers the conductors 1, 2, 3 for phases a, b, c and 4 for the neutral
const NODE = Dict("a" => 1, "b" => 2, "c" => 3, "n" => 4)

# Rebuild the same operating point in OpenDSS: same network, PV models and inverter rules switched off,
# and a fixed generator at each home with exactly the P and Q from the BMOPF solution.
# Returns the phase-to-neutral voltage at every LV (bus, phase) and the OpenDSS losses (W)
function opendss_pinned(snap, net, pu; ideal_switches = false)
    master = joinpath(LV9_DIR, "Master.dss")
    for pass in 1:2                                   # warm-up: first solve can return zeros
        ODD.Text.Command("clear")
        ODD.Text.Command("redirect \"$master\"")
        # Same source voltage as the BMOPF run (pu = grid voltage relative to normal)
        ODD.Text.Command("Vsource.source.pu=$pu")
        ODD.Text.Command("batchedit PVSystem..* enabled=false")
        ODD.Text.Command("InvControl.invall.enabled=false")
        # One fixed generator per home, between its phase and the neutral (.4), with BMOPF's P and Q (W -> kW)
        for (id, inv) in net["ibr"]
            ph = String(inv["terminal_map"][1])
            g  = snap["ibr"][id][ph]
            ODD.Text.Command(@sprintf("new generator.g_%s phases=1 bus1=%s.%d.4 kv=0.230 kw=%.6f kvar=%.6f model=1 vminpu=0.1 vmaxpu=2",
                                      id, inv["bus"], NODE[ph], g["pg"] / 1000, g["qg"] / 1000))
        end
        # Optional: make the 1 mOhm dataset switches near-ideal, like BMOPFTools' switches
        ideal_switches && ODD.Text.Command("batchedit line.switch_.* r1=1e-7 x1=1e-7 r0=1e-7 x0=1e-7 c1=0 c0=0")
        ODD.Text.Command("set controlmode=off")
        ODD.Solution.Solve()
    end
    # Stop if OpenDSS did not solve, or gave all-zero voltages
    @assert ODD.Solution.Converged() "OpenDSS did not converge"
    @assert maximum(abs.(ODD.Circuit.AllBusVolts())) > 1.0 "OpenDSS voltages are zero (warm-up bug)"
    out = Dict{Tuple{String,String},Float64}()
    # For every LV bus with a neutral: phase-to-neutral voltage (what a home feels) = |V phase - V neutral|
    for (bid, ts) in snap["bus"]
        bid in MV_BUSES && continue
        haskey(ts, "n") || continue
        ODD.Circuit.SetActiveBus(bid)
        nodes = ODD.Bus.Nodes(); V = ODD.Bus.Voltages()
        vn_i = findfirst(==(4), nodes); vn_i === nothing && continue
        for ph in ("a", "b", "c")
            haskey(ts, ph) || continue
            i = findfirst(==(NODE[ph]), nodes); i === nothing && continue
            out[(bid, ph)] = abs(V[i] - V[vn_i])
        end
    end
    return out, real(ODD.Circuit.Losses()[1])
end

# Compare BMOPF and OpenDSS on LV9 at one source voltage: save the analyze() report, print the
# clean DOE, then compare voltages with the same inverter outputs in both tools and write a CSV
function run_lv9_check(pu = 1.00; ideal_switches = false)
    t0 = time()
    mkpath(joinpath(pwd(), "results", "lv9"))
    net = make_net(pu)
    # Run BMOPFTools' analyze() on the network, save its report, print only findings and errors
    io = IOBuffer(); render(analyze(load_lv9()), io); txt = String(take!(io))
    write(joinpath(pwd(), "results", "lv9", "analyze_lv9.txt"), txt)
    println("==== analyze() LV9 ====")
    foreach(println, filter(l -> occursin(r"Findings|\[ERROR\]", l), split(txt, "\n")))
    @printf("customers %d, service segments %d (customer cables %d)\n",
            length(net["load"]), length(service_ids(net)), length(customer_cables(net)))

    # Clean equal DOE (DOE = export limit every home gets), checked only with everyone exporting (bound point)
    kw, b, v, st, r = eq_doe(net)
    @printf("\nclean equal DOE at %.3f pu (LV3-equivalent %.3f pu): %.3f kW per customer, %s-limited, max customer %.2f V [%s]\n",
            pu, pu * LV9_EQUIV, kw, b, v, st)
    snap = r.snapshots[1]

    # Same P and Q in OpenDSS, then compare the voltages point by point
    dss, loss = opendss_pinned(snap, net, pu; ideal_switches = ideal_switches)
    ideal_switches && println("\n(OpenDSS switches made ideal: r = x = 1e-7, to match BMOPFTools' ideal switches)")
    rows = String[]; dmax = 0.0; dsum = 0.0; worst = ""
    # Difference at each point; keep the sum (for the mean) and the largest one
    for ((bid, ph), vd) in sort(collect(dss); by = first)
        vb = vpn(snap["bus"][bid], ph)
        d  = abs(vb - vd); dsum += d
        d > dmax && (dmax = d; worst = "$bid $ph-n")
        push!(rows, @sprintf("%s,%s,%.4f,%.4f,%.4f", bid, ph, vb, vd, vb - vd))
    end
    @printf("\nOpenDSS check (same inverter P and Q pinned): %d LV phase-neutral values\n", length(dss))
    @printf("  BMOPF %.2f-%.2f V, OpenDSS %.2f-%.2f V\n",
            minimum(vpn(snap["bus"][k[1]], k[2]) for k in keys(dss)), maximum(vpn(snap["bus"][k[1]], k[2]) for k in keys(dss)),
            minimum(values(dss)), maximum(values(dss)))
    @printf("  |difference| mean %.4f V, max %.4f V (%s)\n", dsum / length(dss), dmax, worst)
    @printf("  OpenDSS losses %.1f W (includes switches and earthing, see LV3 loss note)\n", loss)
    # Write one row per (bus, phase): BMOPF V, OpenDSS V and the difference
    open(joinpath(pwd(), "results", "lv9", ideal_switches ? "lv9_check_idealsw.csv" : "lv9_check.csv"), "w") do io
        println(io, "bus,phase,bmopf_vpn_V,opendss_vpn_V,diff_V")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/analyze_lv9.txt and results/lv9/lv9_check.csv  (%.0f s)\n", time() - t0)
end
