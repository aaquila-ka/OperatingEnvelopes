# Data card: clean vs dirty DOE results (LV3 feeder)

## What this is

Dynamic operating envelopes (DOEs) = the maximum solar export (kW) each customer may send to the grid at a given moment without breaking network limits.

- **Clean DOE (answer key):** computed on the true network.
- **Dirty DOE (issued):** computed on a network whose cable records are wrong, then applied to the true network to see what really happens.

Network: CSIRO LV3, 12 single-phase customers (4 per phase), 5 kVA inverters with AS/NZS 4777.2 Volt-VAr / Volt-Watt.
Loads: original CSIRO values (1 kW, 0.539743 kvar each). One snapshot (not a time series yet).
How to regenerate: see REPRODUCE.md.

## Conventions used in every file

| Item | Meaning |
|---|---|
| Voltages | volts (V), **phase-to-neutral**, at the customer connection point |
| Power | kilowatts (kW), positive = export to the grid |
| Voltage limit | 253 V upper, 207 V lower (AS 61000.3.100) |
| Allocation | every customer gets the same limit (equal fairness) |
| House names | OpenDSS load names, e.g. `ld1291_load_b` = load at bus 1291 on phase b |
| Solver status | Ipopt status; `LOCALLY_SOLVED` = solved normally |

## File 1: results/doe_clean_snapshot.csv

The answer key on the true network, at two transformer source voltages.

| Column | Meaning | Unit |
|---|---|---|
| source_pu | source voltage setting (1.00 = original dataset, 1.03 = stressed case) | per unit |
| house | customer name | text |
| export_limit_kW | correct DOE for that customer | kW |
| status | solver result | text |

Rows: 24 (12 customers x 2 source voltages). All `LOCALLY_SOLVED`.
Values: 4.906345 kW at 1.00 pu, 4.529316 kW at 1.03 pu. Both are limited by the inverter's 5 kVA rating (it must absorb reactive power above 240 V), not by the 253 V voltage limit.

## File 2: results/doe_dirty_snapshot.csv

The two wrong-record cases at 1.03 pu, applied to the 22 service-cable segments.

| Column | Meaning | Unit |
|---|---|---|
| case | A = truth 4 mm², records say 16 mm²; B = truth 16 mm², records say 4 mm² | text |
| correct_limit_kW | DOE on the true network | kW |
| issued_limit_kW | DOE on the wrong-records network (what the operator would send) | kW |
| true_street_max_vpn_V | highest customer phase-to-neutral voltage when every customer exports the issued limit on the true network | V |
| where | bus and phase of that highest voltage | text |
| note | `delivered` = inverters can export that much; `undeliverable within 5 kVA under Volt-VAr` = they cannot, so the voltage is a counterfactual with the 5 kVA rating relaxed | text |

Rows: 2.
Over-promise % = (issued - correct) / correct x 100. Case A = +65.6 %, Case B = -39.6 % (safe export lost).

## File 3: results/doe_severity_sweep.csv

