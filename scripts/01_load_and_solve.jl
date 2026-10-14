# =============================================================================
# 01_load_and_solve.jl: smoke test, load the LV3 feeder in OpenDSS and solve once
#
# What it does (plain English): loads the CSIRO LV3 network (Master.dss) into
#   OpenDSS, runs one power flow and prints whether it converged, plus a few
#   basic facts (circuit name, number of buses and nodes, total power). It is a
#   first check that the model loads before doing anything else with it.
#   It does not read voltages; for reading voltages see the "warm-up" solve
#   used in scripts 02-05.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss (and the .dss files it redirects to)
# Outputs:  printed only, no files written
# How to run (from the repo folder, in `julia +1.9 --project=.`; this is the
#   older top-level project, Julia 1.9.4 Manifest, not bmopf/):
#   include("scripts/01_load_and_solve.jl")
# Used for: early exploration, not used for thesis results
# Credits:  CSIRO LV3 network data (LV3_55bus_withPV); OpenDSS (EPRI) via OpenDSSDirect.jl
# =============================================================================

using OpenDSSDirect
using DataFrames

# --- Point at the network -----------------------------------
# @__DIR__ is the folder THIS script lives in. Building the
# path this way means the script works on any machine, not
# just one with C:\thesis on it.
network_dir = joinpath(@__DIR__, "..", "data", "networks", "LV3_55bus_withPV")
master_file = joinpath(network_dir, "Master.dss")

println("Loading network from: ", master_file)
println("File exists: ", isfile(master_file))

# --- Load and solve -----------------------------------------
# "Clear" wipes any previous circuit out of OpenDSS's memory.
# Skipping this is a classic source of confusing results,
# because OpenDSS keeps state between runs.
dss("Clear")
dss("Redirect \"$master_file\"")

Solution.Solve()

# --- Did it converge? ---------------------------------------
# ALWAYS check this. OpenDSS will happily hand you numbers
# from a failed solve without complaining.
println("Converged: ", Solution.Converged())

# --- Basic circuit facts ------------------------------------
# TotalPower follows the OpenDSS convention: it is the power at the
# source terminal, so power drawn from the source shows as NEGATIVE.
println("Circuit name:    ", Circuit.Name())
println("Number of buses: ", Circuit.NumBuses())
println("Number of nodes: ", Circuit.NumNodes())
println("Total power (kW, kvar): ", Circuit.TotalPower())