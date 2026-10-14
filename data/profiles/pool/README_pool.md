# House-usage pool for the dataset (data/profiles/pool/)

Source: Team-Nando "OEs-The-Basics", folder TestLVCircuit, commit 3667913d62d229f147f02be2cd578995ba6473a3
(https://github.com/Team-Nando/OEs-The-Basics). Licence: BSD 3-Clause, "Copyright (c) 2022, Team Nando -
Public Repositories" (full text in TeamNando_LICENSE.txt in this folder). Data originally from AusNet Services
(anonymised smart meters, Victoria) as credited by Team-Nando.

| File | Shape | SHA1 |
|---|---|---|
| Residential load data 30-min resolution.npy | 342 households x 365 days x 48 half-hours, float64 | 145d73c070f7e95c14524db684918b47daaf1e6e |
| Residential PV data 30-min resolution.npy | 365 days x 48 half-hours, float64 | 59cf9e081d22f54a272ede4a7a8dfaa1c7dd48ce |

What the numbers are (checked 14 Oct 2026):
- Load: average kW in each half-hour, active power only (no kvar), no negative values (no PV behind the meter).
- 203 whole days are all zero (21 households): treat as missing, never sample them.
- Day index 0 = 1 January; the year is not stated. 2014 is inferred (weekday pattern, 14-17 Jan 2014 Melbourne heatwave).
- PV: one per-unit shape per day (year maximum = 1.0) from one AusNet PV meter; the same shape is used for every customer.
- The 99 OE1-Ideal profiles used so far are households 0-341 (by their Load_shape_k number) on day index 350
  (17 Dec 2014), the lowest-demand day of the year.
