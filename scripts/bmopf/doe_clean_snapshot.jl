# scripts/bmopf/doe_clean_snapshot.jl
#
# PURPOSE (Aim 2, first step)
#   Clean dynamic operating envelopes (DOEs) on the corrected LV3 network for one
#   snapshot: equal export limit for every customer, 207-253 V phase-to-neutral
#   limits, PVs keep their AS/NZS 4777.2 Volt-VAr/Volt-Watt law.
#   Run at source 1.00 pu (original CSIRO value) and 1.03 pu (Geth's second case).
#
# TOOLS  BMOPFTools b7aa9a1 + PowerOptLab 953e45c (Julia 1.11, bmopf environment)
# RUN    julia> include("scripts/bmopf/doe_clean_snapshot.jl")
# OUTPUT results/doe_clean_snapshot.csv

using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))   # load_lv3(); Master.dss is at 1.00 pu

const V_MIN_PN = 207.0
const V_MAX_PN = 253.0
const MV_BUSES = ("sourcebus", "b804")          # 11 kV side: no LV limits there
const OPTS     = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)

function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    vs["v_magnitude"] = Float64.(vs["v_magnitude"]) .* pu   # Master.dss is 1.00 pu, so factor = pu
    return net
end

function add_pn_limits!(net)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    n = 0
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        nph = count(!=("n"), terms)
        b["vpn_min"] = fill(V_MIN_PN, nph)
        b["vpn_max"] = fill(V_MAX_PN, nph)
        n += 1
    end
    return n
end

function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

function max_pn(snapshot, net)
    best, where = -Inf, ""
    for (bid, ts) in snapshot["bus"]
        bid in MV_BUSES && continue
        haskey(ts, "n") || continue
        vn = complex(ts["n"]["vr"], ts["n"]["vi"])
        for ph in ("a", "b", "c")
            haskey(ts, ph) || continue
            v = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - vn)
            v > best && (best = v; where = "$bid $ph-n")
        end
    end
    return best, where
end

function run_clean_snapshot()
    rows = String[]
    for pu in (1.00, 1.03)
        net = load_lv3()
        scale_source!(net, pu)
        nlim = add_pn_limits!(net)
        cps  = connection_points(net)
        r = solve_operating_envelope(net, cps; fairness = :equal, direction = :export,
                                     security = :bound_point, solver_options = OPTS)
        status = r.termination_status[1]
        println("\n================ source $(pu) pu ================")
        println("LV buses with 207-253 V limits: $nlim   connection points: $(length(cps))")
        println("solver status: $status   feasible: $(r.diagnostics[1]["feasible"])")
        @printf("total export allowed: %.2f kW\n", r.total_capacity[1] / 1000)
        if isfinite(r.total_capacity[1])
            vmax, where = max_pn(r.snapshots[1], net)
            @printf("highest phase-to-neutral voltage: %.2f V at %s\n", vmax, where)
        end
        println("  house               export limit (kW)")
        for cp in cps
            e = r.envelope[cp.id][1]
            @printf("  %-18s  %8.3f\n", cp.id, e / 1000)
            push!(rows, @sprintf("%.2f,%s,%.6f,%s", pu, cp.id, e / 1000, status))
        end
    end
    open(joinpath(pwd(), "results", "doe_clean_snapshot.csv"), "w") do io
        println(io, "source_pu,house,export_limit_kW,status")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_clean_snapshot.csv")
end

run_clean_snapshot()