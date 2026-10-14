# =============================================================================
# prepare_lv9.jl: build the LV9 network folder used by every other LV9 script
#
# What it does (plain English): copies the CSIRO LV9 feeder (258 buses, 123 single-phase
#   customers) from the BMOPFTools test data and applies the same corrections as the LV3
#   network: every house load reset to the CSIRO default 1 kW / 0.539743 kvar (pf 0.88; the
#   BMOPFTools copy has 2 kW / 0.95 pf placeholders, see its Loads.dss), one 5 kVA / 5 kW
#   rooftop PV per customer connected phase-to-neutral (.x.4) with AS/NZS 4777.2 Australia A
#   Volt-VAr / Volt-Watt (one InvControl, same curves and tolerances as LV3), the transformer
#   LV star point on the neutral (wdg=2 bus=...1.2.3.4), and the source at sourcebus at
#   1.00 pu with a tiny metering line to the MV bus (as LV3).
# Inputs:   <BMOPFTools package>/test/data/LV/LV9_258bus/ (lines, Linecodes, Switches,
#           Groundings, Transformers, Loads .dss). Includes no other thesis script.
# Outputs:  data/networks/LV9_258bus_withPV/ (Master, lines, Linecodes, Switches, Groundings,
#           Transformers, Loads, PVSystems .dss); prints a short summary incl. the number of
#           16 mm2 service segments (179).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/lv9/prepare_lv9.jl")      (runs prepare_lv9() automatically)
# Used for: REPRODUCE.md step 19 (needed by steps 20-30); known issue 15 (the BMOPFTools
#           copy has two closed switches commented out, so LV9 is run radial).
# Credits:  CSIRO LV9 feeder data ("Realistic Australian MV feeder with associated LV
#           feeders" v1, doi 10.25919/ghnz-bk28, CC BY-NC-SA 4.0; copy shipped with
#           BMOPFTools b7aa9a1, test/data/LV/LV9_258bus); BMOPFTools.jl (b7aa9a1) and
#           PowerOptLab.jl (953e45c) by Frederik Geth; JuMP and Ipopt
# =============================================================================

using BMOPFTools

# Where the CSIRO LV9 files sit inside the installed BMOPFTools package, and where the new folder goes
const LV9_SRC = normpath(joinpath(dirname(pathof(BMOPFTools)), "..", "test", "data", "LV", "LV9_258bus"))
const LV9_DST = joinpath(pwd(), "data", "networks", "LV9_258bus_withPV")

