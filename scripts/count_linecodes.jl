# =============================================================================
# count_linecodes.jl
#
# PURPOSE
#   Find out which cable types the LV3_55bus_withPV network actually uses,
#   how many segments use each, and how much total length each accounts for.
#
# WHY THIS MATTERS
#   The thesis perturbs cable impedance records. To do that we first need to
#   know what is in the network's cable catalogue and which entries are really
#   in use. The Linecodes.dss file lists 22 cable types, but a network only
#   uses a handful. Perturbing an unused type would do nothing.
#
# OUTPUT
#   results/linecode_usage.csv
#
# HOW TO RUN
#   From the Julia REPL, with the project activated:
#       include("scripts/count_linecodes.jl")
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

KNOWN BUG BEING WORKED AROUND
  In OpenDSSDirect v0.9.9 on Julia 1.9.4, the first Solve() after a
  Clear + Redirect reports Converged() == true but leaves every node voltage
  sitting at exactly zero. The circuit is loaded but the solution is empty.

  The fix is to throw that first solve away, Clear and Redirect again, then
  solve for real. Because Converged() lies in this situation, we must check
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

# Sanity checks on the loaded circuit. max |V| should be about 6795 V, which
# is 11 kV / sqrt(3) x 1.07, confirming the source is wired as expected.
println("converged: ", Solution.Converged())
println("max |V|:   ", round(maximum(abs.(Circuit.AllBusVolts())), digits=1))
println("n lines:   ", Lines.Count())
println("n buses:   ", Circuit.NumBuses())
println("n nodes:   ", Circuit.NumNodes())
println()

rows = linecode_usage()
println(rows)

println("\ntotal switches: ", sum(rows.n_switches))
println("real cable segments: ", Lines.Count() - sum(rows.n_switches))

mkpath(dirname(OUT))                   # create results/ if it does not exist
CSV.write(OUT, rows)
println("\nwritten to ", OUT)