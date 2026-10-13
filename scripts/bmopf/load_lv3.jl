# scripts/bmopf/load_lv3.jl
#
# PURPOSE
#   Load the LV3_55bus_withPV OpenDSS model into BMOPFTools and correct the
#   inverter control settings that PowerIO v0.7.3 mis-translates.
#
# HOW TO RUN (from the project root C:\thesis\OperatingEnvelopes)
#   julia +1.11 --project=bmopf
#   julia> include("scripts/bmopf/load_lv3.jl")
#
# ENVIRONMENT
#   Julia 1.11, BMOPFTools commit b7aa9a1, Preferences pinned at 1.5.2
#   (Preferences 1.6.0 renamed a keyword that PowerIO 0.7.3 still uses).
#
# CHECKS ALREADY DONE BY HAND (13 Oct 2026)
#   - from_dss converts linecode impedance ohm/kft -> ohm/m and line length
#     km -> m correctly (exact ratio 1.000000 on ugsc_16cu and line L_1232).
#   - PVSystems.dss corrected so every PV connects phase-to-NEUTRAL (.x.4),
#     matching the loads (previously phase-to-ground by default).

using BMOPFTools

const DSS_DIR    = "data/networks/LV3_55bus_withPV/"
const V_BASE_INV = 230.0   # PVSystem kv=0.230, so inverter voltage base = 230 V

function load_lv3()
    net = from_dss(DSS_DIR * "Master.dss")
    vv  = net["control_profile"]["invall"]["volt_var"]
    vw  = net["control_profile"]["invall"]["volt_watt"]

    # ---- 1. Volt-VAr --------------------------------------------------------
    # OpenDSS XYCurve.VoltVar has 6 points in pu, including two flat "end"
    # points at 0.1 and 2 pu. BMOPF wants only the 4 inner corners, in VOLTS.
    vv_pu = Float64.(vv["breakpoints"])
    @assert length(vv_pu) == 6 "expected 6 Volt-VAr points from OpenDSS, got $(length(vv_pu))"
    vv["breakpoints"] = vv_pu[2:5] .* V_BASE_INV
    # OpenDSS yarray = [0.44 0.44 0 0 -0.6 -0.6]: inject 0.44 at low voltage,
    # absorb 0.6 at high voltage. BMOPF order is [absorb <= 0, inject >= 0].
    # PowerIO produced [0, 0.44], which loses the absorb limit entirely.
    vv["q_limits"] = [-0.6, 0.44]
    # The inverter measures the voltage at its own terminals: phase-to-neutral.
    vv["voltage_reference"] = "PN_PER_PHASE"

    # ---- 2. Volt-Watt -------------------------------------------------------
    # OpenDSS XYCurve.VoltWatt has 4 points in pu; BMOPF wants 2 corners in V.
    vw_pu = Float64.(vw["breakpoints"])
    @assert length(vw_pu) == 4 "expected 4 Volt-Watt points from OpenDSS, got $(length(vw_pu))"
    vw["breakpoints"] = vw_pu[2:3] .* V_BASE_INV
    # OpenDSS yarray = [1 1 0.2 0.2]: full output up to the first corner,
    # down to 20 % at the second. PowerIO produced [1, 1], losing the cutback.
    vw["p_limits"] = [1.0, 0.2]
    vw["voltage_reference"] = "PN_PER_PHASE"

    # ---- 3. Link every PV to the Volt-VAr / Volt-Watt profile ---------------
    # InvControl.invall has no PVSystemList, so in OpenDSS it controls ALL 12
    # PVs and overrides a PV's own pf= setting (Ld24 has pf=-0.95). In BMOPF a
    # power_factor profile would instead WIN over the droop, so it is removed.
    for ibr in values(net["ibr"])
        ibr["control_profile"] = "invall"
    end
    delete!(net["control_profile"], "Ld24_LOAD_A_pf")

    # ---- 4. Checks against AS/NZS 4777.2 (Australia A, 230 V) ---------------
    @assert vv["breakpoints"] ≈ [207, 220, 240, 258] "Volt-VAr corners wrong: $(vv["breakpoints"])"
    @assert vw["breakpoints"] ≈ [253, 260]           "Volt-Watt corners wrong: $(vw["breakpoints"])"
    @assert all(ibr["terminal_map"][2] == "n" for ibr in values(net["ibr"])) "a PV is not on the neutral"
    @assert all(ibr["control_profile"] == "invall" for ibr in values(net["ibr"])) "a PV is not linked to invall"
    return net
end

# ---- Run it and re-check the network ----------------------------------------
net = load_lv3()
io = IOBuffer(); render(analyze(net), io); txt = String(take!(io))
write("results/analyze_lv3_after_ctrlfix.txt", txt)
println("\n==== analyze() summary after control-profile fix ====")
foreach(println, filter(l -> occursin(r"Findings|\[ERROR\]", l), split(txt, "\n")))
println("Volt-VAr  breakpoints (V): ", net["control_profile"]["invall"]["volt_var"]["breakpoints"])
println("Volt-Watt breakpoints (V): ", net["control_profile"]["invall"]["volt_watt"]["breakpoints"])