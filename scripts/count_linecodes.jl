# =============================================================================
# count_linecodes.jl: which cable types (line codes) LV3 uses, how many segments, how long
#
# What it does (plain English): loads LV3 in OpenDSS, walks every Line object
#   and counts, per line code, the number of segments, how many are switches,
#   the total length and the length unit. The thesis perturbs cable impedance
#   records, so we first need to know which of the 22 cable types in
#   Linecodes.dss are really in use (perturbing an unused type does nothing).
#   Result: 22 service segments use ugsc_16cu (the cable type perturbed in the
#   thesis), 14 use uglv_240al, 11 use ughv_400al (10 short stubs plus the
#   0.1 m for_energymeter dummy line), and 8 switches have no line code.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss
# Outputs:  results/linecode_usage.csv (total_length in the line's length
#           unit, units code 3 = km); also prints circuit facts
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/count_linecodes.jl")
#   The MASTER and OUT paths below are hard-coded to C:\thesis\OperatingEnvelopes;
#   edit them if the repo is elsewhere.
# Used for: choosing the perturbation target (service cables, 16 mm2 vs 4 mm2);
#   background for REPRODUCE.md section 5 "Cable error"; not a numbered
#   REPRODUCE.md step
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
#
# Author: Aaquila Konnimera Akbar
# =============================================================================

# OpenDSSDirect drives the OpenDSS power flow engine from Julia.
# DataFrames gives us a table type. CSV writes that table to disk.
using OpenDSSDirect, DataFrames, CSV

# raw"..." stops Julia treating backslashes as escape characters, so Windows
# paths can be written normally instead of doubling every backslash.
const MASTER = raw"C:\thesis\OperatingEnvelopes\data\networks\LV3_55bus_withPV\Master.dss"
const OUT    = raw"C:\thesis\OperatingEnvelopes\results\linecode_usage.csv"


"""
    load_circuit(master)

Load an OpenDSS network file and solve it.

OBSERVED BEHAVIOUR WORKED AROUND
  In OpenDSSDirect v0.9.9 on Julia 1.9.4, the first Solve() after a
  Clear + Redirect reports Converged() == true but leaves every node voltage
  sitting at exactly zero. The circuit is loaded but the solution is empty.

  The fix is to throw that first solve away, Clear and Redirect again, then
  solve for real. Because Converged() still reports true in this situation, we must check
  the voltages themselves rather than trusting the convergence flag. That is
  what the @assert does.

  Every script in this project that loads a circuit must do this.
"""
function load_circuit(master)
    dss("Clear")                        # wipe any circuit already in memory
    dss("Redirect \"$master\"")         # read the network definition files
    Solution.Solve()                    # throwaway solve (returns zeros)

    dss("Clear")                        # wipe again
    dss("Redirect \"$master\"")         # reload
    Solution.Solve()                    # this one is real

    # Guard: if voltages are all zero the warm-up did not take. Fail loudly
    # here rather than silently producing meaningless results downstream.
    @assert maximum(abs.(Circuit.AllBusVolts())) > 0 "warm-up failed: all voltages zero"
    return nothing
end


"""
    linecode_usage() -> DataFrame

Walk every Line object in the loaded circuit and tally, per cable type:
  - how many line segments use it
  - how many of those are switches rather than real cable
  - the total length of those segments
  - the length units OpenDSS is using

WHY SWITCHES ARE COUNTED SEPARATELY
  OpenDSS represents switches as Line objects with no linecode and a token
  length. They are not cables and must not be perturbed, so we need to know
  how many of the "lines" are really switches.

WHY UNITS ARE RECORDED
  The Linecodes.dss file mixes units: most cable types are given in ohms per
  kft, but a couple are in ohms per km. Mixing them up introduces a silent
  factor of 3.28 error. Recording the units code makes the mistake visible.
  OpenDSS unit codes: 0 = none, 1 = miles, 2 = kft, 3 = km, 4 = m, 5 = ft,
  6 = inches, 7 = cm.
"""
function linecode_usage()
    # One dictionary per quantity, keyed by cable type name.
    counts   = Dict{String,Int}()      # segments per cable type
    lengths  = Dict{String,Float64}()  # total length per cable type
    units    = Dict{String,Int}()      # length units per cable type
    switches = Dict{String,Int}()      # of which are switches

    # OpenDSS iterates its object lists with a First/Next cursor rather than
    # handing back an array. First() moves to the first Line and returns its
    # index; Next() advances and returns the next index, or 0 when done.
    # All the Lines.X() calls below refer to whichever Line is currently active.
    i = Lines.First()
    while i > 0
        lc = Lines.LineCode()          # name of this segment's cable type

        # get(dict, key, default) returns the default when the key is not yet
        # present, which lets us accumulate without initialising every key first.
        counts[lc]   = get(counts,  lc, 0)   + 1
        lengths[lc]  = get(lengths, lc, 0.0) + Lines.Length()
        # Lines.Units() is the unit of this line's LENGTH (km for every line
        # in LV3), not the impedance unit of its line code (most line codes
        # in Linecodes.dss are in ohm/kft, two are in ohm/km).
        units[lc]    = Lines.Units()
        switches[lc] = get(switches, lc, 0) + (Lines.IsSwitch() ? 1 : 0)

        i = Lines.Next()               # advance; returns 0 at the end
    end

    # Assemble the dictionaries into one table, most-used cable type first.
    rows = DataFrame(linecode=String[], n_lines=Int[], n_switches=Int[],
                     total_length=Float64[], units=Int[])

    # sort(..., by = x -> -x[2]) sorts by count descending. x is a
    # (key, value) pair, so x[2] is the count, and negating it flips the order.
    for (k, v) in sort(collect(counts), by = x -> -x[2])
        push!(rows, (k, v, switches[k], lengths[k], units[k]))
    end

    return rows
end


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

load_circuit(MASTER)

# Sanity checks on the loaded circuit. max |V| is the 11 kV source phase
# voltage: about 6351 V (11 kV / sqrt(3) x 1.00) with the current Master.dss
# at 1.00 pu. The 6795 V noted in the worklog was with the source at 1.07 pu.
println("converged: ", Solution.Converged())
println("max |V|:   ", round(maximum(abs.(Circuit.AllBusVolts())), digits=1))
println("n lines:   ", Lines.Count())
println("n buses:   ", Circuit.NumBuses())
println("n nodes:   ", Circuit.NumNodes())
println()

rows = linecode_usage()
println(rows)

println("\ntotal switches: ", sum(rows.n_switches))
# Note: the count below (Lines minus switches = 47) still includes the
# 0.1 m for_energymeter dummy line (a meter connection, not a cable), so the
# real cable segments are 46.
println("real cable segments: ", Lines.Count() - sum(rows.n_switches))

mkpath(dirname(OUT))                   # create results/ if it does not exist
CSV.write(OUT, rows)
println("\nwritten to ", OUT)