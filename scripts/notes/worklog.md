# Development notes

These notes record every check, problem and fix in the order they happened, so anyone can follow how the results were reached. Stages are numbered instead of dated. Exact versions of every file are in the git history.

## Stage 1: LV3 cable catalogue

Ran scripts/count_linecodes.jl on LV3_55bus_withPV.
Verified against `dss("Show Elements")` by hand count.

Circuit: 57 buses, 227 nodes, max |V| 6795.4 V (= 11 kV/sqrt3 x 1.07; the source was set to 1.07 pu at this stage, later changed to the dataset's 1.00 pu).

55 Line objects total, made up of:
  - 46 real cable segments (l_*)
  - 8 switches (switch_*)
  - 1 zero-impedance meter dummy (for_energymeter)

Correction to my own earlier notes: they said 46 lines and 10 switches. The 46 was right
(it counts cable segments only); there are 8 switches, not 10.

Cable types in use (3, out of 22 defined in Linecodes.dss):
  ugsc_16cu_..._4w      22 segments  0.450 km  R_self 1.491 ohm/km  (services)
  uglv_240al_..._4w     14 segments  0.544 km  R_self 0.209 ohm/km  (mains)
  ughv_400al_triplex_4w 11 segments  0.003 km  R_self 0.150 ohm/km  (stubs + meter dummy)
  no linecode            8 segments  0.008 km  (switches)

No `generic/lv` placeholder present in this network.

Total path resistance: services 0.671 ohm, mains 0.114 ohm.
=> service cables carry ~6x the resistance of the mains despite being
   shorter. Voltage rise is resistance-driven, so the services are where
   a record error has the most effect.

DECISION: perturbation target = ugsc_16cu service cables.
Bias case = record says 16 mm2 Cu, reality is 4 mm2 Cu (uglv_4cu,
4.569 ohm/km). Ratio 3.07x on 22 of 46 segments, all same direction.
(4 mm2 is a test case, not something observed in the field.)

Also noted, to discuss with supervisors:
  - Only 12 customers (12 Loads + 12 PVSystems); "55" is the number of buses.
  - The neutral is earthed at all 12 load buses plus the transformer
    (13 earthing reactors), as in Australian MEN (multiple earthed neutral)
    practice. Studies that use single-point earthing are a different
    setting, so this must be stated when comparing results.

## Stage 2: LV3 imported into BMOPFTools (Aim 1, part 1)

**Environment**
- Separate Julia 1.11.9 environment in `bmopf/` (the top-level project stays on Julia 1.9 for the early PowerModelsDistribution study scripts).
- BMOPFTools pinned at commit b7aa9a1 (the version PowerOptLab expects), JuMP 1.32.1, Ipopt 1.16.0.
- Preferences.jl pinned at 1.5.2: v1.6.0 renamed the keyword `disable_invalidation`, which PowerIO 0.7.3 still uses, so BMOPFTools would not load with 1.6.
- `from_dss` (via PowerIO) is the import path in this BMOPFTools version (`from_pmd` is not available).

**Import checks (from_dss on Master.dss)**
- Counts match the network: 57 buses, 47 lines (46 cables + 1 meter dummy), 12 loads, 12 PV, 8 switches, 22 linecodes.
- 46 import warnings, all "units dropped". Verified by hand that the values were converted first:
  ugsc_16cu self R 0.454302 ohm/kft ÷ 304.8 = 0.0014904921 ohm/m (stored value identical);
  L_1232 length 0.0112649634 km = 11.2649634 m (stored value identical). Ratio 1.000000 in every case.
- ugsc_16cu is defined three times in Linecodes.dss; the three definitions are identical, so harmless.
- BMOPFTools stores all names in lower case.

**My modelling error 1: PV connected to ground (fixed in the .dss)**
- My PVSystems.dss used `bus1=Bxxxx.3`, so OpenDSS filled the second node with 0 = ground.
  Loads use `.3.4` = phase-to-neutral, and a real inverter connects active-to-neutral like any appliance.
- Fixed all 12 PVs to `.x.4`. analyze(): 14 errors -> 2.
- Consequence: all my earlier OpenDSS results (260.71 V baseline, cable sweep 0.34 V / 1.41 V) used PV phase-to-ground and are superseded.

**Inverter settings after import (set in scripts/bmopf/load_lv3.jl)**
- With PowerIO 0.7.3 the Volt-VAr breakpoints arrived as 6 per-unit points (BMOPF expects 4, in volts) and q_limits [0, 0.44] without the −0.6 absorb limit.
- Volt-Watt breakpoints arrived as 4 per-unit points (BMOPF expects 2, in volts) and p_limits [1, 1] without the cutback to 0.2.
- voltage_reference arrived as PG_PER_PHASE (phase-to-ground); set to PN_PER_PHASE.
- 11 of 12 PVs were not linked to a control profile; Ld24 was linked to a fixed pf = −0.95 profile,
  which in BMOPF takes priority over the droop (OpenDSS uses the opposite order). All 12 now linked to `invall`.
- Values used (230 V base) = AS/NZS 4777.2 Australia A: Volt-VAr 207/220/240/258 V, Q [−0.6, +0.44];
  Volt-Watt 253/260 V, P [1.0, 0.2].
- analyze() after the fix: 0 errors, 3 warnings (15 dangling stubs; two loads with low power factor, which is real data).

## Stage 3: BMOPFTools vs OpenDSS cross-validation (Aim 1)

**My modelling error 2: transformer star point on ground**
- My Transformers.dss winding 2 was `bus=B641 conn=wye` with no node list, so OpenDSS tied the star point to node 0 (ground), not to the neutral conductor (node 4). All neutral return current was forced through the 0.3 ohm / 10 ohm earth electrodes.
- Evidence: OpenDSS neutral-to-ground about 6 V almost everywhere; BMOPF (star on neutral) 0–1.3 V; a constant difference of about −6.0 V at every LV bus. Hand check: 6.10 V / 0.3 ohm ≈ 20 A into the transformer earth, plus about 7 A through the 12 customer earths.
- Fixed to `bus=B641.1.2.3.4`. OpenDSS neutral max dropped 7.5 V -> 1.7 V; BMOPF unchanged (it already modelled the star point on the neutral).
- Consequence: my earlier neutral voltages (5.4–7.3 V) and the phase-to-neutral spread (sd 4.58 V vs 0.46 V phase-to-ground) came from this wiring error.
- Rule for anyone continuing this work: in OpenDSS always write every node explicitly (e.g. `.1.2.3.4`, `.3.4`); any node left out defaults to ground.

**How solve_pf treats inverters (BMOPFTools b7aa9a1, ext/BMOPFOpfExt/ibr.jl)**
- Volt-Watt is a cap (P <= cap, line 693), so a power flow alone does not fix P (it returned 1607 W).
- Volt-VAr is Q == s_max · f(U) (lines 336, 703); solve_pf returned Q = 0, consistent with s_max not being carried into the power-flow copy. Question for F. Geth.
- Only q_unit = VA_FRACTION is supported for Volt-VAr in this version.

**Validation method (scripts/bmopf/validate_network_pinned.jl), following Geth's split of network evidence vs controller evidence**
- (A) Network physics: BMOPF inverters replaced by fixed injections equal to OpenDSS's PV output.
  Phase-to-neutral |diff| mean 0.107 V, max 0.222 V (b1006 b-n). Neutral |diff| mean 0.036 V, max 0.091 V.
  At transformer LV bus b641 the tools agree to 0.0003 V.
  Losses: OpenDSS 363.8 W, BMOPF 338.3 W (explained in Stage 9).
- (B) Inverters vs AS/NZS 4777.2 (230 V base): OpenDSS's default VarChangeTolerance (2.5 %) left Q at −2.881 kvar instead of −3.000.
  Added `Edit InvControl.invall VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6` to PVSystems.dss -> Q = −3.000 kvar on all 12 PVs.
- Finding: OpenDSS InvControl evaluates the curves on phase-to-ground voltage. ld626: V_pg 259.71 V gives P = 1.163 kW (matches); V_pn 258.79 V would give 1.693 kW. This thesis uses phase-to-neutral (PN_PER_PHASE).

**Operating point note:** with the source at 1.07 pu every LV node sat at about 259–262 V phase-to-neutral before any export, so the source voltage had to be settled before generating DOEs.

## Stage 4: first clean and dirty DOEs (Aims 2, 4)

**Setup**
- Source set back to 1.00 pu in Master.dss (the original CSIRO value; 1.07 pu was my own earlier choice and put every bus above 253 V before any export). My earlier seminar figure 260.91 V = 1.07 × 243.9 V, i.e. just the no-load LV voltage at 1.07 pu.
- `batchedit load..* kw=1` is commented out in my Master.dss, so OpenDSS and BMOPF use the same Loads.dss values.
- Pinned validation at 1.00 pu with PV near full export: max gap 0.20 V, mean 0.066 V; PV P = sqrt(5² − Q²) exactly (5 kVA rating).
- DOE tool: PowerOptLab commit 953e45c (the version tested against BMOPFTools b7aa9a1). Equal allocation, export, security = bound_point, export_max 5 kW, PVs keep AS/NZS 4777.2 Volt-VAr/Volt-Watt (phase-to-neutral).

**Where the 207–253 V limit is applied (modelling choice)**
- "all": every phase of every LV bus. At 1.03 pu the binding point was b1754 phase a, where no customer is connected (neutral shift from unbalanced load). With 4 mm² services this point is above 253 V even at zero export, so the DOE is infeasible.
- "customer" (DEFAULT): only on each customer's own phase at their connection point. The highest voltage anywhere is still reported.

(The DOE numbers from this stage used my own edited loads and are superseded by Stage 5.)

## Stage 5: original CSIRO loads; code review fixes

- Loads.dss: all 12 loads set to kw=1 kvar=0.539743 (pf 0.88), the original CSIRO setting
  (Master `batchedit load..* kw=1` + OpenDSS default pf). My earlier edited values (0–4 kW, one load
  5 kvar) had no documented source and caused a large neutral shift at b1754.
- Code review against BMOPFTools b7aa9a1 / PowerOptLab 953e45c: DOE maths confirmed;
  verify pins P exactly. Added: source-voltage guard, original-load guard, customer = inverter
  points guard, per-house binding report (S/5 kVA), helpers moved to scripts/bmopf/doe_common.jl,
  "undeliverable" labelling + counterfactual voltage with the inverter rating relaxed.

**Clean DOEs (original loads, customer mode, equal allocation)**
- 1.00 pu: 4.906 kW/house, max 245.78 V -> limited by the inverter rating (5 kVA with Volt-VAr absorption).
- 1.03 pu: 4.529 kW/house, max 252.71 V (b828 b-n) -> limited by the inverter rating, S/5 kVA = 1.000.

**Dirty DOEs (1.03 pu; 22 service segments ugsc_16cu <-> uglv_4cu, R ×3.07)**
- CASE A (truth 4 mm², records 16 mm²): correct 2.734 kW (voltage-limited, 253.00 V b828 b-n, S/5 kVA 0.698);
  issued 4.529 kW (+65.6 %); undeliverable within 5 kVA under Volt-VAr; counterfactual 255.12 V (+2.12 V).
- CASE B (truth 16 mm², records 4 mm²): correct 4.529 kW (inverter-limited); issued 2.734 kW (−39.6 %); 251.80 V.
- Hand check: Q(253 V) = 2.167 kvar; S = sqrt(2.734² + 2.167²) = 3.488 kVA = 0.698 × 5 kVA.

**Design question for supervisors:** a 5 kVA inverter with 5 kW PV makes the clean DOE
inverter-limited at 1.03 pu; Geth's australian_pv study uses 6 kVA with 5 kW, which would make it voltage-limited.

**Re-validation with original loads**
- Loads identical in both tools (12 × 1.000 kW, 0.540 kvar).
- (B) OpenDSS InvControl = AS/NZS 4777.2 curves on phase-to-ground voltage with reactive priority
  (P = min(VW cap, sqrt(5² − Q²))): worst gap 0.000 kW / 0.000 kvar on all 12 PVs.
- (A) pinned network: phase-to-neutral |diff| mean 0.071 V, max 0.104 V (b2740 b-n); neutral max 0.024 V.
  The earlier 0.22 V gap came mostly from my edited loads.

**Severity sweep (service-cable diagonal R × k, 1.03 pu, original loads)**
- k: 1.00 / 1.10 / 1.25 / 1.50 / 2.00 / 2.50 / 3.07 -> correct DOE 4.529 / 4.520 / 4.507 / 4.084 / 3.470 / 3.063 / 2.739 kW
- Binding: inverter (k ≤ 1.25), voltage (k ≥ 1.5). Small record errors are absorbed by the inverter limit.
- Case A over-promise: 0 / +0.2 / +0.5 / +10.9 / +30.5 / +47.9 / +65.4 %; true-street customer V 252.71 / 252.82 / 252.99 / 253.27 / 253.81 / 254.46* / 255.12* V (*undeliverable within 5 kVA, counterfactual)
- Case B lost export: 0 / −0.2 / −0.5 / −9.8 / −23.4 / −32.4 / −39.5 %
- k = 3.07 (R only) 2.739 kW vs full 4 mm² swap 2.734 kW (the swap also changes X).

**OpenDSS check of Case A (opendss_check_caseA.jl)**
- 4 mm² true street, 1.03 pu, VW off, kVA relaxed, kvarMax 5: 0 kW -> OpenDSS 250.38 V vs BMOPF 250.48 V (b1804 b-n);
  4.529 kW -> OpenDSS 255.19 V vs BMOPF 255.12 V (b828 b-n). Both 2.1–2.2 V above 253 V. OpenDSS PV P = 4.529 kW exactly.

## Stage 6: reproducibility, realistic errors, full day, review and fixes

**Reproducibility**
- The thesis scripts use the `bmopf/` project (Julia 1.11.9, BMOPFTools b7aa9a1, PowerOptLab 953e45c, Preferences 1.5.2); its Manifest is tracked. The top-level Project.toml is the older PowerModelsDistribution setup.
- Added REPRODUCE.md (versions, run order, expected numbers, known issues) and DATA_CARD.md (every results column).
- GitHub repo aaquila-ka/OperatingEnvelopes created with the full history.

**Realistic record errors** (doe_record_errors.jl, doe_critical_cables.jl)
- Scatter (sigma 5/10/20 % per cable) and wrong type (2/5/11 of 22 cables really 4 mm2), 20 seeded draws each; running twice gave identical rows.
- One cable at a time: only the 12 customer service cables matter; the 10 other segments are dead-end stubs with no load. Customer Ld1291's cable l_3432 (B828, 29.5 m) alone gives the same DOE as all 22 wrong.

**Full day** (doe_timeseries.jl)
- 12 of 99 Team-Nando OE1-Ideal smart-meter profiles (commit 96abbab, BSD-3), 5-min averaged to 30 min, picked with seed 20261013.

**Cross-check by a separate OpenDSS rebuild** (written in Python with AI assistance, not using the thesis scripts; checked by me)
- Matched: clean DOE 4.527 vs 4.529 kW; l_3432 2.764 vs 2.734 kW. Code logic, units, seeds and topology also checked.
- It pointed out four claims that went too far: (1) the voltage was read with Volt-Watt off and every customer exporting the full DOE, even at night; (2) results depend strongly on the 1.03 pu source; (3) "scatter is harmless" is only true in the inverter-limited 1 kW snapshot; (4) "one wrong record = all wrong" holds for the DOE value, not for how many customers go over 253 V.

**Fixes**
- New realised reading: customers may export up to the cap, inverters keep Volt-VAr, Volt-Watt and 5 kVA. l_3432: 254.60 V (OpenDSS 254.61 V), 1 customer above 253 V.
- Day run limited by available sun (5 kW x PV shape): over-voltage only 10:00-16:30, peak 255.02 V at 11:30, up to 10 customers; DOE too generous by 2.0-2.35 kW all day at 1.03 pu.
- Record errors rerun at 12:00 loads (voltage-limited): scatter 10 % moves the DOE −5.7 to +9.3 %, max 253.20 V; wrong types up to +117 %, 255.15 V.
- Source sweep 1.00-1.035 pu (12:00): gap 0.14 / 0.17 / 0.71 / 1.63 / 2.29 / 0.60 kW. The error matters only when the feeder is near its voltage limit.
- All 22 scatter factors now saved per draw; gap_kW column added; "nameplate" label renamed "other".

## Stage 7: what a utility can do, sharing rules, second review

**Robust DOE vs checking records** (doe_robust.jl)
- Hedge in advance (as in the robust DOE of Liu, Braslavsky and Mahdavi): DOE safe if every service cable's R is up to b higher. Cost vs clean at 12:00: 3.0 / 5.8 / 11.0 % for b = 5 / 10 / 20 % (snapshot 0.1-0.4 %). Their paper reports 37 % at 5 % on their network, so the cost depends on the network.
- PowerOptLab scenario feature (R x (1-b), R, R x (1+b), and mixed: l_3432 +b, others −b) gives the same DOE to 3 decimals, so the uniform worst case also covers uneven errors here.
- Checking the 12 customer cables one by one (unchecked = 4 mm2): at 12:00, 1.96 kW (none) -> 2.43 (1) -> about 2.55 (7-9) -> 3.12 (10, OPF-ranked) -> 4.25 (11). Shortest-first recovers nothing. Under equal allocation checking pays off only near the end.
- Small non-monotone drops (up to 0.02 kW) when one more cable is checked: Volt-VAr coupling between customers (reproduced in OpenDSS, gone with Volt-VAr off).

**Sharing rules** (doe_fairness.jl)
- One wrong record (l_3432): over-voltage always at b828 phase b (Ld1291, the owner of that cable), 254.60 V snapshot / 255.15 V at 12:00, under equal, proportional and max-min.
- Who absorbs the correction: equal 12 of 12 customers (21.6 / 27.5 kW wrongly allocated), proportional 1 of 12 (1.9 / 2.4 kW, about 12x less, but that customer ends up slightly lower: 2.68 vs 2.73 kW), max-min 8-10 of 12.
- All 22 wrong: the error spreads under every rule; proportional curtails more at 12:00 (3.3 vs 0.9 kW).
- Per-customer labels for 3 rules saved in doe_fairness_customers.csv (216 rows).

**Second review (AI-assisted, checked by me)**
- All round-1 points fixed or disclosed; realised reading matches an exact OpenDSS solve within 0.03 V.
- Fixed: DATA_CARD "up to 8" -> 12; cross-reference; fairness wording (physical harm same under every rule); which customers exceed 253 V; mixed robust scenario; OPF-ranked check order; docs for steps 12-13.
- Disclosed: the Volt-Watt corner is smoothed in BMOPF (curtailment about 5 % high when many customers sit just above 253 V, voltages unaffected); error largest around 1.025-1.03 pu; one partly cloudy day.
- Lesson: the browser saved new downloads as "name (1).jl" and the old files were copied; always copy the newest download and check with Select-String.

## Stage 8: cable ratio, clear-sky day, checking under proportional sharing

- Cable ratio (doe_ratio.jl): the dataset's 16 mm2 code is about 30 % above IEC 60228, so its 3.07 ratio is conservative. Diagonal R x 3.07 matches the 4 mm2 code swap within 0.005 kW. With the IEC ratio 4.0: gap +0.35 kW (12:00: 2.29 -> 2.63 kW), realised peak +0.5-0.8 V (11:30 sun-limited: 255.02 -> 255.77 V).
- Clear-sky day (doe_clearsky.jl, ASSUMED peak 0.85 x 5 kW, half-sine over the measured sun hours): over-voltage in 21 half-hours (07:30-17:30) vs 13 on the measured cloudy day; peak 255.22 V held by Volt-Watt and the 5 kVA rating; up to 12 customers; curtailment up to 0.61 kW.
- Checking records under proportional sharing (doe_verify_proportional.jl): at 12:00 the safe total rises 64 -> 75 -> 84 -> 94 -> 100 % after 0/3/6/9/11 checks (OPF-ranked), and still rises in shortest-first order; under equal sharing it stays at 46 % until the last critical check. Trade-off: the unchecked customer keeps a low limit (about 1.9-2.1 kW).
- For "what should a utility do": hedge small resistance doubts in advance (3-11 %); check cable types, which pays off steadily only with proportional sharing.

## Stage 9: loss difference explained

- The 7 % loss difference between BMOPFTools and OpenDSS is explained by conventions: the 8 closed switches are 1 mOhm in OpenDSS but ideal in BMOPFTools (28.2 W), and BMOPF's p_loss does not include the earthing shunts (0.5 W). BMOPF 359.0 + 0.5 + 28.2 = 387.6 W vs OpenDSS 386.9 W (0.2 %). Loss breakdown added to validate_network_pinned.jl after solve_pf.

## Stage 10: review, LV9 second feeder, safety checks

**Four-part review (technical, contribution, dataset, writing; AI-assisted, checked by me)**: LV3 pipeline confirmed; LV9 clean DOE confirmed in OpenDSS (1.6537 vs 1.654 kW). Raised: LV9's 16 mm2 code is also used for shared mains; bound-point DOE vs partial export; no thermal limits; wording (kW and V first, screening rule not law); title vs scope (AI not trained yet); dataset not ML-ready yet (spec written).

**Cable data check**: across the CSIRO LV feeders, the 16 mm2 Cu code covers 99 % of service cables (100 % on LV3 and LV9); 4 mm2 appears only in the line-code library. 16 mm2 code 1.49 ohm/km self resistance (about 30 % above the IEC 60228 20 °C value, consistent with a hot-conductor rating), 4 mm2 code 4.57 ohm/km (close to IEC 4.61 at 20 °C), hence ratio 3.07 vs IEC 4.0.

**LV9 (123 customers)**: prepared like LV3; BMOPF vs OpenDSS 0.0007 V with ideal switches (0.54 V from the 1 mOhm switch convention). 16 mm2 segments: 123 drops, 12 shared, 44 stubs.
- Shared cables carry the risk: 12 shared wrong at 0.94 pu: gap 1.46 kW, 259 V, 64 customers over; l_2373 (43 customers) alone 1.33 kW.
- Drops: 6 of 123 matter; harmful when length x ~0.06 V/m > headroom.
- Proportional: +19 % export but each customer at its own limit, so its own record matters.
- Partial export: up to 258.4 V when one phase does not export. Phase-secure DOE: −32 % (LV3: −5 to −10 %).
- Thermal: shared 16 mm2 l_2373 carries 217 A at the voltage-only DOE vs a 110 A rating; thermally limited DOE 2.29 kW (0.94 pu). 4 mm2 rating still needed (AS/NZS 3008.1.1).

**LV3 safety checks**: partial export worst 253.30 V; currents far below ratings (16 mm2 18.6 A).

## Stage 11: dropout-secure DOEs and checks

- Dropout check, LV3 (doe_dropout_lv3.jl): the bound-point DOE went over 253 V in 13 and 28 of 79 cases (snapshot, 12:00); the phase-secure DOE in 8 and 2 of 79, by at most 0.04 V and 0.08 V in the realised reading.
- Dropout-secure DOE, LV3: 4.203 kW (snapshot) and 3.664 kW (12:00); passes all 85 cases, all 4094 on/off combinations at 12:00, and 300 random part-export points (worst 252.92 V).
- Headline redone with the dropout-secure DOE (doe_dropout_records_lv3.jl): gap 1.488 kW (snapshot, 254.62 V) and 1.718 kW (+88.2 %, 255.05 V) at 12:00.
- LV9 dropout-secure DOE: 2.423 / 1.876 / 1.097 kW at 0.94 / 0.97 / 1.00 pu; gaps with 12 shared cables wrong 0.871 / 0.430 / 0.123 kW.
- Verify vs realised on LV9: the verify solution curtailed one inverter (ld2984) to 2347 W where the realised reading gives 2445 W (253.00 vs 253.21 V). Suspected cause: solver tolerance at the 1 MW base; to be confirmed with a tighter-tolerance rerun.

**Open**: 4 mm2 and Al ratings; tolerance rerun; dataset generator (paused for redesign).
