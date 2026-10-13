# Work log

## 2026-09-10 — LV3 cable catalogue

Ran scripts/count_linecodes.jl on LV3_55bus_withPV.
Verified against `dss("Show Elements")` by hand count.

Circuit: 57 buses, 227 nodes, max |V| 6795.4 V (= 11kV/sqrt3 x 1.07, as expected).

55 Line objects total, made up of:
  - 46 real cable segments (l_*)
  - 8 switches (switch_*)
  - 1 zero-impedance meter dummy (for_energymeter)

CORRECTION: earlier notes said 46 lines and 10 switches. The 46 was right
(it counts cable segments only). The switch count was wrong: there are 8.

Cable types in use (3, out of 22 defined in Linecodes.dss):
  ugsc_16cu_..._4w      22 segments  0.450 km  R_self 1.491 ohm/km  (services)
  uglv_240al_..._4w     14 segments  0.544 km  R_self 0.209 ohm/km  (mains)
  ughv_400al_triplex_4w 11 segments  0.003 km  R_self 0.150 ohm/km  (stubs + meter dummy)
  no linecode            8 segments  0.008 km  (switches)

No `generic/lv` placeholder present in this network.

Total path resistance: services 0.671 ohm, mains 0.114 ohm.
=> service cables carry ~6x the resistance of the mains despite being
   shorter. Voltage rise is resistance-driven, so the services are where
   the perturbation effect will live.

DECISION: perturbation target = ugsc_16cu service cables.
Bias case = record says 16 mm2 Cu, reality is 4 mm2 Cu (uglv_4cu,
4.569 ohm/km). Ratio 3.07x on 22 of 46 segments, all same direction.

ALSO NOTED, needs following up with supervisors:
  - Only 12 customers (12 Loads + 12 PVSystems), not 55. Earlier notes
    describing "55 customer buses" are wrong; 55 refers to buses.
  - Neutral is grounded at ALL 12 load buses plus the transformer
    (13 grounding reactors). This is Australian MEN, not the single-point
    European grounding assumed in Kumarawadu 2025 and in Geth's sparse
    neutral grounding work. Must be stated when comparing to that
    literature, and may explain the April phase-to-ground vs
    phase-to-neutral spread difference (0.46 V vs 4.58 V).

    ## 13 Oct 2026 – LV3 imported into BMOPFTools (Aim 1, part 1)

**Environment**
- Separate Julia 1.11.9 environment in `bmopf/` (main project stays on Julia 1.9 for PMD).
- BMOPFTools pinned at commit b7aa9a1 (the version PowerOptLab expects), JuMP 1.32.1, Ipopt 1.16.0.
- Preferences.jl pinned at 1.5.2: v1.6.0 renamed the keyword `disable_invalidation`, which PowerIO 0.7.3 still uses, so BMOPFTools would not load.
- Note: `from_pmd` no longer exists in BMOPFTools; `from_dss` (via PowerIO) is the import path.

**Import checks (from_dss on Master.dss)**
- Counts match the network: 57 buses, 47 lines (46 cables + 1 meter dummy), 12 loads, 12 PV, 8 switches, 22 linecodes.
- 46 import warnings, all "units dropped". Verified by hand that the values were converted first:
  ugsc_16cu self R 0.454302 ohm/kft ÷ 304.8 = 0.0014904921 ohm/m (stored value identical);
  L_1232 length 0.0112649634 km = 11.2649634 m (stored value identical). Ratio 1.000000 in every case.
- ugsc_16cu is defined three times in Linecodes.dss; the three definitions are identical, so harmless.
- BMOPFTools stores all names in lower case.

**Modelling error 1 – PV connected to ground (fixed in the .dss)**
- PVSystems.dss used `bus1=Bxxxx.3` → OpenDSS fills the second node with 0 = GROUND.
  Loads use `.3.4` = phase-to-neutral. A real inverter connects active-to-neutral like any appliance.
- Fixed all 12 PVs to `.x.4`. analyze(): 14 errors → 2.
- Consequence: all OpenDSS results before 13 Oct (260.71 V baseline, Sept cable sweep 0.34 V / 1.41 V) were computed with PV phase-to-ground and must be regenerated.

