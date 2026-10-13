# scripts/bmopf/load_lv3.jl
#
# PURPOSE
#   Load the LV3_55bus_withPV OpenDSS model into BMOPFTools and correct the
#   inverter control settings that PowerIO v0.7.3 mis-translates.
#
# HOW TO RUN (from C:\thesis\OperatingEnvelopes)
#   julia +1.11 --project=bmopf
#   julia> include("scripts/bmopf/load_lv3.jl")
#
# ENVIRONMENT
#   Julia 1.11, BMOPFTools commit b7aa9a1, Preferences pinned at 1.5.2.
#
# ORDER CONVENTIONS (read from BMOPFTools source ext/BMOPFOpfExt/ibr.jl, b7aa9a1)
#   volt_var  q_limits = [q_absorb (<=0), q_inject (>=0)]   (lines 293-295)
#   volt_watt p_limits = [p_low (cut-back level), p_high (full output)]
#             curve value is p_high at U5 and p_low at U6   (lines 326-328)
#   13 Oct 2026: an earlier version used [1.0, 0.2], which INVERTED the
#   Volt-Watt curve. Caught in independent review; fixed below.

using BMOPFTools

const DSS_DIR    = "data/networks/LV3_55bus_withPV/"
const V_BASE_INV = 230.0   # PVSystem kv=0.230, so inverter voltage base = 230 V

function load_lv3()
    net = from_dss(DSS_DIR * "Master.dss")
    vv  = net["control_profile"]["invall"]["volt_var"]
    vw  = net["control_profile"]["invall"]["volt_watt"]

    # ---- 1. Volt-VAr: 4 inner corners in VOLTS, limits [absorb, inject] -------
    vv_pu = Float64.(vv["breakpoints"])
    @assert length(vv_pu) == 6 "expected 6 Volt-VAr points from OpenDSS, got $(length(vv_pu))"
    vv["breakpoints"] = vv_pu[2:5] .* V_BASE_INV
    vv["q_limits"] = [-0.6, 0.44]          # OpenDSS yarray: +0.44 at low V, -0.6 at high V
    vv["voltage_reference"] = "PN_PER_PHASE"

    # ---- 2. Volt-Watt: 2 corners in VOLTS, limits [p_low, p_high] ------------
    vw_pu = Float64.(vw["breakpoints"])
    @assert length(vw_pu) == 4 "expected 4 Volt-Watt points from OpenDSS, got $(length(vw_pu))"
    vw["breakpoints"] = vw_pu[2:3] .* V_BASE_INV
    vw["p_limits"] = [0.2, 1.0]            # [p_low, p_high]: 1.0 up to 253 V, 0.2 from 260 V
    vw["voltage_reference"] = "PN_PER_PHASE"

    # ---- 3. Link every PV to invall (OpenDSS InvControl has no PVSystemList) --
    for ibr in values(net["ibr"])
        ibr["control_profile"] = "invall"
    end
    delete!(net["control_profile"], "Ld24_LOAD_A_pf")

    # ---- 4. Checks ---------------------------------------------------------
    @assert vv["breakpoints"] ≈ [207, 220, 240, 258] "Volt-VAr corners wrong: $(vv["breakpoints"])"
    @assert vw["breakpoints"] ≈ [253, 260]           "Volt-Watt corners wrong: $(vw["breakpoints"])"
    @assert vv["q_limits"][1] < 0 < vv["q_limits"][2] "q_limits must be [absorb<0, inject>0]"
    @assert vw["p_limits"][1] < vw["p_limits"][2]     "p_limits must be [p_low, p_high]; curve would be inverted"
    @assert all(ibr["terminal_map"][2] == "n" for ibr in values(net["ibr"])) "a PV is not on the neutral"
    @assert all(ibr["control_profile"] == "invall" for ibr in values(net["ibr"])) "a PV is not linked to invall"
    @assert all(haskey(ibr, "s_max") for ibr in values(net["ibr"])) "a PV has no s_max (Volt-VAr base would be 0)"
    return net
end

net = load_lv3()
io = IOBuffer(); render(analyze(net), io); txt = String(take!(io))
write("results/analyze_lv3_after_ctrlfix.txt", txt)
println("\n==== analyze() summary after control-profile fix ====")
foreach(println, filter(l -> occursin(r"Findings|\[ERROR\]", l), split(txt, "\n")))
println("Volt-VAr  breakpoints (V): ", net["control_profile"]["invall"]["volt_var"]["breakpoints"], "  q_limits ", net["control_profile"]["invall"]["volt_var"]["q_limits"])
println("Volt-Watt breakpoints (V): ", net["control_profile"]["invall"]["volt_watt"]["breakpoints"], "  p_limits ", net["control_profile"]["invall"]["volt_watt"]["p_limits"])