# runOpenDSS.jl: solve the LV3 street in OpenDSS and plot voltage against distance
#
# Adapted from data/LV9_258bus/run_LV9.jl in Frederik Geth's GPSTTopic82024
# repository (BSD 3-Clause, Copyright 2025 Frederik Geth). Changes I made:
#   - reads the LV3 export file (lv3_55bus_EXP_VOLTAGES.csv) instead of the LV9 one;
#   - adds `export powers` to the OpenDSS commands;
#   - adds a commented-out cd() line for running from the parent folder;
#   - drops buses above 1000 V (the 11 kV side) before plotting;
#   - small whitespace changes.
# It is only an early look at the model, not used for any thesis result.
#
# Original licence notice (kept as required by the BSD 3-Clause licence):
#
# Copyright 2025 Frederik Geth
#
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this list of
#    conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice, this list of
#    conditions and the following disclaimer in the documentation and/or other materials
#    provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors may be used
#    to endorse or promote products derived from this software without specific prior
#    written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

using OpenDSSDirect
const ODSS = OpenDSSDirect
using DataFrames
using CSV
using Plots
# cd("LV3_55bus_withPV/")
file = "Master.dss"
odssstring = """
clear
compile $file
solve
export voltages
export powers
"""
dss(odssstring)
voltages_file= "lv3_55bus_EXP_VOLTAGES.csv"

##
voltages_df = CSV.read(voltages_file, DataFrame)
voltages_df[!,:Bus] = lowercase.(voltages_df[!,:Bus])
voltages_df

vpn(pm,pa,nm,na) = hypot(pm*exp(im*pa/180*pi) - nm*exp(im*na/180*pi))

voltages_df[!,:Van] = vpn.(voltages_df[!,Symbol(" Magnitude1")], voltages_df[!,Symbol(" Angle1")], voltages_df[!,Symbol(" Magnitude4")], voltages_df[!,Symbol(" Angle4")])
voltages_df[!,:Vbn] = vpn.(voltages_df[!,Symbol(" Magnitude2")], voltages_df[!,Symbol(" Angle2")], voltages_df[!,Symbol(" Magnitude4")], voltages_df[!,Symbol(" Angle4")])
voltages_df[!,:Vcn] = vpn.(voltages_df[!,Symbol(" Magnitude3")], voltages_df[!,Symbol(" Angle3")], voltages_df[!,Symbol(" Magnitude4")], voltages_df[!,Symbol(" Angle4")])


##
busdistances = ODSS.Circuit.AllBusDistances()
busnames = ODSS.Circuit.AllBusNames()
busdistancesdf = DataFrame(Bus=busnames, busdistances=busdistances)
sort!(busdistancesdf, [:busdistances])
busdist_dict = Dict(busdistancesdf.Bus[i] => busdistancesdf.busdistances[i] for i in 1:nrow(busdistancesdf))
CSV.write("busdistances.csv", busdistancesdf)


##
voltages_df = innerjoin(voltages_df, busdistancesdf, on=:Bus)
sort!(voltages_df,[:busdistances])
filter!(row -> row[Symbol(" Magnitude1")] <= 1000, voltages_df)

##
scatter(voltages_df.busdistances, voltages_df[!,Symbol(" Magnitude1")], label="phase a")
scatter!(voltages_df.busdistances, voltages_df[!,Symbol(" Magnitude2")], label="phase b")
scatter!(voltages_df.busdistances, voltages_df[!,Symbol(" Magnitude3")], label="phase c")
xlabel!("Electrical distance from distribution tranformer (km)")
ylabel!("Voltage magnitude to ground (V)")
savefig("volt_distance_drop_ground.pdf")

##
scatter(voltages_df.busdistances, voltages_df.Van, label="phase a")
scatter!(voltages_df.busdistances, voltages_df.Vbn, label="phase b")
scatter!(voltages_df.busdistances, voltages_df.Vcn, label="phase c")
xlabel!("Electrical distance from distribution tranformer (km)")
ylabel!("Voltage magnitude to neutral (V)")
savefig("volt_distance_drop_neutral.pdf")

##
scatter(voltages_df.busdistances, voltages_df[!,Symbol(" Magnitude4")],label="neutral")
xlabel!("Electrical distance from distribution tranformer (km)")
ylabel!("Neutral voltage rise (V)")
savefig("volt_distance_drop_ground_neutral.pdf")