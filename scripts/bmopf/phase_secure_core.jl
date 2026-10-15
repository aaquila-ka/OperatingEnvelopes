# =============================================================================
# phase_secure_core.jl: shared code for the phase-secure equal DOE
#
# What it does (plain English):
#   A normal ("bound-point") DOE is only checked with every customer exporting at once.
#   The phase-secure DOE is the highest equal export limit that also stays within the
#   voltage limits when one or two whole phases export nothing. It tests 7 patterns
#   (all export; only b and c; a and c; a and b; only a; only b; only c) with PowerOptLab's
#   verify_operating_envelope and finds the limit by bisection between 0 and the
#   bound-point DOE.
# Inputs:   nothing on disk; needs connection_points and OPTS from doe_common.jl
#           (directly or through lv9/lv9_common.jl) to be loaded first
# Outputs:  none (returns numbers to the calling script)
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   not run on its own; it is included by doe_phase_secure.jl, doe_dropout_lv3.jl,
#   lv9/lv9_phase_secure.jl and lv9/lv9_dropout.jl, e.g.
#   include("scripts/bmopf/doe_phase_secure.jl")   then   run_phase_secure_lv3()
# Used for: REPRODUCE.md steps 18 and 24 (phase-secure DOEs), also used in 25-26 and 29
# Credits:  PowerOptLab.jl (verify_operating_envelope) and BMOPFTools.jl by Frederik Geth; Ipopt
# =============================================================================
# DOE = export limit every home gets; bound-point (basic) DOE = checked only with everyone
# exporting.
# The 7 phase patterns say which phases export: "abc" = everyone, "bc" = homes on phase a export
# nothing, and so on
const PS_PATTERNS = ["abc", "bc", "ac", "ab", "a", "b", "c"]

# ps_patterns: for each pattern, a list with 1.0 for a home on an exporting phase and 0.0 for a home
# on a silent phase (how much of its limit each home uses in that pattern)
function ps_patterns(cps)
    [[(cp.phase_terminals[1][1] in pat) ? 1.0 : 0.0 for cp in cps] for pat in PS_PATTERNS]
end

# is an equal limit of kw safe (all customer limits met, inverter laws kept) for ALL 7 patterns?
# ev.feasible has one entry per time step, not per pattern: PowerOptLab 953e45c solves all 7
# patterns together in one model, so feasible[1] = true only if every pattern is feasible.
function ps_feasible(net, cps, kw)
    # The same limit (in W) for every home
    caps = Dict(cp.id => 1000.0 * kw for cp in cps)
    # Check all 7 patterns at once; the network's 207-253 V limits stay on, so feasible = no home
    # goes outside them in any pattern
    ev = verify_operating_envelope(net, cps, caps; utilizations = ps_patterns(cps), solver_options = OPTS)
    return ev.feasible[1]
end

# highest equal limit that is safe for all 7 patterns (bisection between 0 and the bound-point DOE)
# returns (limit in kW, number of bisection steps); 0 steps = the bound-point DOE is already safe.
# 10 steps narrow the answer to bound_kw / 1024 (about 4 W); the safe lower end is returned.
function ps_doe(net, bound_kw; iters = 10)
    cps = connection_points(net)
    # If the bound-point DOE already passes all 7 patterns, keep it (0 steps)
    ps_feasible(net, cps, bound_kw) && return bound_kw, 0
    lo, hi = 0.0, bound_kw
    # Bisection: try the middle; safe -> raise the floor (lo), unsafe -> lower the ceiling (hi)
    for it in 1:iters
        mid = (lo + hi) / 2
        ps_feasible(net, cps, mid) ? (lo = mid) : (hi = mid)
    end
    return lo, iters
end
