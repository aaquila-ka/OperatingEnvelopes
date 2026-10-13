# scripts/bmopf/lv9/prepare_lv9.jl
#
# Build data/networks/LV9_258bus_withPV from the CSIRO LV9 feeder, with exactly the same
# corrections as LV3_55bus_withPV:
#   - loads reset to the CSIRO default 1 kW, 0.539743 kvar (pf 0.88); the copy shipped with
#     BMOPFTools b7aa9a1 has 2 kW / 0.95 pf placeholders added in July 2026 (see its Loads.dss)
#   - one 5 kVA / 5 kW PV per customer, phase-to-neutral (.x.4), AS/NZS 4777.2 Australia A
#     Volt-VAr / Volt-Watt via one InvControl (same curves and tolerances as LV3)
#   - transformer LV star point on the neutral (wdg=2 bus=...1.2.3.4)
#   - source at sourcebus, 1.00 pu, with a tiny metering line to the MV bus (as LV3)
# Source data: CSIRO "Realistic Australian MV feeder with associated LV feeders" v1,
# doi 10.25919/ghnz-bk28 (CC BY-NC-SA 4.0), copy in BMOPFTools b7aa9a1 test/data/LV/LV9_258bus.
#
# RUN (from C:\thesis\OperatingEnvelopes, julia +1.11 --project=bmopf)
#   julia> include("scripts/bmopf/lv9/prepare_lv9.jl")

using BMOPFTools

const LV9_SRC = normpath(joinpath(dirname(pathof(BMOPFTools)), "..", "test", "data", "LV", "LV9_258bus"))
const LV9_DST = joinpath(pwd(), "data", "networks", "LV9_258bus_withPV")

function prepare_lv9()
    @assert isdir(LV9_SRC) "LV9 source folder not found: $LV9_SRC"
    mkpath(LV9_DST)
    for f in ("lines.dss", "Linecodes.dss", "Switches.dss", "Groundings.dss")
        cp(joinpath(LV9_SRC, f), joinpath(LV9_DST, f); force = true)
    end

    # ---- transformer: LV star point on the neutral
    tx = read(joinpath(LV9_SRC, "Transformers.dss"), String)
    m  = match(r"wdg=2 bus=(\S+)", tx)
    @assert m !== nothing "no wdg=2 bus= in Transformers.dss"
    lvbus = m[1]
    occursin(".", lvbus) || (tx = replace(tx, "wdg=2 bus=$lvbus " => "wdg=2 bus=$lvbus.1.2.3.4 "))
    @assert occursin("wdg=2 bus=$(split(lvbus, '.')[1]).1.2.3.4 ", tx) "transformer LV winding not on .1.2.3.4"
    write(joinpath(LV9_DST, "Transformers.dss"), tx)
    mvbus = match(r"wdg=1 bus=(\S+)", tx)[1]

    # ---- loads: CSIRO default 1 kW + 0.539743 kvar; collect (name, bus.ph.4)
    loads = Tuple{String,String,String}[]
    for line in eachline(joinpath(LV9_SRC, "Loads.dss"))
        mm = match(r"^new load\.(\S+)\s+phases=1\s+bus1=(\S+)\s+kv=(\S+)"i, line)
        mm === nothing && continue
        push!(loads, (mm[1], mm[2], mm[3]))
    end
    @assert length(loads) == 123 "expected 123 loads in LV9, found $(length(loads))"
    @assert all(endswith(b, ".4") for (_, b, _) in loads) "a load is not phase-to-neutral"
    open(joinpath(LV9_DST, "Loads.dss"), "w") do io
        println(io, "! CSIRO LV9 loads reset to the dataset default (batchedit kw=1, pf 0.88) as for LV3")
        for (n, b, kv) in loads
            println(io, "new load.$n phases=1 bus1=$b kv=$kv kw=1 kvar=0.539743 vminpu=0.1 vmaxpu=2")
        end
    end

    # ---- PV systems with the LV3 inverter settings
    open(joinpath(LV9_DST, "PVSystems.dss"), "w") do io
        println(io, "// same curves and InvControl as LV3_55bus_withPV/PVSystems.dss (AS/NZS 4777.2 Australia A)")
        println(io, "New XYCurve.VoltVar npts=6 xarray=[0.1 0.9 0.9565217391304348 1.0434782608695652 1.1217391304347826 2] yarray=[0.44 0.44 0 0 -0.6 -0.6]")
        println(io, "New XYCurve.VoltWatt npts=4 xarray=[0.1 1.1 1.1304347826086956 2] yarray=[1 1 0.2 0.2]")
        println(io, "New InvControl.invall CombiMode=VV_VW vvc_curve1=VoltVar voltwatt_curve=VoltWatt RefReactivePower=VARMAX_VARS VoltwattYAxis=PMPPPU")
        println(io)
        for (n, b, _) in loads
            println(io, "new PVSystem.$n phases=1 bus1=$b kv=0.230 kVA=5 Pmpp=5 irradiance=1 Temperature=25 %Cutin=0.0 %Cutout=0.0 model=1 vminpu=0.1 vmaxpu=2")
        end
        println(io)
        println(io, "Edit InvControl.invall VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6")
    end

    # ---- master (same structure as LV3)
    open(joinpath(LV9_DST, "Master.dss"), "w") do io
        println(io, "new circuit.lv9_258bus angle=-30.0000000000 basekv=11.0000000000 pu=1.00 phases=3 bus1=sourcebus model=ideal")
        println(io)
        println(io, "set defaultbasefrequency=50.0000000000")
        println(io, "set basefrequency=50.0000000000")
        println(io)
        for f in ("Linecodes.dss", "lines.dss", "Loads.dss", "Transformers.dss", "Switches.dss", "Groundings.dss", "PVSystems.dss")
            println(io, "redirect $f")
        end
        println(io)
        println(io, "new line.for_energymeter lineCode=ughv_400al_triplex_ug_4w_bundled bus1=sourcebus.1.2.3.0 bus2=$(mvbus).1.2.3.4 length=0.0001 units=km phases=4")
        println(io, "New EnergyMeter.Source     Element= line.for_energymeter  Terminal=1")
        println(io)
        println(io, "Set MaxControlIter=100")
        println(io, "Set tolerance=0.00001")
    end
    nsvc = count(l -> occursin("ugsc_16cu", l), eachline(joinpath(LV9_DST, "lines.dss")))
    println("LV9 prepared in $LV9_DST")
    println("  source data: $LV9_SRC")
    println("  MV bus $mvbus, LV bus $lvbus (now .1.2.3.4), 123 loads at 1 kW / 0.539743 kvar, 123 PVs (5 kVA)")
    println("  16 mm2 service segments: $nsvc")
end

prepare_lv9()
