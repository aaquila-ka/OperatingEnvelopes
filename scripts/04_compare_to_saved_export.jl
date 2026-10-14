# =============================================================================
# 04_compare_to_saved_export.jl: voltage statistics from a SAVED OpenDSS export
#
# What it does (plain English): reads the voltage export file saved earlier in
#   the network folder (written by runOpenDSS.jl), keeps the 55 LV buses and
#   prints phase-to-ground and phase-to-neutral statistics (mean, sd, min,
#   max, count above 253 V) and the neutral voltage range.
#   It does NOT solve the network: there is no new solve in this script, only
#   the saved file is read (OpenDSSDirect is loaded but not used).
#   The saved export reflects an earlier model state: source bus 6795.41 V
#   (= 1.07 pu), transformer star point tied to ground and PV connected
#   phase-to-ground (see scripts/notes/worklog.md). It does not match the
#   current Master.dss (1.00 pu, star point on the neutral, PV phase-to-neutral).
#
# Phase-to-ground: |V_phase| relative to earth
# Phase-to-neutral: |V_phase - V_neutral| as phasors
# These differ on a four-wire model because the neutral is
# not at earth potential.
# The code assumes columns Node1..Node4 are nodes 1, 2, 3, 4 in that order;
# this holds for all 55 LV rows of the saved file.
#
# Inputs:   data/networks/LV3_55bus_withPV/lv3_55bus_EXP_VOLTAGES.csv
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/04_compare_to_saved_export.jl")
# Used for: early exploration, not used for thesis results
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
# =============================================================================

using OpenDSSDirect, DataFrames, CSV, Statistics

net = joinpath(@__DIR__, "..", "data", "networks", "LV3_55bus_withPV")

df = CSV.read(joinpath(net, "lv3_55bus_EXP_VOLTAGES.csv"),
              DataFrame; normalizenames = true)

# Keep LV only (drops the 11 kV source bus)
lv = filter(r -> r.Magnitude1 <= 1000, df)
println("LV buses in saved export: ", nrow(lv))

# Phasor subtraction: magnitude of (phase - neutral)
vpn(pm, pa, nm, na) = abs(pm * exp(im * deg2rad(pa)) - nm * exp(im * deg2rad(na)))

pg = vcat(lv.Magnitude1, lv.Magnitude2, lv.Magnitude3)
pn = vcat(vpn.(lv.Magnitude1, lv.Angle1, lv.Magnitude4, lv.Angle4),
          vpn.(lv.Magnitude2, lv.Angle2, lv.Magnitude4, lv.Angle4),
          vpn.(lv.Magnitude3, lv.Angle3, lv.Magnitude4, lv.Angle4))

for (label, v) in (("PHASE-TO-GROUND", pg), ("PHASE-TO-NEUTRAL", pn))
    println()
    println("--- ", label, " (n = ", length(v), ") ---")
    println("  Mean: ", round(mean(v), digits=2), "  Sd: ", round(std(v), digits=2))
    println("  Min:  ", round(minimum(v), digits=2), "  Max: ", round(maximum(v), digits=2))
    println("  Above 253 V: ", count(>(253.0), v), " of ", length(v))
end

println()
println("Neutral magnitude: mean ", round(mean(lv.Magnitude4), digits=2),
        " V, range ", round(minimum(lv.Magnitude4), digits=2),
        " to ", round(maximum(lv.Magnitude4), digits=2), " V")