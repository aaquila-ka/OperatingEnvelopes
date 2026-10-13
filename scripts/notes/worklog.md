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