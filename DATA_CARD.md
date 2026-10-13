# Data card: clean vs dirty DOE results (LV3 feeder)

Last updated 13 Oct 2026 (after two independent reviews; see "How much to trust it").

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
| Voltage limit | 253 V upper, 207 V lower (AS 61000.3.100), applied at customer connections only |
| Allocation | every customer gets the same limit (equal fairness) |
| Source voltage | 1.03 pu unless a `source_pu` column says otherwise |
| House names | OpenDSS load names, e.g. `ld1291_load_b` = load at bus 1291, phase b |
| gap_kW | issued DOE minus correct DOE (positive = too generous) |
| overpromise_pct | (issued - correct) / correct x 100; grows very large when the correct DOE is small, so always read it with gap_kW |
| Bound-point voltage (`boundpoint_V_noVW`, old) | every customer exports exactly the issued DOE, Volt-Watt switched off; if the 5 kVA rating cannot deliver it, the rating is relaxed and the note says `counterfactual`. Worst case, not physical. |
| Realised voltage (`realised_V_VW`, `*_V_VW`) | every customer MAY export up to the cap; inverters keep Volt-VAr, Volt-Watt and 5 kVA; no voltage limit imposed. This is the physical answer. Checked against independent OpenDSS: within 0.03 V. |
| n_customers_over_253 | customers whose realised voltage is above 253.005 V. Many are only 253.01-253.1 V, so read it together with the voltage. |
| curtail_kW | total export the inverters cut back below the cap (5 kVA rating with reactive priority, or Volt-Watt) |

## File 1: results/doe_clean_snapshot.csv

Answer key on the true network, CSIRO loads (1 kW, 0.88 pf per house), two source voltages.
Columns: source_pu, house, export_limit_kW, status. Rows: 24.
Values: 4.906 kW at 1.00 pu, 4.529 kW at 1.03 pu; both limited by the inverter's 5 kVA rating.

## File 2: results/doe_dirty_snapshot.csv (bound-point only, older)

Case A (truth 4 mm², records 16 mm², all 22 service cables) and Case B (reverse), 1.03 pu.
Columns: case, correct_limit_kW, issued_limit_kW, true_street_max_vpn_V (bound-point), where, note.
Case A +65.6 % (bound-point 255.12 V counterfactual; realised with Volt-Watt 254.60 V with all 12 customers above 253 V and 1.86 kW curtailed, see doe_fairness_summary.csv, equal rule). Case B -39.6 % (Case B is the mirror of Case A).

## File 3: results/doe_severity_sweep.csv (bound-point only, older)

Service-cable resistance x k (diagonal R only), k = 1 to 3.07, 1.03 pu, CSIRO loads.
Columns: k, correct_kW, correct_binding, A_issued_kW, A_overpromise_pct, A_true_street_V (bound-point), A_note, B_issued_kW, B_lost_pct.
Under 0.5 % up to k = 1.25 (inverter-limited); +10.9 % at k = 1.5; +30.5 % at k = 2.

## Files 4 and 5: results/doe_record_errors.csv and results/doe_record_errors_1200.csv

Realistic record errors, 20 seeded draws per level. Records always say all 22 service cables are 16 mm².
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
| 2 wrong cables | 0 to +49.7 %, max 254.19 V, 0-2 customers over | 0 to +76.6 % (median +62 %), max 254.58 V |
| 5 wrong cables | +30.8 to +65.7 %, max 254.60 V, 1-4 over | +66 to +117 %, max 255.15 V, 1-3 over |
| 11 wrong cables | +33 to +65.7 %, max 254.60 V, 4-8 over, curtail ≤1.48 kW | +67 to +117 %, max 255.15 V, 3-7 over |

Meaning: in the inverter-limited snapshot small scatter is hidden; at a voltage-limited moment every resistance error moves the DOE (in both directions), but small scatter causes only small over-voltages (≤0.44 V). Wrong cable types are dangerous in both.

## File 6: results/doe_critical_cables.csv

One cable at a time is really 4 mm² (other 21 correct), 1 kW snapshot, 1.03 pu. Sorted, most harmful first.
Columns: segment, bus_from, bus_to, length (m), correct_kW, correct_binding, correct_status, issued_kW, gap_kW, overpromise_pct, boundpoint_V_noVW, boundpoint_note, realised_V_VW, n_customers_over_253, curtail_kW.
Result: the 12 customer service cables each cause an error (+3.9 % to +65.7 %); the 10 dead-end stubs with no customer cause none (they carry no current). Customer Ld1291's cable (l_3432, bus B828, 29.5 m) alone gives the same DOE as all 22 wrong (+65.7 %) and a realised 254.60 V (OpenDSS 254.61 V), but only that one customer goes above 253 V (all 22 wrong: all 12 customers, 254.60 V, 1.86 kW curtailed). At this operating point the harm follows the customer's cable length and voltage headroom (n = 12, R² 0.98, leave-one-out 0.96).

## File 7: results/doe_timeseries.csv

One full day, 48 half-hours, real usage per customer (file 8), 1.03 pu. Case A = all 22 service cables really 4 mm².

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

Which real profile each customer uses (load, profile, daily_kWh). Picked with seed 20261013 from the 99 profiles.
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

## How much to trust it

- Network model checked against OpenDSS: phase-to-neutral voltages within 0.11 V, neutral within 0.024 V.
- Independent review (13 Oct 2026): a separate rebuild in OpenDSS (Python, not our code) reproduced the clean snapshot DOE (4.527 vs 4.529 kW, all customer voltages within 0.03 V), the l_3432 case (2.764 vs 2.734 kW; realised 254.61 vs 254.60 V) and the 12:00 step with 6 random sets of houses (clean 3.97-4.18 kW voltage-limited, Case A +97 to +119 %).
- Second independent review: realised readings match an exact OpenDSS model within 0.03 V; sun-limited 11:30 and 12:00 values fall inside the OpenDSS ranges over 6 random profile sets; the non-monotone steps in file 10 reproduce in OpenDSS.
- Seeded draws rerun identically (same Julia version).
- curtail_kW mixes Volt-Watt and 5 kVA cutback, and BMOPF's smoothed Volt-Watt corner overstates it by about 5 % when many customers sit just above 253 V (all 22 wrong: 1.86 vs 1.78 kW with the exact curve). Voltages are not affected.
- Limitations: see REPRODUCE.md section 6.

## Not in the data yet (planned)

- A second feeder; more days (including a clear-sky day); the cable resistance ratio of about 4.0 from IEC 60228.
- Checking records under proportional allocation (expected to pay off customer by customer).
