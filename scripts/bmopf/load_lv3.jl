# =============================================================================
# load_lv3.jl: load the CSIRO LV3 feeder into BMOPFTools and set the inverter controls
#
# What it does (plain English):
#   Reads the OpenDSS model of the LV3 street (55 buses, 12 houses, each with a
#   5 kVA solar inverter) into BMOPFTools. The importer (PowerIO v0.7.3) carries the
#   OpenDSS inverter curves over in a different convention from the one BMOPFTools
#   expects, so this file rewrites them: Volt-VAr (reactive power vs voltage) and
#   Volt-Watt (active power cut-back vs voltage), AS/NZS 4777.2 "Australia A" values,
#   in volts, measured phase-to-neutral (PN). It then checks the result and saves the
#   BMOPFTools analyze() report.
# Inputs:   data/networks/LV3_55bus_withPV/Master.dss (and the .dss files it redirects to)
# Outputs:  results/analyze_lv3_after_ctrlfix.txt; prints the analyze() findings and the
#           final curve corners. The last lines run on every include, so any script that
#           includes this file (through doe_common.jl) rewrites that report (same content).
# How to run (from the repo folder, in `julia +1.11 --project=bmopf`):
#   include("scripts/bmopf/load_lv3.jl")   (runs straight away; load_lv3() returns the network)
# Used for: REPRODUCE.md step 1; every LV3 DOE script builds its network with load_lv3()
# Credits:  CSIRO LV3 network data (CC BY-NC-SA 4.0); BMOPFTools.jl by Frederik Geth
#           (with its PowerIO importer); OpenDSS (EPRI); AS/NZS 4777.2 curve values
# =============================================================================
#
# Environment: Julia 1.11, BMOPFTools commit b7aa9a1, Preferences pinned at 1.5.2.
#
# ORDER CONVENTIONS (read from BMOPFTools source ext/BMOPFOpfExt/ibr.jl, b7aa9a1)
#   volt_var  q_limits = [q_absorb (<=0), q_inject (>=0)]   (lines 293-295)
#             (fractions of the inverter rating s_max: Q = s_max x curve value)
#   volt_watt p_limits = [p_low (cut-back level), p_high (full output)]
#             curve value is p_high at U5 and p_low at U6   (lines 326-328)
#   An earlier version of this file used [1.0, 0.2], which INVERTED the
#   Volt-Watt curve. Caught in code review (AI-assisted review, checked by me); fixed below.

# BMOPFTools = Frederik Geth's Julia package that reads the street model and solves its power flow
# and optimisation
using BMOPFTools

# Where the street's OpenDSS files live, and the inverter voltage base (230 V) used to turn the
# per-unit curve corners into volts
const DSS_DIR    = "data/networks/LV3_55bus_withPV/"
const V_BASE_INV = 230.0   # PVSystem kv=0.230, so inverter voltage base = 230 V