**Modelling error 2 – inverter curves mis-translated by PowerIO 0.7.3 (fixed in scripts/bmopf/load_lv3.jl)**
- Volt-VAr breakpoints came through as 6 pu points (BMOPF needs 4, in VOLTS); q_limits [0, 0.44] lost the −0.6 absorb limit.
- Volt-Watt breakpoints 4 pu points (BMOPF needs 2, in volts); p_limits [1, 1] lost the cutback to 0.2.
- voltage_reference came through as PG_PER_PHASE (phase-to-ground); set to PN_PER_PHASE.
- 11 of 12 PVs were not linked to any control profile; Ld24 was linked to a fixed pf = −0.95 profile,
  which in BMOPF would override the droop (OpenDSS does the opposite). All 12 now linked to `invall`.
- Corrected values (230 V base) = AS/NZS 4777.2 Australia A: Volt-VAr 207/220/240/258 V, Q [−0.6, +0.44];
  Volt-Watt 253/260 V, P [1.0, 0.2].
- analyze() after fix: 0 errors, 3 warnings (15 dangling stubs; two loads with low power factor – real data).

**Next:** solve a power flow in BMOPFTools and compare phase-to-neutral voltages with OpenDSS (same snapshot, corrected PV file).
## 13 Oct 2026 (afternoon) – Aim 1: BMOPFTools vs OpenDSS cross-validation

**Third modelling error found and fixed – transformer star point on ground**
- Transformers.dss winding 2 was `bus=B641 conn=wye` with no node list, so OpenDSS tied the star point to node 0 (GROUND), not to the neutral conductor (node 4). All neutral return current was forced through the 0.3 ohm / 10 ohm earth electrodes.
- Evidence: OpenDSS neutral-to-ground about 6 V almost uniformly; BMOPF (star on neutral) 0–1.3 V; difference about −6.0 V constant at every LV bus. Hand check: 6.10 V / 0.3 ohm ≈ 20 A into the transformer earth, plus about 7 A through the 12 customer earths.
- Fixed to `bus=B641.1.2.3.4`. OpenDSS neutral max dropped 7.5 V → 1.7 V; BMOPF unchanged (it already modelled the star point correctly).
- CONSEQUENCE: the August neutral voltages (5.4–7.3 V) and the phase-to-neutral spread (sd 4.58 V vs 0.46 V phase-to-ground) were artefacts of this wiring error.
- RULE for anyone continuing this work: in OpenDSS always write every node explicitly (e.g. `.1.2.3.4`, `.3.4`); any node left out defaults to ground.

**solve_pf cannot reproduce inverter behaviour (BMOPFTools b7aa9a1, ext/BMOPFOpfExt/ibr.jl)**
- Volt-Watt is a cap (P <= cap, line 693), so in a power flow P is not determined (returned an arbitrary 1607 W).
- Volt-VAr is Q == s_max · f(U) (lines 336, 703); solve_pf returned Q = 0 exactly, consistent with s_max being stripped from the PF working copy. Open question for F. Geth.
- q_unit other than VA_FRACTION is not supported (warns and skips Volt-VAr).

**Validation method (scripts/bmopf/validate_network_pinned.jl), following Geth's split of network vs controller evidence**
- (A) Network physics: BMOPF inverters replaced by fixed injections equal to OpenDSS's PV output.
  Phase-to-neutral |diff| mean 0.107 V, max 0.222 V (b1006 b-n). Neutral |diff| mean 0.036 V, max 0.091 V.
  At transformer LV bus b641 the tools agree to 0.0003 V (source and transformer identical).
  Losses: OpenDSS 363.8 W, BMOPF 338.3 W.
  OPEN ITEM: residual grows along the cables on phases b and c only, BMOPF slightly higher; cause not yet found.
- (B) Inverters vs AS/NZS 4777.2 (230 V base): OpenDSS default VarChangeTolerance (2.5 %) left Q at −2.881 kvar instead of −3.000.
  Added `Edit InvControl.invall VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6` to PVSystems.dss → Q = −3.000 kvar on all 12 PVs.
- FINDING: OpenDSS InvControl evaluates the curves on PHASE-TO-GROUND voltage. ld626: V_pg 259.71 V gives P = 1.163 kW (matches); V_pn 258.79 V would give 1.693 kW. ld2186: V_pg 260.01 V gives P cut to 1.0 kW. This thesis uses phase-to-neutral (PN_PER_PHASE).

**Operating point note:** with source at 1.07 pu every LV node sits about 259–262 V phase-to-neutral, so all inverters are at full Volt-VAr absorption (−3 kvar) and Volt-Watt at or near 20 % output. Source voltage choice must be settled before generating DOEs.