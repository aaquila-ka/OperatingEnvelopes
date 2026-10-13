# scripts/bmopf/doe_clean_snapshot.jl
#
# PURPOSE (Aim 2, first step)
#   Clean dynamic operating envelopes (DOEs) on the corrected LV3 network for one
#   snapshot: equal export limit for every customer, 207-253 V phase-to-neutral
#   limits, PVs keep their AS/NZS 4777.2 Volt-VAr/Volt-Watt law.
#   Run at source 1.00 pu (original CSIRO value) and 1.03 pu (Geth's second case).
#
# LIMIT_MODE
#   :customer -> 207-253 V applied only on each customer's own phase at their
#                connection bus (statutory point-of-supply view). DEFAULT.
#   :all      -> 207-253 V on every phase of every LV bus (conservative network
#                view). Kept as a sensitivity case.
#   Reason (13 Oct): with :all, the binding voltage was b1754 phase a, where no
#   customer is connected (neutral shift from unbalanced load), not PV export.
#
# TOOLS  BMOPFTools b7aa9a1 + PowerOptLab 953e45c (Julia 1.11, bmopf environment)
# RUN    julia> include("scripts/bmopf/doe_clean_snapshot.jl")
# OUTPUT results/doe_clean_snapshot.csv

using BMOPFTools, PowerOptLab, JuMP, Ipopt, Printf

include(joinpath(pwd(), "scripts", "bmopf", "load_lv3.jl"))   # load_lv3(); Master.dss is at 1.00 pu

const V_MIN_PN   = 207.0
const V_MAX_PN   = 253.0
const NO_LIMIT_HI = 1.0e4      # effectively no upper limit on a phase
const NO_LIMIT_LO = 0.0        # effectively no lower limit on a phase
const MV_BUSES   = ("sourcebus", "b804")          # 11 kV side: no LV limits there
const OPTS       = ("tol" => 1e-8, "max_iter" => 3000, "print_level" => 0)
const LIMIT_MODE = :customer   # :customer or :all

function scale_source!(net, pu)
    vs = only(values(net["voltage_source"]))
    vs["v_magnitude"] = Float64.(vs["v_magnitude"]) .* pu   # Master.dss is 1.00 pu, so factor = pu
    return net
end

# Set of (bus, phase) pairs where a customer is connected (from the loads).
customer_points(net) = Set((String(ld["bus"]), String(ld["terminal_map"][1])) for ld in values(net["load"]))

function add_pn_limits!(net; mode = LIMIT_MODE)
    for bid in MV_BUSES
        @assert haskey(net["bus"], bid) "expected MV bus $bid not found"
    end
    cust = customer_points(net)
    @assert length(cust) == 12 "expected 12 customer connection points, found $(length(cust))"
    nphase = 0
    for (bid, b) in net["bus"]
        bid in MV_BUSES && continue
        terms = String.(b["terminal_names"])
        "n" in terms || continue
        phases = [t for t in terms if t != "n"]
        if mode == :all
            b["vpn_min"] = fill(V_MIN_PN, length(phases))
            b["vpn_max"] = fill(V_MAX_PN, length(phases))
            nphase += length(phases)
        elseif mode == :customer
            any((bid, p) in cust for p in phases) || continue
            b["vpn_min"] = [((bid, p) in cust) ? V_MIN_PN : NO_LIMIT_LO for p in phases]
            b["vpn_max"] = [((bid, p) in cust) ? V_MAX_PN : NO_LIMIT_HI for p in phases]
            nphase += count(p -> (bid, p) in cust, phases)
        else
            error("unknown LIMIT_MODE $mode")
        end
    end
    return nphase
end

function connection_points(net; export_max = 5000.0)
    [ConnectionPoint(id = id, bus = String(inv["bus"]),
                     phase_terminals = [String(inv["terminal_map"][1])], neutral = "n",
                     export_max = export_max, ibr_id = id)
     for (id, inv) in sort(collect(net["ibr"]); by = first)]
end

# Highest phase-to-neutral voltage. only = nothing -> every LV phase;
# only = set of (bus, phase) -> just those points (e.g. customer connections).
function max_pn(snapshot, net; only = nothing)
    best, where = -Inf, ""
    for (bid, ts) in snapshot["bus"]
        bid in MV_BUSES && continue
        haskey(ts, "n") || continue
        vn = complex(ts["n"]["vr"], ts["n"]["vi"])
        for ph in ("a", "b", "c")
            haskey(ts, ph) || continue
            only === nothing || (bid, ph) in only || continue
            v = abs(complex(ts[ph]["vr"], ts[ph]["vi"]) - vn)
            v > best && (best = v; where = "$bid $ph-n")
        end
    end
    return best, where
end

function run_clean_snapshot()
    rows = String[]
    println("\nLIMIT_MODE = $LIMIT_MODE")
    for pu in (1.00, 1.03)
        net = load_lv3()
        scale_source!(net, pu)
        nlim = add_pn_limits!(net)
        cps  = connection_points(net)
        r = solve_operating_envelope(net, cps; fairness = :equal, direction = :export,
                                     security = :bound_point, solver_options = OPTS)
        status = r.termination_status[1]
        println("\n================ source $(pu) pu ================")
        println("phases with 207-253 V limits: $nlim   connection points: $(length(cps))")
        println("solver status: $status   feasible: $(r.diagnostics[1]["feasible"])")
        @printf("total export allowed: %.2f kW\n", r.total_capacity[1] / 1000)
        if isfinite(r.total_capacity[1])
            vc, wc = max_pn(r.snapshots[1], net; only = customer_points(net))
            va, wa = max_pn(r.snapshots[1], net)
            @printf("highest voltage at a customer connection: %.2f V at %s\n", vc, wc)
            @printf("highest voltage anywhere on the LV street: %.2f V at %s\n", va, wa)
        end
        println("  house               export limit (kW)")
        for cp in cps
            e = r.envelope[cp.id][1]
            @printf("  %-18s  %8.3f\n", cp.id, e / 1000)
            push!(rows, @sprintf("%s,%.2f,%s,%.6f,%s", LIMIT_MODE, pu, cp.id, e / 1000, status))
        end
    end
    open(joinpath(pwd(), "results", "doe_clean_snapshot_$(LIMIT_MODE).csv"), "w") do io
        println(io, "limit_mode,source_pu,house,export_limit_kW,status")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/doe_clean_snapshot_$(LIMIT_MODE).csv")
end

run_clean_snapshot()