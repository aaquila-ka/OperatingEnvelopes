# scripts/bmopf/lv9/lv9_check.jl
#
# STEP f3: load LV9 into BMOPFTools, run analyze(), compute the clean equal DOE at one source
# voltage, then check the network physics independently in OpenDSS: the 123 inverter outputs
# (P and Q from the BMOPF DOE solution) are pinned as fixed generators in OpenDSS (PVSystems and
# InvControl disabled), and the phase-to-neutral voltages of all LV buses are compared.
#
# RUN (fresh Julia, from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> include("scripts/bmopf/lv9/lv9_check.jl")
#   julia> run_lv9_check(1.00)          # LV9 1.00 pu ~ LV3 1.025 pu (same LV voltage)
#   julia> run_lv9_check(1.00; ideal_switches = true)   # OpenDSS switches made ideal, like BMOPF
# OUTPUT results/lv9/analyze_lv9.txt, results/lv9/lv9_check.csv

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
using OpenDSSDirect
const ODD = OpenDSSDirect

const NODE = Dict("a" => 1, "b" => 2, "c" => 3, "n" => 4)

function opendss_pinned(snap, net, pu; ideal_switches = false)
    master = joinpath(LV9_DIR, "Master.dss")
    for pass in 1:2                                   # warm-up: first solve can return zeros
        ODD.Text.Command("clear")
        ODD.Text.Command("redirect \"$master\"")
        ODD.Text.Command("Vsource.source.pu=$pu")
        ODD.Text.Command("batchedit PVSystem..* enabled=false")
        ODD.Text.Command("InvControl.invall.enabled=false")
        for (id, inv) in net["ibr"]
            ph = String(inv["terminal_map"][1])
            g  = snap["ibr"][id][ph]
            ODD.Text.Command(@sprintf("new generator.g_%s phases=1 bus1=%s.%d.4 kv=0.230 kw=%.6f kvar=%.6f model=1 vminpu=0.1 vmaxpu=2",
                                      id, inv["bus"], NODE[ph], g["pg"] / 1000, g["qg"] / 1000))
        end
        ideal_switches && ODD.Text.Command("batchedit line.switch_.* r1=1e-7 x1=1e-7 r0=1e-7 x0=1e-7 c1=0 c0=0")
        ODD.Text.Command("set controlmode=off")
        ODD.Solution.Solve()
    end
    @assert ODD.Solution.Converged() "OpenDSS did not converge"
    @assert maximum(abs.(ODD.Circuit.AllBusVolts())) > 1.0 "OpenDSS voltages are zero (warm-up bug)"
    out = Dict{Tuple{String,String},Float64}()
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

function run_lv9_check(pu = 1.00; ideal_switches = false)
    t0 = time()
    mkpath(joinpath(pwd(), "results", "lv9"))
    net = make_net(pu)
    io = IOBuffer(); render(analyze(load_lv9()), io); txt = String(take!(io))
    write(joinpath(pwd(), "results", "lv9", "analyze_lv9.txt"), txt)
    println("==== analyze() LV9 ====")
    foreach(println, filter(l -> occursin(r"Findings|\[ERROR\]", l), split(txt, "\n")))
    @printf("customers %d, service segments %d (customer cables %d)\n",
            length(net["load"]), length(service_ids(net)), length(customer_cables(net)))

    kw, b, v, st, r = eq_doe(net)
    @printf("\nclean equal DOE at %.3f pu (LV3-equivalent %.3f pu): %.3f kW per customer, %s-limited, max customer %.2f V [%s]\n",
            pu, pu * LV9_EQUIV, kw, b, v, st)
    snap = r.snapshots[1]

    dss, loss = opendss_pinned(snap, net, pu; ideal_switches = ideal_switches)
    ideal_switches && println("\n(OpenDSS switches made ideal: r = x = 1e-7, to match BMOPFTools' ideal switches)")
    rows = String[]; dmax = 0.0; dsum = 0.0; worst = ""
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
    open(joinpath(pwd(), "results", "lv9", ideal_switches ? "lv9_check_idealsw.csv" : "lv9_check.csv"), "w") do io
        println(io, "bus,phase,bmopf_vpn_V,opendss_vpn_V,diff_V")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/lv9/analyze_lv9.txt and results/lv9/lv9_check.csv  (%.0f s)\n", time() - t0)
end
