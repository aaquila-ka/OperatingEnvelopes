# shared code for the phase-imbalance-secure equal DOE (included by doe_phase_secure.jl and
# lv9/lv9_phase_secure.jl after their own helpers; needs connection_points, OPTS,
# verify_operating_envelope, solve_operating_envelope)
const PS_PATTERNS = ["abc", "bc", "ac", "ab", "a", "b", "c"]

function ps_patterns(cps)
    [[(cp.phase_terminals[1][1] in pat) ? 1.0 : 0.0 for cp in cps] for pat in PS_PATTERNS]
end

# is an equal limit of kw safe (all customer limits met, inverter laws kept) for ALL 7 patterns?
function ps_feasible(net, cps, kw)
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    ev = verify_operating_envelope(net, cps, caps; utilizations = ps_patterns(cps), solver_options = OPTS)
    return ev.feasible[1]
end

# highest equal limit that is safe for all 7 patterns (bisection between 0 and the bound-point DOE)
function ps_doe(net, bound_kw; iters = 10)
    cps = connection_points(net)
    ps_feasible(net, cps, bound_kw) && return bound_kw, 0
    lo, hi = 0.0, bound_kw
    for it in 1:iters
        mid = (lo + hi) / 2
        ps_feasible(net, cps, mid) ? (lo = mid) : (hi = mid)
    end
    return lo, iters
end
