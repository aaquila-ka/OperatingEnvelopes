# ============================================================
# 01_load_and_solve.jl
# Purpose: load the LV3_55bus_withPV network and run one
#          power flow. This is a smoke test - it proves the
#          model loads and OpenDSS converges before we do
#          anything clever with it.
# ============================================================

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
println("Circuit name:    ", Circuit.Name())
println("Number of buses: ", Circuit.NumBuses())
println("Number of nodes: ", Circuit.NumNodes())
println("Total power (kW, kvar): ", Circuit.TotalPower())