# Build data/networks/LV9_258bus_withPV: copy the files, fix transformer and loads, add PVs, write Master.dss
function prepare_lv9()
    @assert isdir(LV9_SRC) "LV9 source folder not found: $LV9_SRC"
    mkpath(LV9_DST)
    # These four files are copied unchanged
    for f in ("lines.dss", "Linecodes.dss", "Switches.dss", "Groundings.dss")
        cp(joinpath(LV9_SRC, f), joinpath(LV9_DST, f); force = true)
    end

    # ---- transformer: LV star point on the neutral
    tx = read(joinpath(LV9_SRC, "Transformers.dss"), String)
    # Find the LV winding bus; if it has no conductor list, add .1.2.3.4 so the star point is on the neutral (4)
    m  = match(r"wdg=2 bus=(\S+)", tx)
    @assert m !== nothing "no wdg=2 bus= in Transformers.dss"
    lvbus = m[1]
    occursin(".", lvbus) || (tx = replace(tx, "wdg=2 bus=$lvbus " => "wdg=2 bus=$lvbus.1.2.3.4 "))
    @assert occursin("wdg=2 bus=$(split(lvbus, '.')[1]).1.2.3.4 ", tx) "transformer LV winding not on .1.2.3.4"
    write(joinpath(LV9_DST, "Transformers.dss"), tx)
    # The 11 kV bus of the transformer, used for the metering line below
    mvbus = match(r"wdg=1 bus=(\S+)", tx)[1]

    # ---- loads: CSIRO default 1 kW + 0.539743 kvar; collect (name, bus.ph.4)
    loads = Tuple{String,String,String}[]
    # Read each load's name, bus (with phase and neutral) and kV from the original file
    for line in eachline(joinpath(LV9_SRC, "Loads.dss"))
        mm = match(r"^new load\.(\S+)\s+phases=1\s+bus1=(\S+)\s+kv=(\S+)"i, line)
        mm === nothing && continue
        push!(loads, (mm[1], mm[2], mm[3]))
    end
    @assert length(loads) == 123 "expected 123 loads in LV9, found $(length(loads))"
    @assert all(endswith(b, ".4") for (_, b, _) in loads) "a load is not phase-to-neutral"
    # Write the loads again at 1 kW / 0.539743 kvar
    open(joinpath(LV9_DST, "Loads.dss"), "w") do io
        println(io, "! CSIRO LV9 loads reset to the dataset default (batchedit kw=1, pf 0.88) as for LV3")
        for (n, b, kv) in loads
            println(io, "new load.$n phases=1 bus1=$b kv=$kv kw=1 kvar=0.539743 vminpu=0.1 vmaxpu=2")
        end
    end

    # ---- PV systems with the LV3 inverter settings
    open(joinpath(LV9_DST, "PVSystems.dss"), "w") do io
        println(io, "// same curves and InvControl as LV3_55bus_withPV/PVSystems.dss (AS/NZS 4777.2 Australia A)")
        # Volt-VAr and Volt-Watt curves (AS/NZS 4777.2 inverter rules; x in pu of 230 V, pu = voltage
        # relative to normal). Volt-Watt cuts real power down to 20 % when voltage is high
        println(io, "New XYCurve.VoltVar npts=6 xarray=[0.1 0.9 0.9565217391304348 1.0434782608695652 1.1217391304347826 2] yarray=[0.44 0.44 0 0 -0.6 -0.6]")
        println(io, "New XYCurve.VoltWatt npts=4 xarray=[0.1 1.1 1.1304347826086956 2] yarray=[1 1 0.2 0.2]")
        println(io, "New InvControl.invall CombiMode=VV_VW vvc_curve1=VoltVar voltwatt_curve=VoltWatt RefReactivePower=VARMAX_VARS VoltwattYAxis=PMPPPU")
        println(io)
        # One 5 kVA / 5 kW PV per home, on the same bus and phase as its load
        for (n, b, _) in loads
            println(io, "new PVSystem.$n phases=1 bus1=$b kv=0.230 kVA=5 Pmpp=5 irradiance=1 Temperature=25 %Cutin=0.0 %Cutout=0.0 model=1 vminpu=0.1 vmaxpu=2")
        end
        println(io)
        println(io, "Edit InvControl.invall VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6")
    end

    # ---- master (same structure as LV3)
    open(joinpath(LV9_DST, "Master.dss"), "w") do io
        # Ideal 11 kV source at 1.00 pu, 50 Hz
        println(io, "new circuit.lv9_258bus angle=-30.0000000000 basekv=11.0000000000 pu=1.00 phases=3 bus1=sourcebus model=ideal")
        println(io)
        println(io, "set defaultbasefrequency=50.0000000000")
        println(io, "set basefrequency=50.0000000000")
        println(io)
        for f in ("Linecodes.dss", "lines.dss", "Loads.dss", "Transformers.dss", "Switches.dss", "Groundings.dss", "PVSystems.dss")
            println(io, "redirect $f")
        end
        println(io)
        # Tiny (0.0001 km) line from the source to the 11 kV bus, so an energy meter can sit on it
        println(io, "new line.for_energymeter lineCode=ughv_400al_triplex_ug_4w_bundled bus1=sourcebus.1.2.3.0 bus2=$(mvbus).1.2.3.4 length=0.0001 units=km phases=4")
        println(io, "New EnergyMeter.Source     Element= line.for_energymeter  Terminal=1")
        println(io)
        println(io, "Set MaxControlIter=100")
        println(io, "Set tolerance=0.00001")
    end
    # Count the 16 mm2 lines (expected 179) and print a summary
    nsvc = count(l -> occursin("ugsc_16cu", l), eachline(joinpath(LV9_DST, "lines.dss")))
    println("LV9 prepared in $LV9_DST")
    println("  source data: $LV9_SRC")
    println("  MV bus $mvbus, LV bus $lvbus (now .1.2.3.4), 123 loads at 1 kW / 0.539743 kvar, 123 PVs (5 kVA)")
    println("  16 mm2 service segments: $nsvc")
end

# Running this file builds the folder straight away
prepare_lv9()
