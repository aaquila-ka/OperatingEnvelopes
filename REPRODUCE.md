# How to reproduce the thesis results

Thesis: Learning dynamic operating envelopes from imperfect data (UQ REIT7841, Aaquila Konnimera Akbar)
Main results were produced at git commit ae2dc4f; later results were added afterwards (see the git log for the exact version of every file).

New here? Start with README.md for a plain-English overview.

## 1. Software (locked)

| Item | Version |
|---|---|
| Julia | 1.11.9 (install with juliaup, run with `julia +1.11`) |
| BMOPFTools.jl | commit b7aa9a1 (github.com/frederikgeth/BMOPFTools.jl) |
| PowerOptLab.jl | commit 953e45c (github.com/frederikgeth/PowerOptLab.jl) |
| JuMP / Ipopt | 1.32.1 / 1.16.0 |
| OpenDSSDirect.jl | 0.9.9 |
| Preferences.jl | pinned at 1.5.2 (1.6 is incompatible with BMOPFTools at b7aa9a1) |

All thesis scripts use the project in the `bmopf/` folder. Its `Manifest.toml` locks every version above.
The top-level `Project.toml` is the older PowerModelsDistribution setup (used only by the early study scripts) and is NOT used for these results.
Random draws use Julia's MersenneTwister; streams can change between Julia versions, so the scatter factors, changed segments and profile map are also written to the CSVs.

First-time setup, from the repository folder in a terminal:

    julia +1.11 --project=bmopf -e "using Pkg; Pkg.instantiate()"

## 2. Network and data

`data/networks/LV3_55bus_withPV/` is the CSIRO LV3 feeder (55 buses, 500 kVA 11/0.433 kV Dyn transformer, tap 1.025, four-wire, 12 single-phase customers), with these changes from the original:

- Master.dss: source moved to a new bus `sourcebus` with pu = 1.00 written out (same as the dataset; scripts scale it, usually to 1.03), joined to the 11 kV bus by a short meter line `for_energymeter` with an EnergyMeter; `redirect PVSystems.dss` added; `batchedit load..* kw=1` commented out; the `solve` and `export` lines removed; `Set MaxControlIter=100` and `Set tolerance=0.00001` added (full list in data/networks/README.md)
- Transformers.dss: LV winding `bus=B641.1.2.3.4` (star point on the neutral, not ground)
- PVSystems.dss: 12 x 5 kVA / 5 kW PV systems, connected `.x.4` (phase-to-neutral), one InvControl `invall` with AS/NZS 4777.2 Australia A curves; tighter InvControl tolerances
- Loads.dss: all 12 loads = original CSIRO values, 1 kW, 0.539743 kvar (0.88 power factor)

`scripts/bmopf/load_lv3.jl` also fixes the inverter settings after import (see the comments at the top of that file).

House usage for the day runs: `data/profiles/TeamNando_OE1_LoadShapes.txt` (Team-Nando OE1-Ideal, commit 96abbab, BSD-3; licence in the same folder; SHA1 8116287f0eb1b67f1aa933f2ec28e0730060c98a with LF line endings, as stored in this repository; a Windows checkout with CRLF endings gives FE3A06F54025E1B4268F523AC1DB1E7870BCF33C).
These 99 profiles are AusNet households from Team-Nando's 342-household x 365-day pool ("Residential load data 30-min resolution.npy", in OEs-The-Basics and MV-LV-Networks; not included here, see data/profiles/pool/README_pool.md), all on day index 350: the lowest-demand day in the dataset (mean 9.71 kWh per house vs 12.06 kWh on the median day). Checked: the 5-min OE1 shapes averaged to 30 min equal the pool values to 1e-15 kW for all 99. The OE1 PV shape is not from the pool's PV file; its daily energy is above about 76 % of the pool's PV days.

## 3. Run order

Start Julia from the repository folder with `julia +1.11 --project=bmopf`. For steps 7-34, first run `using Logging; disable_logging(Logging.Warn)` to hide the repeated import warnings, and use a fresh Julia session for each script.

