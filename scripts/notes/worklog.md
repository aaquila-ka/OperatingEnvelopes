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
