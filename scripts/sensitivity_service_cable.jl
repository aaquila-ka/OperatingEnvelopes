# =============================================================================
# sensitivity_service_cable.jl: how far do LV3 voltages move if service-cable records are wrong?
#
# What it does (plain English): loads LV3 in OpenDSS, then replaces the
#   ugsc_16cu service-cable line code (22 segments) by scaled copies with the
#   self resistance multiplied by 1.0 / 1.16 / 1.35 / 2.0 / 3.065 / 5.0 (and
#   reactance scaled gently in step), re-solves, and records how much the
#   phase-to-neutral voltages change, over all LV nodes and at the 12
#   customer connection points. Factor 1.0 is a control (should change ~0).
#   This is a power flow sensitivity only; no DOEs are computed here.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss
# Outputs:  results/sensitivity_service_cable.csv; prints the operating point,
#           baseline statistics and one line per factor
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/sensitivity_service_cable.jl")
#   The MASTER and OUTCSV paths below are hard-coded to C:\thesis\OperatingEnvelopes;
#   edit them if the repo is elsewhere.
# Used for: the go/no-go decision to use service-cable impedance error as the
#   thesis perturbation; early exploration, not a numbered REPRODUCE.md step.
#   The saved results/sensitivity_service_cable.csv comes from an earlier
#   model state (source 1.07 pu, PV connected phase-to-ground, transformer
#   star point on ground: max_V about 266 V and 163-164 of 165 nodes above
#   253 V in every row). scripts/notes/worklog.md records that these numbers
#   must be regenerated; a rerun with the current Master.dss (1.00 pu) gives
#   different values.
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
#
# PURPOSE
#   Answer the go/no-go question: if the service cable records are wrong,
#   how far do the customer voltages actually move?
#
# WHY
#   Cable impedance error is only worth choosing as the thesis perturbation
#   parameter if the network responds to it. Kumarawadu et al. (2025) found
#   30% RANDOM impedance error moved voltages by only 0.37 V, because random
#   errors partly cancel along a feeder. A SYSTEMATIC error (a whole cable
#   type mis-recorded) should not cancel: every segment shifts the same way,
#   so the error accumulates down the feeder. This script tests that.
#
# WHAT IS PERTURBED
#   Only the ugsc_16cu service cables (22 of the 46 cable segments in LV3).
#   Only the DIAGONAL (self) resistance terms are scaled.
#
#   The off-diagonal (mutual) R terms are left ALONE. Reason: across the whole
#   Linecodes.dss catalogue the mutual R is 0.0150 ohm/kft = 0.0493 ohm/km for
#   every single cable type, from 4 mm2 to 400 mm2. That is the Carson
#   earth-return resistance (9.869e-4 x f = 0.04935 ohm/km at 50 Hz). It is
#   set by frequency and soil, not by the conductor, so it must not change
#   when the conductor type changes.
#
#   Reactance is scaled separately and much more gently (self and mutual
#   together), because X depends on conductor geometry and does shift modestly
#   between cable types.
#
# THE REAL SWAP BEING MODELLED
#   Record says: ugsc_16cu_xlpe/nyl/pvc_ug_4w   R_self 0.454302 ohm/kft
#   Reality is:  uglv_4cu_xlpe/pvc_ug_4w        R_self 1.3926   ohm/kft
#   => R factor 3.065, X factor 1.048
#   i.e. the asset record names a 16 mm2 copper service, but the cable in the
#   ground is 4 mm2. Both types exist in this network's own catalogue, so the
#   confusion is one a real utility record could plausibly contain.
#
# METHOD NOTE 1 (why linecodes are swapped, not matrices edited)
#   An earlier version read Lines.RMatrix(), scaled it and wrote it back. That
#   is NOT a no-op even at a scale factor of 1.0: the linecodes are defined in
#   ohm/kft while the lines are in km, so the round trip silently rescales the
#   impedance (control row showed 0.083 V mean error at factor 1.0). This
#   version defines a new linecode with the scaled values and points the
#   affected lines at it by name, letting OpenDSS handle the units. That is
#   also a truer model of the error being studied: an asset record naming the
#   wrong cable type.
#
# METHOD NOTE 2 (why customer nodes are reported separately)
#   LV3 has 165 LV phase nodes but only 12 customers. A service cable affects
#   only the house at its end, so a mean taken over all 165 nodes is dominated
#   by ~153 nodes that barely move, and understates the effect by roughly an
#   order of magnitude. DOEs are issued at customer connection points, so the
#   customer-node statistics are the ones that matter. Both are reported.
#
# METHOD NOTE 3 (why PV output is checked)
#   Voltage rise is driven by export current through the service cable. If the
#   snapshot has little or no PV generation, the currents are small and so is
#   any impedance error effect. The script prints total PV output so the
#   operating point behind the numbers is always visible.
#
# OUTPUT
#   results/sensitivity_service_cable.csv
#
# HOW TO RUN
#   include("scripts/sensitivity_service_cable.jl")
#
# Author: Aaquila Konnimera Akbar
# =============================================================================