| # | Command | What it does | Output |
|---|---|---|---|
| 1 | `include("scripts/bmopf/load_lv3.jl")` | imports and checks the feeder | results/analyze_lv3_after_ctrlfix.txt |
| 2 | `include("scripts/bmopf/validate_network_pinned.jl")` | BMOPFTools vs OpenDSS with the same pinned PV outputs | results/pf_validation_lv3_pinned.csv |
| 3 | `include("scripts/bmopf/doe_clean_snapshot.jl")` | correct DOEs at 1.00 and 1.03 pu | results/doe_clean_snapshot.csv |
| 4 | `include("scripts/bmopf/doe_dirty_snapshot.jl")` | Case A and Case B (bound-point reading) | results/doe_dirty_snapshot.csv |
| 5 | `include("scripts/bmopf/doe_severity_sweep.jl")` | resistance x k, k = 1 to 3.07 (bound-point reading) | results/doe_severity_sweep.csv |
| 6 | `include("scripts/bmopf/opendss_check_caseA.jl")` | OpenDSS check of the Case A bound-point voltage | printed only |
| 7 | `include("scripts/bmopf/doe_record_errors.jl")` then `run_record_errors(n_draws = 20)` | scatter and wrong-type errors, 1 kW snapshot | results/doe_record_errors.csv |
| 8 | `include("scripts/bmopf/doe_critical_cables.jl")` then `run_critical_cables()` | one cable at a time is 4 mm² | results/doe_critical_cables.csv |
| 9 | `include("scripts/bmopf/doe_timeseries.jl")` then `run_timeseries()` | full day, 48 half-hours, real profiles, sun-limited | results/doe_timeseries.csv, results/timeseries_profile_map.csv |
| 10 | (same session as 9) `run_record_errors_at(25; n_draws = 20)` | the step-7 draws at the 12:00 loads | results/doe_record_errors_1200.csv |
| 11 | `include("scripts/bmopf/doe_source_sweep.jl")` then `run_source_sweep()` | Case A at 1.00-1.035 pu | results/doe_source_sweep.csv |
| 12 | `include("scripts/bmopf/doe_robust.jl")` then `run_robust()` | hedge in advance vs check records first | results/doe_robust.csv |
| 13 | `include("scripts/bmopf/doe_fairness.jl")` then `run_fairness()` | equal, proportional and max-min sharing rules | results/doe_fairness_summary.csv, results/doe_fairness_customers.csv |
| 14 | `include("scripts/bmopf/doe_ratio.jl")` then `run_ratio()` | cable ratio 3.07 (dataset line codes) vs a higher test ratio of 4.0 | results/doe_ratio.csv |
| 15 | `include("scripts/bmopf/doe_clearsky.jl")` then `run_clearsky()` | clear-sky day (assumed peak 0.85) | results/doe_clearsky.csv |
| 16 | `include("scripts/bmopf/doe_verify_proportional.jl")` then `run_verify_proportional()` | checking records under proportional vs equal sharing | results/doe_verify_proportional.csv |
| 17 | `include("scripts/bmopf/doe_partial_lv3.jl")` then `run_partial_lv3()` | partial export (7 phase patterns) and cable currents | results/doe_partial_lv3.csv, results/cable_currents_lv3.csv |
| 18 | `include("scripts/bmopf/doe_phase_secure.jl")` then `run_phase_secure_lv3()` | phase-secure equal DOE (needs phase_secure_core.jl) | results/doe_phase_secure_lv3.csv |
| 19 | `include("scripts/bmopf/lv9/prepare_lv9.jl")` | builds data/networks/LV9_258bus_withPV from the CSIRO LV9 copy in BMOPFTools b7aa9a1 | network files |
| 20 | `include("scripts/bmopf/lv9/lv9_check.jl")` then `run_lv9_check(1.00)` and `run_lv9_check(1.00; ideal_switches = true)` | BMOPF vs OpenDSS on LV9 | results/lv9/analyze_lv9.txt, lv9_check*.csv |
| 21 | `include("scripts/bmopf/lv9/lv9_core.jl")` then `run_lv9_sweep()`, `run_lv9_upstream(0.94)`, `run_lv9_single(0.94)`, `run_lv9_fairness(0.94)` | LV9 record errors by segment kind, one at a time, sharing rules | results/lv9/lv9_sweep.csv, lv9_segments.csv, lv9_single_*.csv, lv9_fairness.csv |
| 22 | `include("scripts/bmopf/lv9/lv9_partial.jl")` then `run_lv9_partial()` | LV9 partial export and cable currents | results/lv9/lv9_partial.csv, lv9_cable_currents.csv |
| 23 | `include("scripts/bmopf/lv9/lv9_thermal.jl")` then `run_lv9_thermal()` | LV9 with cable current limits | results/lv9/lv9_thermal.csv |
| 24 | `include("scripts/bmopf/lv9/lv9_phase_secure.jl")` then `run_phase_secure_lv9()` | LV9 phase-secure DOE (~6 min) | results/lv9/lv9_phase_secure.csv |
| 25 | `include("scripts/bmopf/doe_dropout_lv3.jl")` then `run_dropout_lv3()` | bound-point and phase-secure DOEs vs every 1 or 2 dropped customers (79 cases x 2 DOEs x 2 settings, ~2 min) | results/doe_dropout_lv3.csv |
| 26 | (same session) `run_dropout_secure_lv3()` | dropout-secure DOE: 7 phase patterns + all 1- and 2-customer dropouts (85 cases), bisection (~5 min) | results/doe_dropout_secure_lv3.csv |
| 27 | (same session) `run_dropout_lv3_full()` | dropout-secure DOE at 12:00 vs all 4094 on/off combinations (~15 min, resumable) | results/doe_dropout_lv3_full_day_1200_dropout_secure.csv |
| 28 | `include("scripts/bmopf/doe_dropout_records_lv3.jl")` then `run_dropout_records_lv3()` | headline redone: records-based dropout-secure DOE on the true network (needs 26, ~6 min) | results/doe_dropout_records_lv3.csv |
| 29 | `include("scripts/bmopf/lv9/lv9_dropout.jl")` then `run_lv9_dropout_check()` and `run_lv9_dropout_secure()` | LV9: phase-secure DOE vs 130 cases (nobody, 6 phase patterns, 123 single dropouts); verify-vs-realised diagnostic; dropout-secure DOE (needs 24, ~15 min) | results/lv9/lv9_dropout_check.csv, lv9_dropout_diagnostic.csv, lv9_dropout_secure.csv |
| 30 | `include("scripts/bmopf/lv9/lv9_dropout_records.jl")` then `run_lv9_dropout_records()` | LV9 headline redone with the dropout-secure DOE (shared cables / l_2373 wrong; needs 29, ~25 min) | results/lv9/lv9_dropout_records.csv |
| 31 | `include("scripts/bmopf/lv9/lv9_midpoint.jl")` then `run_lv9_midpoint()` | LV9 dropout-secure DOE and headline at 0.97 pu (needs 29) | results/lv9/lv9_midpoint_0.97.csv |
| 32 | `include("scripts/bmopf/doe_partial_util_lv3.jl")` then `run_partial_util_lv3()` | dropout-secure DOE vs 300 random part-export mixes, snapshot and 12:00 (~2 min) | results/doe_partial_util_lv3.csv |
| 33 | `include("scripts/bmopf/lv9/lv9_verify_diag.jl")` then `run_lv9_verify_diag()` | LV9 verify vs realised, customer by customer (known issue 20) | results/lv9/lv9_verify_diag.csv |
| 34 | `include("scripts/bmopf/validate_pf_vs_opendss.jl")` | unpinned BMOPF power flow vs OpenDSS; not a like-for-like test, see known issue 25 | results/pf_validation_lv3.csv |
| 35 | `include("scripts/bmopf/dataset/pool_profiles.jl")` then `check_pool()` | checks Team-Nando's house-usage pool and that the 99 OE1 profiles equal its day index 350 (needs the pool .npy files, not included, see data/profiles/pool/README_pool.md; a few seconds) | results/dataset/pool_check.txt |