# load_lv3(): read the LV3 street from the OpenDSS files, rewrite the inverter rules so BMOPFTools
# reads them the right way round, check them, and return the network (a big dictionary of buses,
# lines, loads and inverters).
# Volt-VAr / Volt-Watt = inverter rules from AS/NZS 4777.2 (the Australian inverter standard):
# Volt-VAr makes the inverter soak up reactive power when the voltage is high, Volt-Watt cuts real
# export back when the voltage is very high
function load_lv3()
    # Read Master.dss (which pulls in the other .dss files) into a BMOPFTools network
    net = from_dss(DSS_DIR * "Master.dss")
    # Shortcuts to the two rule curves of the one shared inverter-control profile, called "invall"
    vv  = net["control_profile"]["invall"]["volt_var"]
    vw  = net["control_profile"]["invall"]["volt_watt"]

    # ---- 1. Volt-VAr: 4 inner corners in VOLTS, limits [absorb, inject] -------
    # OpenDSS gave 6 corner voltages in pu (pu = voltage relative to normal, so 1.03 = 3% high)
    vv_pu = Float64.(vv["breakpoints"])
    @assert length(vv_pu) == 6 "expected 6 Volt-VAr points from OpenDSS, got $(length(vv_pu))"
    # Keep only the 4 inner corners (the outer two only stretch the flat ends of the curve) and turn
    # pu into volts by x 230 V; the check below expects 207, 220, 240, 258 V
    vv["breakpoints"] = vv_pu[2:5] .* V_BASE_INV
    # How much reactive power the inverter may absorb (-0.6 = 60% of its 5 kVA) or inject (+0.44 =
    # 44%) at the ends of the curve
    vv["q_limits"] = [-0.6, 0.44]          # OpenDSS yarray: +0.44 at low V, -0.6 at high V
    # Measure the voltage phase-to-neutral (what a home actually feels), not phase-to-ground
    vv["voltage_reference"] = "PN_PER_PHASE"

    # ---- 2. Volt-Watt: 2 corners in VOLTS, limits [p_low, p_high] ------------
    vw_pu = Float64.(vw["breakpoints"])
    @assert length(vw_pu) == 4 "expected 4 Volt-Watt points from OpenDSS, got $(length(vw_pu))"
    # Keep the 2 middle corners and turn them into volts (the check below expects 253 and 260 V):
    # full output up to 253 V, cut back to 20% by 260 V
    vw["breakpoints"] = vw_pu[2:3] .* V_BASE_INV
    vw["p_limits"] = [0.2, 1.0]            # [p_low, p_high]: 1.0 up to 253 V, 0.2 from 260 V
    # Same as Volt-VAr: measured phase-to-neutral
    vw["voltage_reference"] = "PN_PER_PHASE"

    # ---- 3. Link every PV to invall (OpenDSS InvControl has no PVSystemList) --
    # Make every one of the 12 inverters follow the same "invall" rules
    for ibr in values(net["ibr"])
        ibr["control_profile"] = "invall"
    end
    # The importer also linked PV Ld24 to a fixed power-factor profile (pf=-0.95 in
    # PVSystems.dss). In BMOPFTools that profile would take priority over the droop
    # curves, while in OpenDSS the InvControl takes over, so it is removed here.
    delete!(net["control_profile"], "Ld24_LOAD_A_pf")

    # ---- 4. Checks ---------------------------------------------------------
    # Safety checks: stop with an error if the corners or limits are not what we expect, so a wrong
    # (for example upside-down) curve can never slip through silently
    @assert vv["breakpoints"] ≈ [207, 220, 240, 258] "Volt-VAr corners wrong: $(vv["breakpoints"])"
    @assert vw["breakpoints"] ≈ [253, 260]           "Volt-Watt corners wrong: $(vw["breakpoints"])"
    @assert vv["q_limits"][1] < 0 < vv["q_limits"][2] "q_limits must be [absorb<0, inject>0]"
    @assert vw["p_limits"][1] < vw["p_limits"][2]     "p_limits must be [p_low, p_high]; curve would be inverted"
    # Every inverter must be wired phase-to-neutral, linked to invall, and have a size s_max (the
    # Volt-VAr amounts are a fraction of s_max)
    @assert all(ibr["terminal_map"][2] == "n" for ibr in values(net["ibr"])) "a PV is not on the neutral"
    @assert all(ibr["control_profile"] == "invall" for ibr in values(net["ibr"])) "a PV is not linked to invall"
    @assert all(haskey(ibr, "s_max") for ibr in values(net["ibr"])) "a PV has no s_max (Volt-VAr base would be 0)"
    return net
end

# Everything below runs as soon as this file is included: build the network once and keep it in
# `net`
net = load_lv3()
# Run BMOPFTools' analyze() health check on the network and capture its report as text
io = IOBuffer(); render(analyze(net), io); txt = String(take!(io))
# Save the full report in the results folder
write("results/analyze_lv3_after_ctrlfix.txt", txt)
println("\n==== analyze() summary after control-profile fix ====")
# Print only the lines that summarise the findings or flag errors
foreach(println, filter(l -> occursin(r"Findings|\[ERROR\]", l), split(txt, "\n")))
# Print the final curve corners and limits so you can see the fix worked
println("Volt-VAr  breakpoints (V): ", net["control_profile"]["invall"]["volt_var"]["breakpoints"], "  q_limits ", net["control_profile"]["invall"]["volt_var"]["q_limits"])
println("Volt-Watt breakpoints (V): ", net["control_profile"]["invall"]["volt_watt"]["breakpoints"], "  p_limits ", net["control_profile"]["invall"]["volt_watt"]["p_limits"])