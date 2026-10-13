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

## How much to trust it

- Network model checked against OpenDSS: phase-to-neutral voltages within 0.11 V, neutral within 0.024 V.
- Case A over-voltage confirmed independently in OpenDSS (255.2 V vs 255.12 V).
- Limitations: one feeder, one snapshot, equal allocation, 5 kVA inverters, cable ratio 3.07 from the dataset (IEC gives about 4.0). See REPRODUCE.md section 6.

## Not in the data yet (planned)

- Voltage at every customer and an independent "passed check" flag for each DOE.
- Time series (48 half-hour steps of one day).
- Realistic random record errors (scatter per cable, wrong cable type on some cables, all-default records).