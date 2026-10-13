# How to reproduce the thesis results

Thesis: Learning dynamic operating envelopes from imperfect data (UQ REIT7841, Aaquila Konnimera Akbar)
Last updated 13 Oct 2026, after an independent review. Results produced at git commit ae2dc4f.

## 1. Software (locked)

| Item | Version |
|---|---|
| Julia | 1.11.9 (install with juliaup, run with `julia +1.11`) |
| BMOPFTools.jl | commit b7aa9a1 (github.com/frederikgeth/BMOPFTools.jl) |
| PowerOptLab.jl | commit 953e45c (github.com/frederikgeth/PowerOptLab.jl) |
| JuMP / Ipopt | 1.32.1 / 1.16.0 |
| OpenDSSDirect.jl | 0.9.9 |
| Preferences.jl | pinned at 1.5.2 (1.6 clashes with BMOPFTools at b7aa9a1) |

All thesis scripts use the project in the `bmopf/` folder. Its `Manifest.toml` locks every version above.
The top-level `Project.toml` is the older August 2026 PowerModelsDistribution setup and is NOT used for these results.
Random draws use Julia's MersenneTwister; streams can change between Julia versions, so the scatter factors, changed segments and profile map are also written to the CSVs.

First-time setup, from C:\thesis\OperatingEnvelopes in PowerShell:

    julia +1.11 --project=bmopf -e "using Pkg; Pkg.instantiate()"

## 2. Network and data

`data/networks/LV3_55bus_withPV/` is the CSIRO LV3 feeder (55 buses, 500 kVA 11/0.433 kV Dyn transformer, tap 1.025, four-wire, 12 single-phase customers), with these changes from the original:

- Master.dss: source pu = 1.00 (original dataset value; scripts scale it, usually to 1.03); `batchedit load..* kw=1` commented out; `Set MaxControlIter=100`
- Transformers.dss: LV winding `bus=B641.1.2.3.4` (star point on the neutral, not ground)
- PVSystems.dss: 12 x 5 kVA / 5 kW PV systems, connected `.x.4` (phase-to-neutral), one InvControl `invall` with AS/NZS 4777.2 Australia A curves; tighter InvControl tolerances
- Loads.dss: all 12 loads = original CSIRO values, 1 kW, 0.539743 kvar (0.88 power factor)

`scripts/bmopf/load_lv3.jl` also fixes the inverter settings after import (see the comments at the top of that file).

House usage for the day runs: `data/profiles/TeamNando_OE1_LoadShapes.txt` (Team-Nando OE1-Ideal, commit 96abbab, BSD-3; licence in the same folder).

## 3. Run order

Start Julia from C:\thesis\OperatingEnvelopes with `julia +1.11 --project=bmopf`. For steps 7-11, first run `using Logging; disable_logging(Logging.Warn)` to hide the repeated import warnings, and use a fresh Julia session for each script.

| # | Command | What it does | Output |
|---|---|---|---|
| 1 | `include("scripts/bmopf/load_lv3.jl")` | imports and checks the feeder | results/analyze_lv3_after_ctrlfix.txt |
| 2 | `include("scripts/bmopf/validate_network_pinned.jl")` | BMOPFTools vs OpenDSS with the same pinned PV outputs | results/pf_validation_lv3*.csv |
| 3 | `include("scripts/bmopf/doe_clean_snapshot.jl")` | correct DOEs at 1.00 and 1.03 pu | results/doe_clean_snapshot.csv |
| 4 | `include("scripts/bmopf/doe_dirty_snapshot.jl")` | Case A and Case B (bound-point reading) | results/doe_dirty_snapshot.csv |
| 5 | `include("scripts/bmopf/doe_severity_sweep.jl")` | resistance x k, k = 1 to 3.07 (bound-point reading) | results/doe_severity_sweep.csv |
| 6 | `include("scripts/bmopf/opendss_check_caseA.jl")` | OpenDSS check of the Case A bound-point voltage | printed only |
| 7 | `include("scripts/bmopf/doe_record_errors.jl")` then `run_record_errors(n_draws = 20)` | scatter and wrong-type errors, 1 kW snapshot | results/doe_record_errors.csv |
| 8 | `include("scripts/bmopf/doe_critical_cables.jl")` then `run_critical_cables()` | one cable at a time is 4 mm² | results/doe_critical_cables.csv |
| 9 | `include("scripts/bmopf/doe_timeseries.jl")` then `run_timeseries()` | full day, 48 half-hours, real profiles, sun-limited | results/doe_timeseries.csv, results/timeseries_profile_map.csv |
| 10 | (same session as 9) `run_record_errors_at(25; n_draws = 20)` | the step-7 draws at the 12:00 loads | results/doe_record_errors_1200.csv |
| 11 | `include("scripts/bmopf/doe_source_sweep.jl")` then `run_source_sweep()` | Case A at 1.00-1.035 pu | results/doe_source_sweep.csv |