using OpenDSSDirect, DataFrames, CSV, Statistics

const MASTER = raw"C:\thesis\OperatingEnvelopes\data\networks\LV3_55bus_withPV\Master.dss"
const OUTCSV = raw"C:\thesis\OperatingEnvelopes\results\sensitivity_service_cable.csv"

const TARGET = "ugsc_16cu_xlpe/nyl/pvc_ug_4w_bundled"   # cable type to perturb

# Voltage nodes above this are on the 11 kV side, not the LV feeder. In LV3
# these are the 3 phase nodes of sourcebus (skipped anyway, as it has no
# neutral node 4) and the 3 phase nodes of b804 (transformer 11 kV side),
# about 6351 V at 1.00 pu (6795 V at 1.07 pu). Including them makes the mean
# and standard deviation meaningless, so they are excluded from all statistics.
const LV_CEILING = 400.0

# R multipliers to test. 3.065 is the real 16cu -> 4cu swap; the others
# bracket it so we get a curve rather than a single point. 1.0 is a CONTROL:
# it must produce essentially zero voltage change. A residual of order 1e-3 V
# is expected, from writing matrix values out as decimal text.
const R_FACTORS = [1.0, 1.16, 1.35, 2.0, 3.065, 5.0]

# Tolerance for the control check. Not 0, because the linecode is rebuilt from
# text and loses a little precision. 0.01 V is ~0.2% of the 4.58 V baseline
# spread seen at the time (that spread was later traced to the transformer
# star point being tied to ground; see worklog), and far below anything the
# thesis reports.
const CONTROL_TOL = 0.01

# X scales far less than R between cable types, so it gets its own factor.
# For the 16cu -> 4cu swap: X factor = 0.264871 / 0.252757 = 1.048 (self X).
# The mutual X terms of the two line codes differ by about 1.074-1.076, so
# scaling the whole X matrix by 1.048 is an approximation of the real swap.
const X_FACTOR_AT_SWAP = 1.048
const R_FACTOR_AT_SWAP = 3.065


"""
    load_circuit(master)

Load an OpenDSS network file and solve it.

OBSERVED BEHAVIOUR WORKED AROUND
  In OpenDSSDirect v0.9.9 on Julia 1.9.4, the first Solve() after a
  Clear + Redirect reports Converged() == true but leaves every node voltage
  at exactly zero. Discard that solve, reload, and solve again. Because
  Converged() still reports true here, we check the voltages themselves via @assert.
"""
function load_circuit(master)
    dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()
    dss("Clear"); dss("Redirect \"$master\""); Solution.Solve()
    @assert maximum(abs.(Circuit.AllBusVolts())) > 0 "warm-up failed: all voltages zero"
    return nothing
end


"""
    pv_summary() -> (n, total_kW, total_kvar)

Report how many PVSystems exist and what they are producing at the current
operating point. Negative kW in OpenDSS convention means power flowing INTO
the circuit, i.e. exporting.
"""
function pv_summary()
    n = 0
    kw = 0.0
    kvar = 0.0
    i = PVsystems.First()
    while i > 0
        n += 1
        kw   += PVsystems.kW()
        kvar += PVsystems.kvar()
        i = PVsystems.Next()
    end
    return n, kw, kvar
end


"""
    customer_nodes() -> Set{String}

Return the set of "bus.phase" node names that have a customer (Load) on them.
These are the connection points where a DOE would actually be issued, and
where a service cable error has its direct effect.
"""
function customer_nodes()
    s = Set{String}()
    i = Loads.First()
    while i > 0
        # CktElement follows whichever element was last made active.
        Circuit.SetActiveElement("Load." * Loads.Name())
        for b in CktElement.BusNames()
            bus = lowercase(split(b, '.')[1])
            for node in split(b, '.')[2:end]
                node in ("1", "2", "3") && push!(s, bus * "." * node)
            end
        end
        i = Loads.Next()
    end
    return s
end