The ~46 "from_dss: ... could not be represented" warnings at import are expected (OpenDSS fields like `units` that BMOPF does not need).

## 4. Expected key numbers (to check a rerun)

| Result | Value |
|---|---|
| BMOPFTools vs OpenDSS, phase-to-neutral voltage | within 0.11 V at all 55 buses; neutral within 0.024 V |
| Losses (pinned validation) | OpenDSS 386.9 W; BMOPF p_loss 359.0 W + earthing 0.5 W + switches 28.2 W = 387.6 W |
| Clean DOE, 1 kW snapshot | 4.906 kW at 1.00 pu, 4.529 kW at 1.03 pu (both inverter-limited) |
| Case A, 1 kW snapshot, 1.03 pu | correct 2.734 kW, issued 4.529 kW, gap 1.795 kW (+65.6 %); realised 254.60 V with Volt-Watt (bound-point 255.12 V) |
| Critical cables | 12 of 22 segments matter; l_3432 alone = same DOE as all 22 wrong, realised 254.60 V, 1 customer above 253 V |
| Record errors, 1 kW snapshot | scatter 5-10 %: ≤+0.3 %; 2 wrong cables: 0 to +49.65 %; 5 or 11 wrong: up to +65.7 %, ≤254.60 V |
| Record errors, 12:00 loads | scatter 10 %: -5.7 to +9.3 %, ≤253.20 V; 5 or 11 wrong: up to +117 %, ≤255.15 V |
| Full day, 1.03 pu | clean DOE 4.02-4.48 kW, voltage-limited at all 48 steps; gap 2.0-2.35 kW; sun-limited over-voltage 10:00-16:30, peak 255.02 V at 11:30 |
| Source sweep, 12:00 | gap 0.14 / 0.17 / 0.71 / 1.63 / 2.29 / 0.60 kW at 1.00 / 1.01 / 1.02 / 1.025 / 1.03 / 1.035 pu |
| Robust, 12:00 | hedge b = 5 / 10 / 20 %: 4.124 / 4.004 / 3.785 kW (scenario check identical); check records: 1.959 kW (none) -> 2.428 (1) -> 4.253 (11) |
| Cable ratio 4.0, 12:00 | correct 1.624 kW, gap 2.628 kW (+161.8 %), sun-limited 255.12 V (3.07: 1.959 kW, 254.29 V) |
| Clear-sky day | 21 half-hours above 253 V (07:30-17:30), peak 255.22 V |
| Checking under proportional, 12:00 | total share 64 % (none) -> 75 / 84 / 94 / 100 % after 3 / 6 / 9 / 11 checks (equal, OPF-ranked: 46 -> 57 / 60 / 60 -> 100 %; equal, shortest first: 46 % until all 12 are checked) |
| LV3 partial export / phase-secure | worst 253.30 V; phase-secure DOE -4.8 % (snapshot), -9.7 % (12:00) |
| LV9 clean DOE | 3.587 kW (0.94 pu), 1.654 kW (1.00 pu), voltage-limited; OpenDSS 0.0007 V with ideal switches |
| LV9 shared vs drops (0.94 pu) | 12 shared wrong: gap 1.458 kW, 258.99 V; l_2373 alone 1.333 kW; drops wrong: 0.238 kW; 6 of 123 single drops matter |
| LV9 thermal (110 A) / phase-secure | 2.293 kW (0.94 pu) / 2.445 kW (0.94 pu) |
| LV3 dropout check (79 cases) | bound-point: 13 (snapshot, worst 253.16 V) and 28 (12:00, 253.30 V) cases over 253 V; phase-secure: 8 (253.04 V) and 2 (253.08 V) |
| LV3 dropout-secure DOE | 4.203 kW snapshot (-7.2 % vs bound point, -2.5 % vs phase-secure); 3.664 kW 12:00 (-13.8 %, -4.6 %); 85 cases and all 4094 combinations at 12:00: 0 over 253 V, worst 253.00 V (phase a silent) |
| LV3 headline, dropout-secure | snapshot: issued 4.203, correct 2.715 kW, gap 1.488 kW (+54.8 %), 254.62 V; 12:00: 3.664 vs 1.947 kW, gap 1.718 kW (+88.2 %), 255.05 V; all 22 wrong: 85 of 85 cases over 253 V; l_3432 only: 70 of 85, same correct DOE |
| LV9 dropout check / dropout-secure | phase-secure DOE: all 123 single dropouts pass; "only b and c export" 253.20 V (0.94 pu) / 253.13 V (1.00 pu) although verify said feasible; dropout-secure 2.423 kW (0.94 pu, -0.9 %) / 1.097 kW (1.00 pu, -1.3 %), about -33 % vs bound point |
| LV9 headline, dropout-secure | 0.94 pu: 12 shared wrong correct 1.552 kW, gap 0.871 kW (+56.1 %), 258.93 V, 127 of 130 cases; l_2373 only 1.602 kW, gap 0.821 (+51.3 %), 258.42 V; 1.00 pu: 12 shared gap 0.123 kW (+12.7 %), 254.13 V, 2 of 130; l_2373 only: no gap |
| Part-export check, LV3 dropout-secure | 300 random mixes each: 0 over 253 V; worst 252.92 V (snapshot), 252.82 V (12:00) |
| Sharing rules, l_3432 wrong | equal: 12 of 12 limits change, 21.55 kW (snapshot); proportional: 1 of 12, 1.85 kW; realised 254.60 V at b828 b-n under every rule |