The ~46 "from_dss: ... could not be represented" warnings at import are expected (OpenDSS fields like `units` that BMOPF does not need).

## 4. Expected key numbers (to check a rerun)

| Result | Value |
|---|---|
| BMOPFTools vs OpenDSS, phase-to-neutral voltage | within 0.11 V at all 55 buses; neutral within 0.024 V |
| Clean DOE, 1 kW snapshot | 4.906 kW at 1.00 pu, 4.529 kW at 1.03 pu (both inverter-limited) |
| Case A, 1 kW snapshot, 1.03 pu | correct 2.734 kW, issued 4.529 kW, gap 1.795 kW (+65.6 %); realised 254.60 V with Volt-Watt (bound-point 255.12 V) |
| Critical cables | 12 of 22 segments matter; l_3432 alone = same DOE as all 22 wrong, realised 254.60 V, 1 customer above 253 V |
| Record errors, 1 kW snapshot | scatter 5-10 %: ≤+0.3 %; 2 wrong cables: 0 to +49.7 %; 5 or 11 wrong: up to +65.7 %, ≤254.60 V |
| Record errors, 12:00 loads | scatter 10 %: -5.7 to +9.3 %, ≤253.20 V; 5 or 11 wrong: up to +117 %, ≤255.15 V |
| Full day, 1.03 pu | clean DOE 4.02-4.48 kW, voltage-limited at all 48 steps; gap 2.0-2.35 kW; sun-limited over-voltage 10:00-16:30, peak 255.02 V at 11:30 |
| Source sweep, 12:00 | gap 0.14 / 0.17 / 0.71 / 1.63 / 2.29 / 0.60 kW at 1.00 / 1.01 / 1.02 / 1.025 / 1.03 / 1.035 pu |

## 5. Main modelling choices

- Voltage limit: 207 to 253 V phase-to-neutral, checked at each customer's own connection point (not on every phase of every bus; with all phases the 1.03 pu DOE is 3.329 kW, binding at B1754 phase a where there is no customer, and the 4 mm² network is infeasible).
- DOE = limit on the inverter's AC output (gross PV), not net export at the meter.
- DOE allocation: equal export limit for every customer (PowerOptLab fairness = :equal, security = :bound_point).
- Inverters: 5 kVA, Volt-VAr and Volt-Watt on phase-to-neutral voltage, reactive priority.
- Source voltage: 1.03 pu for the main results (also used in Geth's PowerOptLab LV3 study); 1.00-1.035 pu in the source sweep.
- Cable error: 22 service-cable segments; 16 mm² vs 4 mm² copper from the dataset's own line codes (resistance ratio 3.07).
- Two readings of what an issued DOE does on the true street: bound-point (everyone exports exactly the DOE, Volt-Watt off; worst case) and realised (everyone may export up to the cap, all inverter laws on; physical). Day runs also cap export by the sun available.

## 6. Known issues and limitations

1. Source voltage drives the size of the error (section 4, source sweep). Team-Nando's MV profile is about 0.99-1.00 pu; the LV operating point depends on the transformer tap. Always quote the error together with the source voltage.
2. Resistance ratio: the dataset's 16 mm² line code (1.49 Ω/km) is about 30 % above the IEC 60228 20 °C maximum (1.15 Ω/km), while its 4 mm² code (4.57 Ω/km) is close to IEC (4.61). The 3.07 ratio is therefore conservative; with 4.0 the reviewer found +149 % and 256.7 V at 12:00 (bound-point).
3. Equal allocation: one critical customer sets everyone's DOE, so one wrong record changes all 12 limits; but physically only the customers on wrong cables go over 253 V. Other fairness rules are not yet tested.
4. One feeder, one day, one set of 12 profiles, 5 kVA inverters.
5. Network losses differ by about 7 % between BMOPFTools and OpenDSS (voltages agree). Not yet traced.
6. Bound-point "delivered" vs realised: in a few cases the realised run trims tens of watts (5 kVA rating with reactive priority) where the bound-point check said delivered; this is within BMOPF's smoothing of the Volt-VAr corners.
7. The severity sweep (file 3) scales only diagonal R; k = 3.07 gives 2.739 kW vs the full line-code swap 2.734 kW (0.2 %).
8. Customer counts above 253 V include marginal cases (253.01 V); read them with the voltage.
9. Case B is the mirror of Case A (lost % = 1/(1 + over-promise) - 1), not separate evidence.
10. Transformer xhl = 0.0391918 comes from the original dataset (= sqrt(0.04^2 - 0.008^2)); left unchanged.
11. The older results files doe_dirty_snapshot.csv and doe_severity_sweep.csv report bound-point voltages only; the realised values for the same cases are in doe_critical_cables.csv, doe_record_errors.csv and doe_source_sweep.csv.

## 7. Where the history is

`scripts/notes/worklog.md` has a dated log of every check, error and fix.
