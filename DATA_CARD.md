# Data card: clean vs dirty DOE results (LV3 feeder)

Every results file, what each column means, and how much to trust it. Start with README.md for the overview and REPRODUCE.md to re-run.

## What this is

Dynamic operating envelopes (DOEs) = the maximum solar export each customer may send at a given moment without breaking network limits. Here the DOE is the limit on the **inverter's AC output (gross PV export)**, not the net export at the meter (house load is modelled separately).

- **Clean DOE (answer key):** computed on the true network.
- **Dirty DOE (issued):** computed from wrong cable records, then applied to the true network to see what really happens.

Network: CSIRO LV3, 12 single-phase customers (4 per phase), 5 kVA inverters with AS/NZS 4777.2 Volt-VAr / Volt-Watt (reactive priority).
How to regenerate everything: see REPRODUCE.md.

## Conventions used in every file

| Item | Meaning |
|---|---|
| Voltages | volts (V), **phase-to-neutral**, at the customer connection point |
| Power | kW, positive = export |
| Voltage limit | 253 V upper (AS 60038:2012), 207 V lower (source to be confirmed, REPRODUCE.md known issue 32), applied at customer connections only |
| Allocation | every customer gets the same limit (equal fairness) |
| Source voltage | 1.03 pu unless a `source_pu` column says otherwise |
| House names | OpenDSS load names, e.g. `ld1291_load_b` = load at bus 1291, phase b |
| gap_kW | issued DOE minus correct DOE (positive = too generous) |
| overpromise_pct | (issued - correct) / correct x 100; grows very large when the correct DOE is small, so always read it with gap_kW |
| Bound-point voltage (`boundpoint_V_noVW`, old) | every customer exports exactly the issued DOE, Volt-Watt switched off; if the 5 kVA rating cannot deliver it, the rating is relaxed and the note says `counterfactual`. Worst case, not physical. |
| Realised voltage (`realised_V_VW`, `*_V_VW`) | every customer MAY export up to the cap; inverters keep Volt-VAr, Volt-Watt and 5 kVA; no voltage limit imposed. This is the physical answer. Checked against a separate OpenDSS model: within 0.03 V. |
| n_customers_over_253 | customers whose realised voltage is above 253.005 V. Many are only 253.01-253.1 V, so read it together with the voltage. |
| curtail_kW | total export the inverters cut back below the cap (5 kVA rating with reactive priority, or Volt-Watt) |

## File 1: results/doe_clean_snapshot.csv

Answer key on the true network, CSIRO loads (1 kW, 0.88 pf per house), two source voltages.
Columns: source_pu, house, export_limit_kW, status. Rows: 24.
Values: 4.906 kW at 1.00 pu, 4.529 kW at 1.03 pu; both limited by the inverter's 5 kVA rating.

## File 2: results/doe_dirty_snapshot.csv (bound-point only, older)

Case A (truth 4 mm², records 16 mm², all 22 service-cable segments, 12 of which feed a home) and Case B (reverse), 1.03 pu.
Columns: case, correct_limit_kW, issued_limit_kW, true_street_max_vpn_V (bound-point), where, note.
Case A +65.6 % (bound-point 255.12 V counterfactual; realised with Volt-Watt 254.60 V with all 12 customers above 253 V and 1.86 kW curtailed, see doe_fairness_summary.csv, equal rule). Case B -39.6 % (Case B is the mirror of Case A).

## File 3: results/doe_severity_sweep.csv (bound-point only, older)

Service-cable resistance x k (diagonal R only), k = 1 to 3.07, 1.03 pu, CSIRO loads.
Columns: k, correct_kW, correct_binding, A_issued_kW, A_overpromise_pct, A_true_street_V (bound-point), A_note, B_issued_kW, B_lost_pct.
Under 0.5 % up to k = 1.25 (inverter-limited); +10.9 % at k = 1.5; +30.5 % at k = 2.

## Files 4 and 5: results/doe_record_errors.csv and results/doe_record_errors_1200.csv

Realistic record errors, 20 seeded draws per level. Records always say all 22 service-cable segments (12 feed a home) are 16 mm².
File 4 = CSIRO 1 kW snapshot (setting `snapshot_1kW`); file 5 = the house loads of 12:00 of the real day (setting `day_1200`), where the voltage limit binds.

