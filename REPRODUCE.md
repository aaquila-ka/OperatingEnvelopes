# How to reproduce the thesis results

Thesis: Learning dynamic operating envelopes from imperfect data (UQ REIT7841, Aaquila Konnimera Akbar)
Last verified: 13 Oct 2026, git commit d2b4d06

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

First-time setup, from C:\thesis\OperatingEnvelopes in PowerShell:

    julia +1.11 --project=bmopf -e "using Pkg; Pkg.instantiate()"

## 2. Network

`data/networks/LV3_55bus_withPV/` is the CSIRO LV3 feeder (55 buses, 500 kVA 11/0.433 kV Dyn transformer, tap 1.025, four-wire, 12 single-phase customers), with these changes from the original:

- Master.dss: source pu = 1.00 (original dataset value; an earlier version had 1.07); `batchedit load..* kw=1` commented out; `Set MaxControlIter=100`
- Transformers.dss: LV winding `bus=B641.1.2.3.4` (star point on the neutral, not ground)
- PVSystems.dss: 12 x 5 kVA / 5 kW PV systems, connected `.x.4` (phase-to-neutral), one InvControl `invall` with AS/NZS 4777.2 Australia A curves; tighter InvControl tolerances
- Loads.dss: all 12 loads = original CSIRO values, 1 kW, 0.539743 kvar (0.88 power factor)

`scripts/bmopf/load_lv3.jl` also fixes the inverter settings after import (see the comments at the top of that file).

## 3. Run order

Start Julia from C:\thesis\OperatingEnvelopes with `julia +1.11 --project=bmopf`, then:

| # | Command | What it does | Output |
|---|---|---|---|
| 1 | `include("scripts/bmopf/load_lv3.jl")` | imports and checks the feeder | results/analyze_lv3_after_ctrlfix.txt |
| 2 | `include("scripts/bmopf/validate_network_pinned.jl")` | BMOPFTools vs OpenDSS with the same pinned PV outputs | results/pf_validation_lv3*.csv |
| 3 | `include("scripts/bmopf/doe_clean_snapshot.jl")` | correct DOEs (the answer key) at 1.00 and 1.03 pu | results/doe_clean_snapshot.csv |
| 4 | `include("scripts/bmopf/doe_dirty_snapshot.jl")` | wrong cable records, Case A and Case B | results/doe_dirty_snapshot.csv |
| 5 | `include("scripts/bmopf/doe_severity_sweep.jl")` | resistance scaled by k = 1 to 3.07 | results/doe_severity_sweep.csv |
| 6 | `include("scripts/bmopf/opendss_check_caseA.jl")` | independent OpenDSS check of the Case A over-voltage | printed only |

The ~46 "from_dss: ... could not be represented" warnings at import are expected (OpenDSS fields like `units` that BMOPF does not need).

## 4. Expected key numbers (to check a rerun)

| Result | Value |
|---|---|
| BMOPFTools vs OpenDSS, phase-to-neutral voltage | within 0.11 V at all 55 buses |
| BMOPFTools vs OpenDSS, neutral voltage | within 0.024 V |
| Clean DOE, 1.00 pu | 4.91 kW per customer, max 245.8 V, inverter-limited |
| Clean DOE, 1.03 pu | 4.529 kW per customer, max 252.7 V, inverter-limited |
| Case A (truth 4 mm², records 16 mm²) | correct 2.734 kW, issued 4.529 kW, +65.6 %; counterfactual 255.12 V (BMOPFTools), 255.2 V (OpenDSS) |
| Case B (truth 16 mm², records 4 mm²) | correct 4.529 kW, issued 2.734 kW, -39.6 % |
| Sweep | under 0.5 % up to k = 1.25; +10.9 % at k = 1.5; +30.5 % at k = 2 |

## 5. Main modelling choices

- Voltage limit: 207 to 253 V phase-to-neutral, checked at each customer's own connection point (not on every phase of every bus).
- DOE allocation: equal export limit for every customer (PowerOptLab fairness = :equal, security = :bound_point).
- Inverters: 5 kVA, Volt-VAr and Volt-Watt on phase-to-neutral voltage, reactive power has priority.
- Cable error: 22 service-cable segments; 16 mm² vs 4 mm² copper using the dataset's own line codes (resistance ratio 3.07).

## 6. Known issues (open, not yet fixed)

1. Resistance ratio: the dataset's line codes give 3.07x for 4 vs 16 mm² copper; IEC 60228 maximum DC values give about 4.0x. The thesis must say which is used and why.
2. Network losses differ by about 7 % between BMOPFTools and OpenDSS (voltages agree). Likely bookkeeping or switch impedance; not yet traced.
3. Only one loading snapshot, one feeder, 5 kVA inverters, equal allocation.
4. Case A issued DOE cannot actually be delivered within 5 kVA under Volt-VAr; the 255 V figure is a counterfactual with the rating relaxed.
5. Transformer xhl = 0.0391918 comes from the original dataset (= sqrt(0.04^2 - 0.008^2)); left unchanged.
6. Using customer-only voltage limits was needed because applying them on every phase was infeasible at bus b1754 phase a (no customer there).

## 7. Where the history is

`scripts/notes/worklog.md` has a dated log of every check, error and fix.