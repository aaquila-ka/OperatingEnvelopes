# =============================================================================
# lv9_verify_diag.jl: why the phase-secure check and the realised reading disagree on LV9
#
# What it does (plain English):
#   For the LV9 phase-secure DOE (2.445 kW at 0.94 pu) and the pattern "only phases b and c
#   export", it solves the same case two ways and compares them customer by customer:
#     A = verify_operating_envelope (export fixed at the DOE, 253 V limit imposed)
#     B = realised reading (export up to the DOE, maximised; no voltage limit imposed)
#   For every customer it lists inverter P and Q, phase-to-neutral and neutral voltage, and
#   the solver statuses. Result so far: A curtails one inverter (ld2984) to 2347 W where B
#   gives 2445 W (253.00 vs 253.21 V). Suspected cause: solver tolerance at the 1 MW power
#   base, still to be confirmed (REPRODUCE.md known issue 20).
# Inputs:   includes lv9_common.jl (-> the LV9 network) and phase_secure_core.jl
# Outputs:  results/lv9/lv9_verify_diag.csv (one row per customer); prints the largest
#           differences
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/lv9/lv9_verify_diag.jl")   then   run_lv9_verify_diag()   (~2 min)
# Used for: REPRODUCE.md step 33 and known issue 20
# Credits:  CSIRO LV9 data (CC BY-NC-SA 4.0, copy shipped with BMOPFTools b7aa9a1);
#           BMOPFTools.jl and PowerOptLab.jl by Frederik Geth; Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "lv9", "lv9_common.jl"))
include(joinpath(pwd(), "scripts", "bmopf", "phase_secure_core.jl"))

# realised reading, but return the whole result (snapshot) as well
function realised_full(net, caps)
    ev = deepcopy(net)
    for b in values(ev["bus"]), k in ("vpn_min", "vpn_max", "vpg_min", "vpg_max", "v_min", "v_max", "vm_min", "vm_max")
        delete!(b, k)
    end
    cps = [ConnectionPoint(id = cp.id, bus = cp.bus, phase_terminals = cp.phase_terminals,
                           neutral = cp.neutral, export_max = max(1000.0 * caps[cp.id], 1.0),
                           ibr_id = cp.ibr_id) for cp in connection_points(ev)]
    return solve_operating_envelope(ev, cps; fairness = :max_total, direction = :export,
                                    security = :bound_point, solver_options = OPTS)
end

getpq(snap, net, id) = begin
    inv = net["ibr"][id]; g = snap["ibr"][id][String(inv["terminal_map"][1])]
    (Float64(g["pg"]), Float64(g["qg"]))
end
getv(snap, cp) = begin
    key = haskey(snap["bus"], cp.bus) ? cp.bus : lowercase(cp.bus)
    ts = snap["bus"][key]; ph = cp.phase_terminals[1]
    (vpn(ts, ph), abs(complex(ts["n"]["vr"], ts["n"]["vi"])))
end

function run_lv9_verify_diag(; pu = 0.94, kw = 2.445, pattern = "bc")
    net = make_net(pu)
    cps = connection_points(net)
    j = findfirst(==(pattern), PS_PATTERNS)
    u = ps_patterns(cps)[j]
    caps_w = Dict(cp.id => 1000.0 * kw for cp in cps)
    # A: verify
    ev = verify_operating_envelope(net, cps, caps_w; utilizations = [u], solver_options = OPTS)
    dA = ev.diagnostics[1]
    @printf("A verify: feasible %s, termination %s, primal %s\n", ev.feasible[1], ev.termination_status[1],
            get(dA, "primal_status", "?"))
    println("A diagnostics keys: ", join(sort(collect(keys(dA))), ", "))
    for k in ("minimum_margins", "minimum_margin_locations", "binding_constraints")
        haskey(dA, k) && println("  ", k, ": ", dA[k])
    end
    snapA = ev.snapshots[1]
    haskey(snapA, "bus") || (println("A snapshot has no bus results (infeasible?) - stopping"); return)
    # B: realised
    caps_kw = Dict(cp.id => u[i] * kw for (i, cp) in enumerate(cps))
    rB = realised_full(net, caps_kw)
    snapB = rB.snapshots[1]
    @printf("B realised: termination %s, total export %.3f kW\n", string(rB.termination_status[1]),
            rB.total_capacity[1] / 1000)
    # per-customer comparison
    rows = String[]
    sumA = zeros(2); sumB = zeros(2)
    worstA = (-Inf, ""); worstB = (-Inf, "")
    for (i, cp) in enumerate(cps)
        pA, qA = getpq(snapA, net, cp.id); pB, qB = getpq(snapB, net, cp.id)
        vA, nA = getv(snapA, cp);          vB, nB = getv(snapB, cp)
        sumA .+= (pA, qA); sumB .+= (pB, qB)
        vA > worstA[1] && (worstA = (vA, "$(cp.bus) $(cp.phase_terminals[1])"))
        vB > worstB[1] && (worstB = (vB, "$(cp.bus) $(cp.phase_terminals[1])"))
        push!(rows, @sprintf("%s,%s,%s,%.0f,%.6g,%.6g,%.4f,%.4f,%.6g,%.6g,%.4f,%.4f", cp.id, cp.bus,
                             cp.phase_terminals[1], u[i], pA, qA, vA, nA, pB, qB, vB, nB))
    end
    @printf("totals  A: P %.6g  Q %.6g   |  B: P %.6g  Q %.6g   (units as stored in the snapshot)\n",
            sumA[1], sumA[2], sumB[1], sumB[2])
    @printf("highest customer phase-neutral V:  A %.3f V at %s   |   B %.3f V at %s\n",
            worstA[1], worstA[2], worstB[1], worstB[2])
    # the 8 customers with the biggest voltage difference
    diffs = sort([(abs(parse(Float64, split(r, ",")[11]) - parse(Float64, split(r, ",")[7])), r) for r in rows]; rev = true)
    println("\nlargest V differences (B - A):")
    println("  customer           bus     ph u |   P_A      Q_A     V_A    Vn_A |   P_B      Q_B     V_B    Vn_B")
    for (_, r) in diffs[1:min(8, end)]
        f = split(r, ",")
        @printf("  %-18s %-7s %s  %s | %8.4g %8.4g %7.2f %6.2f | %8.4g %8.4g %7.2f %6.2f\n",
                f[1], f[2], f[3], f[4], parse(Float64, f[5]), parse(Float64, f[6]), parse(Float64, f[7]),
                parse(Float64, f[8]), parse(Float64, f[9]), parse(Float64, f[10]), parse(Float64, f[11]),
                parse(Float64, f[12]))
    end
    open(joinpath(pwd(), "results", "lv9", "lv9_verify_diag.csv"), "w") do io
        println(io, "customer,bus,phase,utilisation,P_verify,Q_verify,Vpn_verify_V,Vneutral_verify_V,P_realised,Q_realised,Vpn_realised_V,Vneutral_realised_V")
        foreach(l -> println(io, l), rows)
    end
    println("\nwritten results/lv9/lv9_verify_diag.csv")
end