"""
    phase_to_neutral() -> Dict{String,Float64}

Return LV phase-to-neutral voltage magnitudes, keyed by "bus.phase".

Circuit.AllBusVolts() returns phase-to-GROUND complex voltages. Phase-to-
neutral is obtained by subtracting the bus's own neutral (node 4) phasor.
The supervisors agreed that phase-to-neutral is the quantity
this thesis reports, so every voltage number must come through this function.

Nodes above LV_CEILING are on the 11 kV side and are excluded.
"""
function phase_to_neutral()
    names = Circuit.AllNodeNames()      # e.g. "b1044.1", "b1044.4"
    volts = Circuit.AllBusVolts()       # complex, same order as names

    # First pass: record each bus's neutral phasor.
    neutral = Dict{String,ComplexF64}()
    for (i, nm) in enumerate(names)
        parts = split(lowercase(nm), '.')
        length(parts) == 2 || continue
        parts[2] == "4" && (neutral[parts[1]] = volts[i])
    end

    # Second pass: phase node minus its own bus's neutral.
    out = Dict{String,Float64}()
    for (i, nm) in enumerate(names)
        parts = split(lowercase(nm), '.')
        length(parts) == 2 || continue
        bus, node = parts
        node in ("1", "2", "3") || continue
        haskey(neutral, bus) || continue
        v = abs(volts[i] - neutral[bus])
        v < LV_CEILING || continue      # skip the 11 kV source-side nodes
        out[nm] = v
    end
    return out
end


"""
    capture_baseline_z() -> Dict

Record every line's original cable type (and its R and X matrices, for
reference) so that each perturbation is decided from the ORIGINAL network
rather than from an already-perturbed one. Without this, once a line's
linecode has been swapped we would no longer be able to tell which lines
were originally service cables.
"""
function capture_baseline_z()
    z = Dict{String,Tuple{Matrix{Float64},Matrix{Float64},String}}()
    i = Lines.First()
    while i > 0
        z[Lines.Name()] = (copy(Lines.RMatrix()), copy(Lines.XMatrix()), Lines.LineCode())
        i = Lines.Next()
    end
    return z
end


"""
Map an OpenDSS unit code to the keyword OpenDSS expects in a definition.
LineCodes.Units() returns an enum (OpenDSSDirect.Lib.LineUnits) rather than
an Int, so convert before indexing.
Codes: 0=none, 1=mi, 2=kft, 3=km, 4=m, 5=ft, 6=in, 7=cm.
"""
unit_string(u) = ("none", "mi", "kft", "km", "m", "ft", "in", "cm")[Int(u) + 1]


"""
    make_scaled_linecode(source, newname, rfac, xfac) -> String

Define a new OpenDSS linecode derived from `source`, with the DIAGONAL (self)
resistance scaled by `rfac` and the whole reactance matrix scaled by `xfac`.
The new linecode keeps the source's phase count and units, so no unit
conversion happens anywhere in this script.
"""
function make_scaled_linecode(source::String, newname::String,
                              rfac::Float64, xfac::Float64)
    LineCodes.Name(source)
    R     = copy(LineCodes.Rmatrix())
    X     = copy(LineCodes.Xmatrix())
    n     = LineCodes.Phases()
    units = LineCodes.Units()

    for k in 1:size(R, 1)               # diagonal (self) terms only
        R[k, k] *= rfac
    end
    X = X .* xfac                       # self and mutual together

    # OpenDSS matrix literal: lower triangle, rows separated by |, values by
    # spaces. Row r contributes its first r entries.
    fmt(M) = "[" * join([join(string.(M[r, 1:r]), " ") for r in 1:size(M, 1)], " | ") * "]"

    dss("New Linecode.$newname nphases=$n units=$(unit_string(units)) " *
        "Rmatrix=$(fmt(R)) Xmatrix=$(fmt(X))")
    return newname
end


"""
    assign_linecode!(z0, target, newcode) -> Int

Point every line that ORIGINALLY used `target` at `newcode` instead, and
return how many lines were changed. Membership is decided from the captured
baseline z0, so repeated calls do not compound and always act on the same
set of lines.
"""
function assign_linecode!(z0, target::String, newcode::String)
    n_hit = 0
    i = Lines.First()
    while i > 0
        name = Lines.Name()
        if z0[name][3] == target
            Lines.LineCode(newcode)
            n_hit += 1
        end
        i = Lines.Next()
    end
    return n_hit
end


