# ============================================================
# 04_compare_to_saved_export.jl
# Compares today's solve against the OpenDSS export saved in
# April 2026, and computes BOTH phase-to-ground and
# phase-to-neutral statistics.
#
# Phase-to-ground: |V_phase| relative to earth
# Phase-to-neutral: |V_phase - V_neutral| as phasors
# These differ on a four-wire model because the neutral is
# not at earth potential.
# ============================================================

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