## 5. Main modelling choices

- Voltage limit: 207 to 253 V phase-to-neutral, checked at each customer's own connection point (not on every phase of every bus; with all phases the 1.03 pu DOE is 3.329 kW, binding at B1754 phase a where there is no customer, and the 4 mm² network is infeasible).
- DOE = limit on the inverter's AC output (gross PV), not net export at the meter.
- DOE allocation: equal export limit for every customer (PowerOptLab fairness = :equal, security = :bound_point).
- Inverters: 5 kVA, Volt-VAr and Volt-Watt on phase-to-neutral voltage, reactive priority.
- Source voltage: 1.03 pu for the main results (also used in Geth's PowerOptLab LV3 study, there with 1 % source unbalance); 1.00-1.035 pu in the source sweep.
- Cable error: 22 service-cable segments; 16 mm² vs 4 mm² copper from the dataset's own line codes (resistance ratio 3.07).
- Security of the DOE: bound-point (everyone exports at once), phase-secure (also safe when one or two whole phases export nothing, checked with verify_operating_envelope) and dropout-secure (realised reading <= 253.005 V for nobody dropped, the 7 phase patterns, and every 1- or 2-customer dropout on LV3 / every single dropout on LV9). The dropout-secure DOE is the safest of the three and is used for the headline results. The idea comes from Liu and Braslavsky (IEEE Access, 2022) and PowerOptLab's `doe_dropout_utilizations` (F. Geth); see ACKNOWLEDGEMENTS.md.
- Two readings of what an issued DOE does on the true street: bound-point (everyone exports exactly the DOE, Volt-Watt off; worst case) and realised (everyone may export up to the cap, all inverter laws on; physical). Day runs also cap export by the sun available.

## 6. Known issues and limitations

1. Source voltage drives the size of the error (section 4, source sweep). Team-Nando's MV profile is about 0.99-1.00 pu; the LV operating point depends on the transformer tap. Always quote the error together with the source voltage.
2. Resistance ratio: the 3.07 ratio comes from the dataset's own line codes (self resistance 4.57 Ω/km for 4 mm² vs 1.49 Ω/km for 16 mm²). It is not taken from a standard. doe_ratio.jl also tests a higher ratio of 4.0 (labelled `IEC` in the script and CSV): it adds about 0.35 kW to the gap and 0.5-0.8 V to the realised peak, so a bigger real ratio would make the results worse, not better.
3. Equal allocation is the main rule; one critical customer sets everyone's DOE. Proportional and max-min are tested in doe_fairness.jl: they change who absorbs the error, not the physical over-voltage.
4. One feeder, one day, one set of 12 profiles, 5 kVA inverters.
5. Network losses: BMOPF p_loss (lines + transformer) is about 7 % below OpenDSS because the 8 closed switches are 1 mΩ elements in OpenDSS (switch=y) but ideal ties in BMOPFTools (28.2 W), and BMOPF's p_loss leaves out the earthing shunts (0.5 W). With both added, losses agree within 0.8 W (387.6 vs 386.9 W, 0.2 %) (loss breakdown printed by validate_network_pinned.jl). The switch impedance also explains most of the 0.10 V voltage difference. Negligible for DOEs.
6. Smoothing: BMOPF smooths the Volt-Watt corner at 253 V (softplus, about 0.5 V wide), which caps an inverter at about 4.8 kW at exactly 253 V. This overstates realised curtailment by about 5 % when many customers sit just above 253 V (all 22 wrong: 1.86 vs 1.78 kW with the exact curve); voltages are unaffected. Small trims in the inverter-limited snapshot come from the 5 kVA circle with reactive priority. curtail_kW mixes both causes.
7. The severity sweep (file 3) scales only diagonal R; k = 3.07 gives 2.739 kW vs the full line-code swap 2.734 kW (0.2 %).
8. Customer counts above 253 V include marginal cases (253.01 V); read them with the voltage.
9. Case B is the mirror of Case A (lost % = 1/(1 + over-promise) - 1), not separate evidence.
10. Transformer xhl = 0.0391918 comes from the original dataset (= sqrt(0.04^2 - 0.008^2)); left unchanged.
11. The older results files doe_dirty_snapshot.csv and doe_severity_sweep.csv report bound-point voltages only; the realised values for the same cases are in doe_critical_cables.csv, doe_record_errors.csv and doe_source_sweep.csv.
12. The DOE is very slightly non-monotone in a single cable's resistance: a thicker cable lowers that customer's voltage, so its inverter absorbs less reactive power, which nudges its neighbours. Effect up to 0.02 kW (0.7 %); reproduced in OpenDSS; disappears with Volt-VAr off. So 'thinnest cable everywhere' is the worst case only to within about 0.02 kW.
13. The size of the error is not monotone in source voltage: largest around 1.025-1.03 pu, smaller in kW at 1.035 pu where the clean DOE collapses.
14. The measured day is partly cloudy (sun peak 3.6 kW per house); the clear-sky run uses an assumed peak of 0.85 x 5 kW and a symmetric half-sine shape.

15. LV9 source data is the CSIRO LV9 copy shipped with BMOPFTools b7aa9a1 (loads reset to the CSIRO default). That copy has two closed switches commented out (Switch_3773_CLOSED, Switch_4284_CLOSED), so LV9 is run radial; to be checked against the DOI download.
16. LV9 voltage comparison depends on the switch convention: with the dataset's 1 mOhm switches (OpenDSS) the LV9 equal DOE is about 0.10 kW higher than with ideal switches (BMOPF); voltages differ by up to 0.75 V.
17. "LV9 1.00 pu ~ LV3 1.025 pu" means the same transformer no-load voltage only; LV9 is voltage-limited even at 0.92-0.94 pu.
18. Current ratings are only applied to copper cables (16 mm2 110 A buried / 81 A duct, 120 mm2 345 A, Prysmian datasheet). Aluminium mains and the 4 mm2 cable have no rating yet, so the LV9 shared-cable thermal case is incomplete (negative gaps there are an artefact). AS/NZS 3008.1.1 to be consulted.
19. All DOEs before step 25 except doe_phase_secure / lv9_phase_secure are bound-point DOEs (everyone exports at once); they are not automatically safe when one or two phases do not export (LV3 +0.3 V, LV9 +5.4 V). Steps 25-30 give the dropout-secure versions.
20. The phase-secure check (verify_operating_envelope with the 7 phase patterns) and the realised reading disagree slightly: patterns the check accepts give up to 0.01 V (LV3) and 0.20 V (LV9, "only b and c export") above 253 V in the realised reading. The LV9 diagnostic (lv9_verify_diag.jl, results/lv9/lv9_verify_diag.csv) shows the check's own solution curtails one inverter (ld2984) to 2347 W where the realised reading gives 2445 W (253.00 vs 253.21 V). Suspected cause, not yet confirmed: solver tolerance at the 1 MW power base (about 1e-4 pu, i.e. about 100 W); a rerun with a tighter tolerance is planned. (An earlier guess, smoothing of the inverter laws, did not explain it.) The dropout-secure DOE uses the realised reading, so it is not affected. To ask F. Geth.
21. Near the limit the DOE is very sensitive to the voltage tolerance: on LV3 at 12:00, removing violations of under 0.1 V costs 4.6 % of export (3.841 -> 3.664 kW). The tolerance used is 253.005 V.
22. On LV3, checking the 85 cases found the same worst case as checking all 4094 on/off combinations, so dropping 3 or more customers never made things worse there. On LV9, pairs (7503 cases) were not checked; single dropouts never bind, the binding case is always one whole phase silent.
23. The harm from a wrong record is not monotone in source voltage (also item 13): on LV9 the dropout-secure gap is 0.82-0.87 kW at 0.94 pu but 0-0.12 kW at 1.00 pu, where every customer is already limited to about 1.1 kW and the shared cable carries little current.
24. Current ratings found since item 18 (not yet used in any run): 4 mm2 Cu 33 A buried / 33 A duct and 16 mm2 110 / 81 A (MEC XV datasheet, AS/NZS 3008.1.1 basis); AusNet library in Team-Nando MV-LV-Networks: 16 mm2 Cu 107 / 91 A, 240 mm2 Al 280 / 325 A (meaning of the two columns undocumented, probably summer / winter).
25. Unpinned comparison (validate_pf_vs_opendss.jl, step 34) is not a like-for-like test. The BMOPFTools power flow (solve_pf) treats Volt-Watt as a cap, so it does not fix each inverter's P, and it returns Q = 0 (Stage 3 of the development notes). Rerun on the current model (1.00 pu): for example ld1970 gets 1.124 kW, 0 kvar in BMOPF but 4.924 kW, -0.869 kvar in OpenDSS, so the voltages differ by up to 2.07 V (b828 b-n), neutral up to 0.91 V. This shows the inverter outputs differ, not the network model. The network model is validated with the same P and Q in both programs (step 2: largest difference 0.103 V); the inverter curves are checked separately (OpenDSS InvControl gives the AS/NZS 4777.2 values exactly); and the OPF-based realised reading, which does apply the inverter laws, matched an exact OpenDSS solve within 0.03 V (DATA_CARD.md, "How much to trust it"; the files of that separate OpenDSS rebuild are not included in this repository).
26. The 4094 on/off check (step 27) covers every combination of the 12 customers exporting or not, at one operating point (12:00 loads, 1.03 pu, the dropout-secure DOE). It is not a check over all days or voltages.
27. curtail_kW is about 0.001 kW low for each customer given a limit of 0, because the solver needs a cap above zero and those customers get 1 W (doe_fairness.jl / lv9_common.jl realised()). Seen in doe_partial_lv3.csv and lv9_partial.csv (e.g. -0.082 kW with 82 silent customers). Voltages and DOEs are not affected.
28. Bisection limits: the correct DOE in the records runs is searched between 0 and the issued DOE, so a gap can never come out negative ("no gap" means gap <= 0). The search step is about issued/1024 (LV9) or 1/4096 of the range (LV3), always rounding to the safe side, so gaps carry about 0.002 kW of grid precision.
29. LV9 thermal case (lv9_thermal.jl): in the 81 A "in duct" run the 120 mm2 cable keeps its 345 A buried rating, so buried and duct assumptions are mixed there.
30. scripts/bmopf/doe_dirty_origloads.jl and its CSV are from an earlier version: the script calls a helper that has since been renamed, so it no longer runs, and the loads it compares are now the default. It is kept for history only and is not part of the run order.
31. The scripts in scripts/ (01-05, count_linecodes.jl, sensitivity_service_cable.jl) and scripts/study/ are early exploration on the older top-level PowerModelsDistribution project (Julia 1.9). Their outputs (e.g. results/sensitivity_service_cable.csv) come from earlier model states and are not thesis results.
32. Voltage lower limit: the model uses 207 V (DATA_CARD.md cites AS 61000.3.100); AS 60038's 230 V -6 % would be 216.2 V. The source for 207 V is still to be confirmed. All results in this thesis are about the 253 V upper limit.
33. Line current limits in the OPF: checked. After import, every line code carries a current limit of 600 A (the OpenDSS default, because the dataset's line codes give no real rating), and the lines take it from their line code. This is not a real cable rating (a 16 mm² service cable is rated about 110 A). It never limits any result here: the highest current at a DOE is about 73 A on LV3 (results/cable_currents_lv3.csv) and 497 A on LV9 (results/lv9/lv9_cable_currents.csv, 0.94 pu), both below 600 A. So all DOEs in this repo are set by voltage or the inverter size, not by current. Real cable ratings are tested separately in lv9_thermal.jl. Check used (after include("scripts/bmopf/load_lv3.jl")): list net["linecode"][k]["i_max"].
34. Minor logging points: a NaN cap (no sun) is logged as "no export"; a failed solve is counted as "over 253 V" (so it is never hidden as a pass); and "0 over" means every checked voltage is at or below 253.005 V (the tolerance in item 21).

## 7. Where the history is

`scripts/notes/worklog.md` has a step-by-step log of every check, error and fix (stages, in order). The git log has the exact version of every file.