"""
    run_sweep() -> DataFrame

Solve the clean baseline, then solve once per R factor, comparing
phase-to-neutral voltages node by node against the baseline. Statistics are
reported twice: over all LV nodes, and over customer connection points only.

Wrapped in a function so the loop variables are function-local. A bare
top-level loop in Julia creates a new local scope and cannot assign to
globals, which silently breaks iteration.
"""
function run_sweep()
    load_circuit(MASTER)
    z0 = capture_baseline_z()

    npv, pvkw, pvkvar = pv_summary()
    println("OPERATING POINT")
    println("  PVSystems: ", npv)
    # Sign note: PVsystems.kW() is the PV output, which OpenDSS normally
    # reports as POSITIVE when generating; check the printed sign rather than
    # relying on the "(negative = exporting)" label.
    println("  total P:   ", round(pvkw, digits=2), " kW  (negative = exporting)")
    println("  total Q:   ", round(pvkvar, digits=2), " kvar")
    if abs(pvkw) < 1.0
        println("  *** WARNING: PV output is near zero. Voltage-rise effects")
        println("      will be small regardless of impedance error. ***")
    end
    println()

    cust   = customer_nodes()
    base   = phase_to_neutral()
    keys_s = sort(collect(keys(base)))     # fixed order so comparisons line up
    base_v = [base[k] for k in keys_s]

    # Index positions of the customer connection points within keys_s.
    cidx = [i for (i, k) in enumerate(keys_s) if k in cust]

    println("BASELINE (phase-to-neutral)")
    println("  all LV nodes:   ", length(base_v),
            "  mean ", round(mean(base_v), digits=2),
            "  sd ",   round(std(base_v),  digits=2),
            "  min ",  round(minimum(base_v), digits=2),
            "  max ",  round(maximum(base_v), digits=2), " V")
    if !isempty(cidx)
        bc = base_v[cidx]
        println("  customer nodes: ", length(bc),
                "  mean ", round(mean(bc), digits=2),
                "  sd ",   round(std(bc),  digits=2),
                "  min ",  round(minimum(bc), digits=2),
                "  max ",  round(maximum(bc), digits=2), " V")
    else
        println("  *** WARNING: no customer nodes matched. Check bus naming. ***")
    end
    println("  n > 253 V:      ", count(>(253), base_v))
    println()

    rows = DataFrame(r_factor=Float64[], x_factor=Float64[], n_lines_hit=Int[],
                     mean_dV_all=Float64[],  max_dV_all=Float64[],
                     mean_dV_cust=Float64[], max_dV_cust=Float64[],
                     max_V=Float64[], n_over_253=Int[])

    for rfac in R_FACTORS
        # Interpolate the X factor in step with R, so mild cases are mild in
        # both. At rfac = 3.065 this returns exactly the real 16cu -> 4cu
        # X factor of 1.048.
        xfac = 1.0 + (X_FACTOR_AT_SWAP - 1.0) *
                     (rfac - 1.0) / (R_FACTOR_AT_SWAP - 1.0)

        # Build a derived linecode for this severity and point the service
        # cables at it. The name encodes the factor so results are traceable.
        newcode = "pert_r" * replace(string(rfac), "." => "p")
        make_scaled_linecode(TARGET, newcode, rfac, xfac)
        n_hit = assign_linecode!(z0, TARGET, newcode)

        Solution.Solve()
        @assert maximum(abs.(Circuit.AllBusVolts())) > 0 "solve returned zeros at rfac=$rfac"

        pv = phase_to_neutral()
        v  = [pv[k] for k in keys_s]
        d  = abs.(v .- base_v)
        dc = isempty(cidx) ? [0.0] : d[cidx]

        push!(rows, (rfac, round(xfac, digits=4), n_hit,
                     mean(d), maximum(d), mean(dc), maximum(dc),
                     maximum(v), count(>(253), v)))

        println("R x", rpad(rfac, 6),
                " | all: mean ",  lpad(round(mean(d),  digits=3), 7),
                " max ",          lpad(round(maximum(d), digits=3), 7),
                " | CUSTOMER: mean ", lpad(round(mean(dc), digits=3), 7),
                " max ",          lpad(round(maximum(dc), digits=3), 7),
                " | n>253V ",     lpad(count(>(253), v), 4))
    end

    return rows
end


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

rows = run_sweep()

println()
println(rows)

# Control check: scaling by 1.0 must change essentially nothing. A residual of
# order 1e-3 V is expected because the linecode is rebuilt from decimal text.
ctrl = rows[rows.r_factor .== 1.0, :]
if nrow(ctrl) == 1
    resid = ctrl.max_dV_all[1]
    pass  = resid < CONTROL_TOL
    println("\nCONTROL (R x 1.0) max|dV| = ", round(resid, digits=6), " V  ",
            pass ? "PASS (below $(CONTROL_TOL) V text-precision tolerance)" :
                   "*** FAIL - do not trust the other rows ***")
end

mkpath(dirname(OUTCSV))
CSV.write(OUTCSV, rows)
println("\nwritten to ", OUTCSV)