Same as Case A/B but the service-cable resistance is multiplied by k (only the cables' own resistance; see REPRODUCE.md known issue 7). Source 1.03 pu.

| Column | Meaning | Unit |
|---|---|---|
| k | resistance multiplier on the true network (1 = records are right) | - |
| correct_kW | DOE on the true network | kW |
| correct_binding | what limits the correct DOE: `inverter` (5 kVA rating) or `voltage` (253 V) | text |
| A_issued_kW | DOE issued from records that say k = 1 (records too optimistic) | kW |
| A_overpromise_pct | (A_issued - correct) / correct x 100 | % |
| A_true_street_V | highest customer voltage on the true network at the issued limit | V |
| A_note | `delivered` or `undeliverable (5 kVA); counterfactual` (as in file 2) | text |
| B_issued_kW | DOE issued when records say k but truth is k = 1 (records too pessimistic) | kW |
| B_lost_pct | (B_issued - correct) / correct x 100, negative = safe export wasted | % |

Rows: 7 (k = 1.00, 1.10, 1.25, 1.50, 2.00, 2.50, 3.07).
Key pattern: up to k = 1.25 the inverter rating hides the error (under 0.5 %); from k = 1.5 the voltage limit binds and the error passes into the DOE. At k = 1.5 and 2.0 the over-promise is delivered and causes a real over-voltage (253.27 V, 253.81 V).

## File 4: results/doe_record_errors.csv

Realistic record errors, many seeded random draws (source 1.03 pu). Records always say all 22 service cables are 16 mm2; the true street differs.

| Column | Meaning | Unit |
|---|---|---|
| scenario | `scatter` = every service cable's resistance x its own random factor; `wrongtype` = some cables are really 4 mm2 | text |
| level | scatter: sigma of the factor (0.05, 0.10, 0.20); wrongtype: number of wrong cables (2, 5, 11 of 22) | - |
| draw | draw number 1 to 20 | - |
| seed | random seed for this draw (rebuilds it exactly) | - |
| correct_kW, correct_binding, correct_status | DOE on that draw's true street | kW / text |
| issued_kW | DOE on the records (4.529 kW for every draw) | kW |
| overpromise_pct | (issued - correct) / correct x 100 | % |
| true_street_max_vpn_V | highest customer voltage when the issued DOE is exported on the true street | V |
| note | `delivered` or `undeliverable (5 kVA); counterfactual` | text |
| mean_factor, max_factor | scatter only: mean and largest resistance factor of the 22 cables | - |
| changed_segments | wrongtype only: which segments are really 4 mm2 | text |

Rows: 120 (2 scenarios x 3 levels x 20 draws). Running it twice gives identical rows.
Summary: scatter 5-10 % has no effect (max +0.3 %); scatter 20 % up to +3.8 % (4 of 20 draws real over-voltage); 2 wrong cables: mean +26.6 %, 0 to +49.7 % depending on which cables; 5 or 11 wrong cables: mean +50 to +54 %, up to the full +65.7 %.

## File 5: results/doe_critical_cables.csv

One cable at a time is really 4 mm2 (the other 21 correct). Same columns as file 2, plus segment, bus_from, bus_to, length (km). Sorted, most harmful first.
Result: the 12 customer service cables each cause an over-promise (+3.9 % to +65.7 %); the 10 cables with no customer behind them cause none. The cable of customer Ld1291 (l_3432, bus B828, 29.5 m) alone gives the full Case A over-promise (+65.7 %). Among customer cables, the harm follows cable length and how close the customer already is to 253 V.

## File 6: results/doe_timeseries.csv

One full day, 48 half-hour steps. Each customer follows its own real usage profile (see file 7). Source fixed at 1.03 pu.

| Column | Meaning | Unit |
|---|---|---|
| step, time | half-hour number 1-48 and its start time | - |
| pv_shape | solar shape of the day, 0-1 (0 = no sun); for reference only, the DOE does not depend on it | - |
| total_load_kW | sum of the 12 customers' usage at that half-hour | kW |
| clean_kW, clean_binding, clean_max_vpn_V, clean_status | answer-key DOE (records correct), what limits it, highest customer voltage, solver status | kW / text / V |
| A_correct_kW, A_binding, A_status | Case A: correct DOE when all 22 service cables are really 4 mm2 | kW / text |
| A_overpromise_pct | clean DOE issued from 16 mm2 records vs correct: (clean - A_correct) / A_correct x 100 | % |
| A_true_street_V, A_note | highest customer voltage when the issued DOE is exported on the 4 mm2 street; delivered or counterfactual | V / text |
| B_lost_pct | Case B: DOE issued from 4 mm2 records on a 16 mm2 street vs correct: (A_correct - clean) / clean x 100 | % |
| B_true_street_V, B_note | highest customer voltage in Case B | V / text |

Rows: 48. Clean DOE 4.02-4.48 kW, voltage-limited at every step. Case A +87 % to +135 % (mean +117 %), real street 254.9-255.8 V, delivered in 45 of 48 steps. Case B -47 % to -58 % (mean -54 %).
Note: with real (lower) usage the inverter buffer seen in the 1 kW snapshot disappears, so the snapshot understated the error.

## File 7: results/timeseries_profile_map.csv

Which real profile each customer uses (load, profile name in TeamNando_OE1_LoadShapes.txt, daily kWh). Picked with seed 20261013 from the 99 profiles.
Source: Team-Nando OE1-Ideal, github.com/Team-Nando/OE1-Ideal, commit 96abbab, BSD-3 licence (data/profiles/TeamNando_OE1_LICENSE.txt). Anonymised Victorian smart-meter data, one day, 5-min P and Q, averaged to 30 min.

## How much to trust it

- Network model checked against OpenDSS: phase-to-neutral voltages within 0.11 V, neutral within 0.024 V.
- Case A over-voltage confirmed independently in OpenDSS (255.2 V vs 255.12 V).
- Limitations: one feeder, one snapshot, equal allocation, 5 kVA inverters, cable ratio 3.07 from the dataset (IEC gives about 4.0). See REPRODUCE.md section 6.

## Not in the data yet (planned)

- Voltage at every customer and an independent "passed check" flag for each DOE.
- Time series (48 half-hour steps of one day).
- Realistic random record errors (scatter per cable, wrong cable type on some cables, all-default records).