| Column | Meaning |
|---|---|
| setting, source_pu | operating point |
| scenario, level | `scatter` (every cable's resistance x its own random factor, sigma 0.05/0.10/0.20) or `wrongtype` (2/5/11 of 22 cables really 4 mm²) |
| draw, seed | draw 1-20 and its seed |
| correct_kW, correct_binding, correct_status | DOE on that draw's true street; binding = inverter / voltage / other |
| issued_kW, gap_kW, overpromise_pct | DOE from the records and the error |
| boundpoint_V_noVW, boundpoint_note | old worst-case reading |
| realised_V_VW, n_customers_over_253, curtail_kW, realised_status | physical reading |
| mean_factor, max_factor, factors | scatter only; `factors` lists all 22 resistance factors in segment order (rebuild a draw without Julia) |
| changed_segments | wrongtype only; which segments are really 4 mm² |

Rows: 120 each.

| Error | 1 kW snapshot (file 4) | 12:00 loads (file 5) |
|---|---|---|
| Scatter 5 % | ±0.1 %, max 252.79 V | -5.2 % to +4.3 % (gap ≤0.18 kW), max 253.09 V |
| Scatter 10 % | -0.2 % to +0.3 %, max 252.88 V | -5.7 % to +9.3 % (gap ≤0.36 kW), max 253.20 V |
| Scatter 20 % | up to +3.8 %, max 253.09 V | -5.8 % to +20.5 % (gap ≤0.72 kW), max 253.44 V |
| 2 wrong cables | 0 to +49.65 %, max 254.19 V, 0-2 customers over | 0 to +76.6 % (median +62 %), max 254.58 V |
| 5 wrong cables | +30.8 to +65.7 %, max 254.60 V, 1-4 over | +66 to +117 %, max 255.15 V, 1-3 over |
| 11 wrong cables | +33 to +65.7 %, max 254.60 V, 4-8 over, curtail ≤1.48 kW | +67 to +117 %, max 255.15 V, 3-7 over |

Meaning: in the inverter-limited snapshot small scatter is hidden; at a voltage-limited moment every resistance error moves the DOE (in both directions), but small scatter causes only small over-voltages (≤0.44 V). Wrong cable types are dangerous in both.

## File 6: results/doe_critical_cables.csv

One cable at a time is really 4 mm² (other 21 correct), 1 kW snapshot, 1.03 pu. Sorted, most harmful first.
Columns: segment, bus_from, bus_to, length (m), correct_kW, correct_binding, correct_status, issued_kW, gap_kW, overpromise_pct, boundpoint_V_noVW, boundpoint_note, realised_V_VW, n_customers_over_253, curtail_kW.
Result: the 12 customer service cables each cause an error (+3.9 % to +65.7 %); the 10 dead-end stubs with no customer cause none (they carry no current). On this 12-home street, customer Ld1291's cable (l_3432, bus B828, 29.5 m) alone gives the same DOE as all 22 wrong (+65.7 %) and a realised 254.60 V (OpenDSS 254.61 V), but only that one customer goes above 253 V (all 22 wrong: all 12 customers, 254.60 V, 1.86 kW curtailed). At this operating point the harm follows the customer's cable length and voltage headroom (n = 12, R² 0.98, leave-one-out 0.96).

## File 7: results/doe_timeseries.csv

One full day, 48 half-hours, real usage per customer (file 8), 1.03 pu. Case A = all 22 service-cable segments (12 feed a home) really 4 mm².

| Column | Meaning |
|---|---|
| step, time, source_pu | half-hour 1-48, start time |
| pv_shape, daylight | the day's solar shape 0-1; daylight = pv_shape > 0 |
| total_load_kW | sum of the 12 customers' usage |
| clean_kW, clean_binding, clean_max_vpn_V, clean_status | answer-key DOE |
| A_correct_kW, A_binding, A_status, A_gap_kW, A_overpromise_pct | Case A correct DOE and the error of the issued (clean) DOE |
| A_boundpoint_V_noVW, A_boundpoint_note | old worst case |
| A_worst_V_VW, A_worst_n_over_253, A_worst_curtail_kW | realised if every customer may export the full DOE |
| pv_cap_kW | sun available per customer = min(DOE, 5 kW x pv_shape) |
| A_pv_V_VW, A_pv_n_over_253, A_pv_curtail_kW | realised, limited by the sun: **the realistic numbers** (NaN at night = no export) |
| B_lost_pct_mirror | Case B, mirror of Case A: 1/(1 + over-promise) - 1 |

Rows: 48. Clean DOE 4.02-4.48 kW, voltage-limited at every step (at 1.03 pu). Issued DOE too generous by 2.0-2.35 kW at every half-hour (meaningful for PV only in daylight). One partly cloudy day (sun peak 3.6 kW per house); on a clear day the sun-limited values move towards the worst-case column. Realistic (sun-limited) over-voltage in 13 half-hours, 10:00-16:30, peak 255.02 V at 11:30, up to 10 of 12 customers above 253 V, no curtailment needed. Mornings, evenings, night: no over-voltage. If every customer could export the full DOE: 254.6-255.3 V.

## File 8: results/timeseries_profile_map.csv

Which real profile each customer uses (load, profile, daily_kWh). Picked from the 99 profiles with the fixed seed RE_SEED = 20261013, the same seed constant the record-error draws use (set in doe_record_errors.jl).
Source: Team-Nando OE1-Ideal, github.com/Team-Nando/OE1-Ideal, commit 96abbab, BSD-3 licence (data/profiles/TeamNando_OE1_LICENSE.txt). Anonymised Victorian smart-meter data, one day, 5-min P and Q (aggregate pf about 0.95), averaged to 30 min.

## File 9: results/doe_source_sweep.csv

Case A at source voltages 1.00-1.035 pu, for the 1 kW snapshot and the 11:00, 12:00, 13:00 loads.
Columns: setting, source_pu, clean_kW, clean_binding, A_correct_kW, A_gap_kW, A_overpromise_pct, A_worst_V_VW, A_worst_n_over_253, A_worst_curtail_kW, pv_cap_kW, A_pv_V_VW, A_pv_n_over_253, A_pv_curtail_kW.

| Source (12:00) | Clean DOE | Gap | Over-promise | Sun-limited realised V |
|---|---|---|---|---|
| 1.00 pu | 4.89 kW (inverter) | 0.14 kW | +3 % | 247.2 V |
| 1.01 pu | 4.79 kW (inverter) | 0.17 kW | +4 % | 249.6 V |
| 1.02 pu | 4.66 kW (inverter) | 0.71 kW | +18 % | 251.9 V |
| 1.025 pu | 4.58 kW (inverter) | 1.63 kW | +55 % | 253.1 V (1 over) |
| 1.03 pu | 4.25 kW (voltage) | 2.29 kW | +117 % | 254.3 V (9 over) |
| 1.035 pu | 1.37 kW (voltage) | 0.60 kW | +78 % | 253.5 V (6 over) |

Meaning: the same record error is harmless when the feeder has voltage headroom and largest around the change from inverter-limited to voltage-limited (about 1.025-1.03 pu here), which is exactly when DOEs start to matter. When the feeder is almost full (1.035 pu) the clean DOE itself collapses, so the gap in kW shrinks again.

## File 10: results/doe_robust.csv

What a utility can do, 1.03 pu, 1 kW snapshot and 12:00 loads.
Columns: setting, source_pu, part, param, verified_segments, clean_kW, all_4mm2_kW, safe_DOE_kW, cost_vs_clean_pct, scenario_check_kW, status.
- Part A (`A_hedge`, param = b): DOE safe if every service cable's resistance is up to b higher. Cost vs clean: 0.1 / 0.2 / 0.4 % (snapshot) and 3.0 / 5.8 / 11.0 % (12:00) for b = 5 / 10 / 20 %. The scenario check (one envelope valid for R x (1-b), R, R x (1+b) and a mixed case with l_3432 at +b and all others at -b) gives the same value to 3 decimals.
- Part B (`B_verify_<order>`, param = k): the 12 customer cables are checked one by one; unchecked ones are assumed 4 mm². Orders: longest_first, opf_ranked (from file 6), shortest_first. At 12:00 the safe DOE goes 1.96 kW (k = 0) -> 2.43 kW (k = 1) -> about 2.55 kW (k = 7-9) -> 3.12 kW (k = 10, opf_ranked; 2.55 longest_first) -> 4.25 kW (k = 11). Shortest_first recovers nothing until k = 12. Under equal allocation, checking pays off only when (nearly) all customer cables are checked.
- Note: the DOE is very slightly non-monotone in single-cable resistance (Volt-VAr coupling between customers, confirmed in OpenDSS), so a few steps drop by up to 0.02 kW.

## Files 11 and 12: results/doe_fairness_summary.csv and results/doe_fairness_customers.csv

Three sharing rules (PowerOptLab fairness :equal, :proportional, :max_min; max_min is two-stage: raise the minimum, then the total), 1.03 pu, 1 kW snapshot and 12:00 loads. Cases: only l_3432 wrong (Ld1291), only l_4155 wrong (Ld1668), all 22 wrong.
Summary columns: setting, source_pu, policy, case, issued_total/min/max_kW, correct_total/min_kW, n_customers_changed (limit changes by > 0.05 kW), total_gap_kW, max_gap_kW, max_gap_customer, realised_V_VW, n_customers_over_253, curtail_kW, customers_over_253 (bus and phase), statuses.
Customer file: setting, source_pu, policy, case, customer, issued_kW, correct_kW, gap_kW (216 rows: per-customer labels for learning).

| One wrong record (l_3432) | Equal | Proportional | Max-min |
|---|---|---|---|
| Customers whose correct limit changes | 12 of 12 | 1 of 12 | 8-10 of 12 |
| Total wrongly allocated export | 21.6 kW (snapshot), 27.5 kW (12:00) | 1.9 / 2.4 kW (about 12x less) | 14.3 / 18.8 kW |
| Affected customer's correct limit | 2.73 / 1.96 kW | 2.68 / 1.88 kW (lower) | 2.75 / 1.98 kW |
| Realised outcome (same for all rules) | 254.60 V / 255.15 V at bus B828 phase b only; about 0.46-0.49 kW curtailed | same | same |

Meaning: the safety harm of one wrong record is local and the same under every rule (the wrongly recorded customer's voltage rises). The rule only decides whose limits absorb the correction: everyone's under equal, only the affected customer's under proportional (who then carries all of it). For a mild cable (l_4155) at 12:00 no customer exceeds 253 V under any rule. When all 22 cables are wrong the error spreads under every rule, and proportional gives more curtailment (3.3 vs 0.9 kW at 12:00). Proportional raises total clean export at 12:00 (54.2 vs 51.0 kW) at the cost of a lower minimum limit (4.23 vs 4.25 kW); at the snapshot the gain is negligible (54.6 vs 54.4 kW).

## File 13: results/doe_ratio.csv

Cable resistance ratio, Case A (all 22 service-cable segments really thinner), 1.03 pu, 1 kW snapshot, 11:30 and 12:00.
Variants: `dataset_4mm2_code` (the dataset's 4 mm² code, ratio 3.07, as everywhere else), `diagR_x3.07` (16 mm² code with diagonal R x 3.07; matches the swap within 0.005 kW), `diagR_x4.00_IEC` (diagonal R x 4.0, a higher test ratio; the `IEC` in the name is only a label, the 3.07 used everywhere else comes from the dataset's own line codes).
Columns: setting, source_pu, variant, clean_kW, correct_kW, gap_kW, overpromise_pct, worst_V_VW, worst_n_over_253, worst_curtail_kW, pv_cap_kW, pv_V_VW, pv_n_over_253, pv_curtail_kW.

| Moment | Gap 3.07 -> 4.0 | Over-promise 3.07 -> 4.0 | Realised V (Volt-Watt on) 3.07 -> 4.0 |
|---|---|---|---|
| 1 kW snapshot | 1.80 -> 2.14 kW | +66 % -> +90 % | 254.60 -> 255.10 V (worst case) |
| 11:30 | 2.30 -> 2.64 kW | +122 % -> +170 % | 255.02 -> 255.77 V (sun-limited) |
| 12:00 | 2.29 -> 2.63 kW | +117 % -> +162 % | 254.29 -> 255.12 V (sun-limited) |

Meaning: a higher ratio of 4.0 adds about 0.35 kW to the gap and 0.5-0.8 V to the peak, so if the real ratio is larger than the dataset's 3.07, the results would be worse, not better.

## File 14: results/doe_clearsky.csv

Same as file 7 (same columns) but with a clear-sky solar shape: a half-sine over the measured day's sun hours (05:30-21:00) with an ASSUMED peak of 0.85 x 5 kW = 4.25 kW per house (typical clear summer output after heat and system losses; the measured day peaks at 0.72). Only sunny half-hours (31 rows).
Result: a customer is above 253 V in 21 half-hours (07:30-17:30), peak 255.22 V, up to 12 of 12 customers, curtailment up to 0.61 kW (11:00-15:00). Compare the measured cloudy day: 13 half-hours, peak 255.02 V. The DOE gap (about 2.3 kW) does not depend on the weather; how much of it becomes over-voltage does.

## File 15: results/doe_verify_proportional.csv

Checking the 12 customer cables one by one (unchecked = 4 mm²), under proportional and equal sharing, 1.03 pu, 1 kW snapshot and 12:00.
Columns: setting, source_pu, order (opf_ranked / shortest_first), k_checked, checked_segments, clean_total_prop_kW, prop_total_kW, prop_share_pct, prop_min_kW, equal_total_kW, equal_share_pct, statuses.

| 12:00, share of the all-records-right total | k = 0 | 3 | 6 | 9 | 11 |
|---|---|---|---|---|---|
| Proportional, OPF-ranked | 64 % | 75 % | 84 % | 94 % | 100 % |
| Proportional, shortest first | 64 % | 71 % | 82 % | 89 % | 96 % |
| Equal, OPF-ranked | 46 % | 57 % | 60 % | 60 % | 100 % |
| Equal, shortest first | 46 % | 46 % | 46 % | 46 % | 46 % |

Meaning: under proportional sharing every checked record releases that customer's export at once (about 2-3 points per cable, in any order); under equal sharing checking pays off only at the end. Trade-off: under proportional the unchecked customer keeps a low limit (smallest limit at 12:00 before the last check: 1.88-1.95 kW in shortest-first order, 1.95-3.14 kW in OPF-ranked order). Under equal sharing in OPF-ranked order the share goes 46 % -> 57 % (1-5 checks) -> 60 % (6-9) -> 73 % (10) -> 100 % (11); in shortest-first order it stays at 46 % until all 12 are checked.

## Files 16-18: LV3 safety checks (results/doe_partial_lv3.csv, results/cable_currents_lv3.csv, results/doe_phase_secure_lv3.csv)

- Partial export (clean equal DOE on the correct network, 7 phase patterns, realised with Volt-VAr/Volt-Watt/5 kVA): worst 253.19 V (1 kW snapshot) and 253.30 V (12:00), up to 3 customers just above 253 V.
- Cable currents at the clean DOE: 16 mm2 service cables at most 18.6 A, 240 mm2 Al mains 36.8 A, 400 mm2 Al 73.3 A; far below ratings (16 mm2 Cu 4-core XLPE: 110 A buried / 81 A in duct, Prysmian datasheet). Thermal limits do not bind on LV3.
- Phase-secure equal DOE (highest equal limit safe for all 7 phase patterns, bisection with verify_operating_envelope): 4.313 kW vs 4.529 kW (-4.8 %, snapshot) and 3.841 vs 4.253 kW (-9.7 %, 12:00).

## Files 19-22: LV3 dropout-secure DOE

Why: a DOE checked only with everyone exporting (bound point), or with whole phases silent (phase-secure), can still break 253 V when SOME customers export nothing. "Dropped" = that customer's export cap is 0; everyone else may export up to the DOE; realised reading. The idea comes from Liu and Braslavsky (IEEE Access, 2022) and PowerOptLab's `doe_dropout_utilizations` (F. Geth); see ACKNOWLEDGEMENTS.md.

| File | Content | Key numbers |
|---|---|---|
| results/doe_dropout_lv3.csv | bound-point and phase-secure DOEs vs nobody + every 1 or 2 dropped customers (79 cases), snapshot and 12:00 | bound-point: 13 / 28 of 79 cases over 253 V (worst 253.16 / 253.30 V); phase-secure: 8 / 2 of 79 (253.04 / 253.08 V); the phase-secure snapshot failures all involve ld1895_load_b dropped |
| results/doe_dropout_secure_lv3.csv | dropout-secure equal DOE (85 cases: nobody, 7 phase patterns, all 1- and 2-customer dropouts) | 4.203 kW snapshot, 3.664 kW 12:00 (-7.2 % / -13.8 % vs bound point); final check 0 of 85 over 253 V |
| results/doe_dropout_lv3_full_day_1200_dropout_secure.csv | the 12:00 dropout-secure DOE vs all 4094 on/off combinations (`mask`: bit i = i-th customer in sorted id order dropped) | 0 of 4094 over 253 V; worst 253.00 V with all 4 phase-a customers silent |
| results/doe_dropout_records_lv3.csv | headline redone: dropout-secure DOE from the records (16 mm2) applied on the true network; correct dropout-secure DOE on the true network | snapshot: gap 1.488 kW (+54.8 %), 254.62 V; 12:00: gap 1.718 kW (+88.2 %), 255.05 V; all 22 wrong: 85 of 85 cases over 253 V; l_3432 only: 70 of 85, same correct DOE |

Meaning: securing the DOE against customer behaviour (dropouts) does not secure it against wrong records; every check uses the same wrong network. The dropout-secure limit still trusts the records; a limit that assumes the worst cable everywhere is safe but gives up about half the export (file 10: 1.959 vs 4.253 kW at 12:00).

## Second feeder: CSIRO LV9 (results/lv9/)

LV9: 258 buses, 123 single-phase customers (41 per phase), 500 kVA, HV tap 1.000 (LV9 is about 2.5 % higher than LV3 at the same source pu). Prepared like LV3 (scripts/bmopf/lv9/prepare_lv9.jl). The 16 mm2 line code is used for 123 customer drops, 12 shared segments (carrying 1-43 customers) and 44 dead-end stubs.

| File | Content | Key numbers |
|---|---|---|
| lv9_check.csv / lv9_check_idealsw.csv | BMOPF vs OpenDSS, same 123 inverter P/Q pinned, 774 LV phase-neutral voltages | 0.54 V mean (OpenDSS 1 mOhm switches); 0.0007 V with ideal switches in both tools |
| lv9_segments.csv | kind (drop / upstream / stub), customers downstream, length of every 16 mm2 segment | |
| lv9_sweep.csv | Case A by kind at 0.94 / 0.97 / 1.00 pu (equal, voltage only) | drops wrong: gap 0.24 / 0.17 / 0.03 kW, up to 254.6 V; 12 shared wrong: gap 1.46 / 0.87 / 0.39 kW, up to 259.2 V, up to 64 customers above 253 V |
| lv9_single_upstream_0.94.csv | each shared segment alone | l_2373 (43 customers, 68.7 m): gap 1.33 kW, 257.9 V, 43 over; l_3443 (28): 0.88 kW |
| lv9_single_drops_0.94.csv | each of the 123 drops alone, with length, distance, clean headroom | 6 of 123 change the DOE by > 0.01 kW (max 0.27 kW, 254.86 V, l_747); rule: harmful when length x ~0.06 V/m > headroom |
| lv9_fairness.csv | equal vs proportional at 0.94 pu | proportional +19 % total (525 vs 441 kW) but exposes individual records (165 m drop: no effect under equal, 254.2 V under proportional) |
| lv9_partial.csv | partial export, 7 phase patterns | up to 258.36 V (0.94 pu) / 257.74 V (1.00 pu), up to 28 customers over |
| lv9_cable_currents.csv | highest current per segment kind at the clean DOE | shared 16 mm2 l_2373: 217 A (0.94 pu) / 153 A (1.00 pu) vs 110 A buried rating |
| lv9_thermal.csv | DOE with current limits (16 mm2 110 or 81 A, 120 mm2 345 A) | clean DOE thermally limited by l_2373: 2.29 kW (0.94 pu, 110 A), 1.04 kW (1.00 pu, 110 A); drop errors then negligible; shared-cable case incomplete (no 4 mm2 rating) |
| lv9_phase_secure.csv | phase-secure equal DOE | 2.445 vs 3.587 kW (-31.8 %, 0.94 pu); 1.111 vs 1.654 kW (-32.8 %, 1.00 pu) |
| lv9_dropout_check.csv | phase-secure DOE vs 130 cases (nobody, 6 phase patterns, each of 123 customers dropped) | all single dropouts pass; "only_bc_export" 253.20 V (0.94 pu) / 253.13 V (1.00 pu) |
| lv9_dropout_diagnostic.csv | per phase pattern: verify_operating_envelope verdict next to the realised voltage | verify says feasible for all 7 patterns, realised "bc" is 0.13-0.20 V above 253 V (see REPRODUCE.md item 20) |
| lv9_dropout_secure.csv | dropout-secure equal DOE (realised reading, 130 cases) | 2.423 kW (0.94 pu, -0.9 % vs phase-secure), 1.097 kW (1.00 pu, -1.3 %); 0 of 130 over 253 V |
| lv9_dropout_records.csv | headline redone with the dropout-secure DOE | 0.94 pu: 12 shared wrong gap 0.871 kW (+56.1 %), 258.93 V, 127 of 130 cases over; l_2373 only gap 0.821 kW (+51.3 %), 258.42 V; 1.00 pu: 12 shared gap 0.123 kW (+12.7 %), 254.13 V, 2 of 130; l_2373 only: no gap (DOE limited by source voltage, cable carries little current) |

## Files not described above

| File | What it is |
|---|---|
| results/pf_validation_lv3_pinned.csv | BMOPFTools vs OpenDSS on LV3 with the same pinned inverter P and Q (REPRODUCE.md step 2). Columns: bus, quantity (a-n, b-n, c-n, n-g), v_opendss_V, v_bmopf_V, diff_V. Largest phase-to-neutral difference 0.103 V, neutral 0.024 V. |
| results/pf_validation_lv3.csv | the unpinned comparison (step 34), same columns. Not a like-for-like test (REPRODUCE.md known issue 25). |
| results/doe_partial_util_lv3.csv | the LV3 dropout-secure DOE against 300 random part-export mixes per setting (step 32). Columns: setting, source_pu, dropout_secure_kW, point, kind, realised_V_VW, n_customers_over_253, result, fractions_sorted_ids. 0 of 300 over 253 V in each setting. |
| results/lv9/lv9_midpoint_0.97.csv | LV9 dropout-secure DOE and headline at 0.97 pu (step 31). |
| results/lv9/lv9_verify_diag.csv | LV9 verify vs realised reading, customer by customer (step 33, known issue 20). |
| results/analyze_lv3_after_ctrlfix.txt | BMOPFTools network report for LV3 after the inverter-settings fix (step 1): 0 errors. |
| results/analyze_lv3_after_pvfix.txt | the same report from an earlier stage (after the PV connection fix, before the inverter-settings fix): 2 errors, both about the inverter curves. Kept for history. |
| results/lv9/analyze_lv9.txt | BMOPFTools network report for LV9 (step 20). |
| results/dataset/pool_check.txt | output of check_pool() in scripts/bmopf/dataset/pool_profiles.jl (step 35): pool file checks and the OE1 cross-check. |
| results/linecode_usage.csv | cable types used on LV3 (from the early script scripts/count_linecodes.jl). Early exploration, not a thesis result. |
| results/sensitivity_service_cable.csv | early cable sweep on an older model state (scripts/sensitivity_service_cable.jl). Not a thesis result (REPRODUCE.md known issue 31). |
| results/doe_dirty_snapshot_origloads.csv | from an earlier version of the code (scripts/bmopf/doe_dirty_origloads.jl); kept for history only (REPRODUCE.md known issue 30). |

## How much to trust it

- Network model checked against OpenDSS: phase-to-neutral voltages within 0.11 V, neutral within 0.024 V, losses within 0.8 W once the switch and earthing modelling difference is accounted for (see REPRODUCE.md section 6, item 5).
- Cross-check: a separate rebuild directly in OpenDSS (Python, not using the thesis scripts; written with AI assistance and checked by the author; its files are not included in this repository) reproduced the clean snapshot DOE (4.527 vs 4.529 kW, all customer voltages within 0.03 V), the l_3432 case (2.764 vs 2.734 kW; realised 254.61 vs 254.60 V) and the 12:00 step with 6 random sets of houses (clean 3.97-4.18 kW voltage-limited, Case A +97 to +119 %).
- Second cross-check: realised readings match an exact OpenDSS model within 0.03 V; sun-limited 11:30 and 12:00 values fall inside the OpenDSS ranges over 6 random profile sets; the non-monotone steps in file 10 reproduce in OpenDSS.
- Seeded draws rerun identically (same Julia version).
- curtail_kW mixes Volt-Watt and 5 kVA cutback, and BMOPF's smoothed Volt-Watt corner overstates it by about 5 % when many customers sit just above 253 V (all 22 wrong: 1.86 vs 1.78 kW with the exact curve). Voltages are not affected.
- Limitations: see REPRODUCE.md section 6.

## Not in the data yet (planned)

- LV9: day runs, record-error draws, 4 mm2 and aluminium current ratings (shared-cable thermal case).
- More measured days and other sets of house profiles. The current day is day index 350 of the AusNet pool (the lowest-demand day in the dataset); Team-Nando's 342-household x 365-day pool is the planned source for more days.
- LV9 pair dropouts (7503 cases). (LV9 at 0.97 pu with the dropout-secure DOE is done: results/lv9/lv9_midpoint_0.97.csv.)
