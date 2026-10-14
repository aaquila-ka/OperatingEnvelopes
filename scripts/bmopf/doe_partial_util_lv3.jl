# =============================================================================
# doe_partial_util_lv3.jl: part-export check of the LV3 dropout-secure DOE
#
# What it does (plain English):
#   The dropout check only tried on/off export (each customer at 0 % or 100 % of its limit).
#   Here each customer exports a RANDOM fraction of the dropout-secure DOE (0 to 100 %),
#   read with the realised reading (Volt-VAr, Volt-Watt and 5 kVA kept, no voltage limit).
#   If no random point goes above 253 V, the on/off check was not hiding a worse in-between
#   case at this operating point. Three kinds of seeded random points: uniform fractions,
#   "mostly on or off" fractions (Beta(0.3, 0.3)), and one phase silent with the other two
#   phases at random fractions.
# Inputs:   includes doe_dropout_records_lv3.jl (-> the LV3 network, profiles and helpers);
#           needs results/doe_dropout_secure_lv3.csv (REPRODUCE.md step 26)
# Outputs:  results/doe_partial_util_lv3.csv; prints the worst point per setting
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`, fresh session):
#   using Logging; disable_logging(Logging.Warn)
#   include("scripts/bmopf/doe_partial_util_lv3.jl")   then   run_partial_util_lv3()
#   (2 settings x 300 points, about 2 min)
# Used for: REPRODUCE.md step 32 (0 of 300 above 253 V; worst 252.92 V snapshot,
#           252.82 V at 12:00)
# Credits:  CSIRO LV3 data (CC BY-NC-SA 4.0); BMOPFTools.jl and PowerOptLab.jl by Frederik
#           Geth; Team-Nando OE1-Ideal profiles (BSD-3, AusNet smart-meter data); Ipopt
# =============================================================================

include(joinpath(pwd(), "scripts", "bmopf", "doe_dropout_records_lv3.jl"))   # rec_issued_kw, do_net, ...

# Beta(a, a) sample without extra packages (ratio of two Gamma draws via Marsaglia-Tsang)
# Random Gamma(a) number (Marsaglia-Tsang method); used only to build Beta numbers below
function pu_gamma(rng, a)
    # For a < 1, use the standard trick: draw Gamma(a + 1) and multiply by U^(1/a), U uniform 0..1
    a < 1 && return pu_gamma(rng, a + 1) * rand(rng)^(1 / a)
    # Marsaglia-Tsang: propose v from a normal number, accept it with the test below, otherwise try again
    d = a - 1 / 3; c = 1 / sqrt(9d)
    while true
        x = randn(rng); v = (1 + c * x)^3
        v <= 0 && continue
        u = rand(rng)
        log(u) < 0.5x^2 + d - d * v + d * log(v) && return d * v
    end
end
# Beta(a, a) = g1 / (g1 + g2) with two Gamma(a) numbers; with a = 0.3 most values are near 0 or near 1
pu_beta(rng, a) = (g1 = pu_gamma(rng, a); g2 = pu_gamma(rng, a); g1 / (g1 + g2))

# Main run: for each setting, n random part-export points at the dropout-secure DOE (the safer DOE that also stays safe
# when 1-2 homes or a whole phase stop exporting); counts points above 253 V and writes the CSV
function run_partial_util_lv3(; pu = RE_PU, n = 300, seed = 20261014)
    t0 = time()
    P, Q, pv = read_profiles()
    pmap = profile_map(make_net(pu), P)
    rows = String[]
    for setting in DO_SETTINGS
        # The dropout-secure DOE (kW, same for every home) read from results/doe_dropout_secure_lv3.csv
        kw = rec_issued_kw(setting, pu)
        # The street for this setting (records = truth here: all 16 mm2, with the setting's loads)
        net0 = do_net(setting, pu, pmap, P, Q)
        cps = connection_points(net0)
        ids = [cp.id for cp in cps]
        # Which phase each home is on ('a', 'b' or 'c')
        ph  = Dict(cp.id => cp.phase_terminals[1][1] for cp in cps)
        # One random generator per setting with a fixed seed, so the same points come out every run
        rng = MersenneTwister(seed)
        worst = (-Inf, "", ""); nfail = 0
        @printf("\n=== %s, %.3f pu: dropout-secure DOE %.3f kW, %d random partial-export points ===\n", setting, pu, kw, n)
        for k in 1:n
            # First third of the points: uniform fractions; second third: Beta(0.3, 0.3); last third: one phase silent
            kind = k <= n ÷ 3 ? "uniform" : k <= 2n ÷ 3 ? "beta0.3" : "phase_silent"
            # For "phase_silent", pick the phase whose homes export nothing
            silent = kind == "phase_silent" ? rand(rng, ('a', 'b', 'c')) : ' '
            # Each home's fraction (0 to 1) of the DOE for this point
            frac = Dict{eltype(ids),Float64}()
            for id in ids
                frac[id] = kind == "uniform" ? rand(rng) :
                           kind == "beta0.3" ? pu_beta(rng, 0.3) :
                           (ph[id] == silent ? 0.0 : rand(rng))
            end
            # Realised reading: homes export up to fraction x DOE with Volt-VAr / Volt-Watt (AS/NZS 4777.2 inverter rules)
            # and 5 kVA on, no voltage limit; then we read the highest customer voltage
            rv = fr_realised(do_net(setting, pu, pmap, P, Q), Dict(id => frac[id] * kw for id in ids))
            # FAIL if the highest customer voltage is above 253.005 V (253 V plus a tiny tolerance), or NaN (solve failed)
            fail = !(rv.v <= V_MAX_PN + 0.005)
            nfail += fail
            # The 12 fractions as text, in sorted home order, for the CSV and the worst-point printout
            fr = join([@sprintf("%.3f", frac[id]) for id in sort(ids)], " ")
            # Keep the worst (highest-voltage) point
            rv.v > worst[1] && (worst = (rv.v, kind, fr))
            # One CSV row per point
            push!(rows, @sprintf("%s,%.3f,%.6f,%d,%s,%.4f,%d,%s,%s", setting, pu, kw, k, kind, rv.v, rv.n_over,
                                 fail ? "FAIL" : "ok", fr))
            # Progress line every 100 points
            k % 100 == 0 && @printf("  %d done, worst so far %.3f V (%s), over 253 V: %d\n", k, worst[1], worst[2], nfail)
        end
        @printf("  worst %.3f V (%s); fractions (customers in sorted id order): %s\n", worst[1], worst[2], worst[3])
        @printf("  over 253 V: %d of %d\n", nfail, n)
    end
    open(joinpath(pwd(), "results", "doe_partial_util_lv3.csv"), "w") do io
        println(io, "setting,source_pu,dropout_secure_kW,point,kind,realised_V_VW,n_customers_over_253,result,fractions_sorted_ids")
        foreach(l -> println(io, l), rows)
    end
    @printf("\nwritten results/doe_partial_util_lv3.csv (%.0f min)\n", (time() - t0) / 60)
end
