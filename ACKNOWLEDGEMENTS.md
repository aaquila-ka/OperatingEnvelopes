# Acknowledgements

This work stands on other people's data, software and guidance. Thank you to all of them.

## People

- **Archie Chapman** and **Frederik Geth** (The University of Queensland), my supervisors, for their guidance throughout this thesis.
- **Frederik Geth** also for BMOPFTools.jl and PowerOptLab.jl, the four-wire network and DOE tools every thesis result is computed with, and for the CSIRO street models he co-authored.
- **The School of Electrical Engineering and Computer Science, The University of Queensland**, for the thesis course and its resources.

## Data

**CSIRO low-voltage street models (LV3 and LV9)**
F. Geth, R. Heidari, J. Clark, K. Lucas and N. Nimalsiri, "Realistic Australian medium voltage feeder with associated low voltage feeders," v1, CSIRO Data Collection, 2025, doi: [10.25919/ghnz-bk28](https://doi.org/10.25919/ghnz-bk28).
Licence: CC BY-NC-SA 4.0. The copies in `data/networks/` are modified; every change is listed in [data/networks/README.md](data/networks/README.md). The LV9 copy is the one distributed with BMOPFTools.jl (commit b7aa9a1).

**House-usage and solar profiles**
Team-Nando (University of Melbourne), repositories [OE1-Ideal](https://github.com/Team-Nando/OE1-Ideal) (commit 96abbab), [OEs-The-Basics](https://github.com/Team-Nando/OEs-The-Basics) (commit 3667913) and [MV-LV-Networks](https://github.com/Team-Nando/MV-LV-Networks).
Licence: BSD 3-Clause; the licence notices are kept unchanged in `data/profiles/`. The underlying anonymised smart-meter data are from **AusNet Services**, as credited by Team-Nando.

**Cable current ratings** (used only in the LV9 thermal check)
Prysmian and MEC cable datasheets (AS/NZS 3008.1.1 basis), and the AusNet cable library in Team-Nando's MV-LV-Networks repository. Exact values and where each is used: REPRODUCE.md known issues 18 and 24.

## Software

| Tool | Used for | Reference | Licence |
|---|---|---|---|
| BMOPFTools.jl (commit b7aa9a1) | four-wire network model, power flow, optimal power flow | F. Geth, github.com/frederikgeth | see its repository |
| PowerOptLab.jl (commit 953e45c) | DOE calculation and checking (verify_operating_envelope) | F. Geth, github.com/frederikgeth | see its repository |
| OpenDSS (EPRI) | independent cross-check of voltages | R. C. Dugan and T. E. McDermott, "An open source platform for collaborating on smart grid research," IEEE PES General Meeting, 2011 | BSD-3 |
| OpenDSSDirect.jl (DSS-Extensions) | running OpenDSS from Julia | github.com/dss-extensions/OpenDSSDirect.jl | BSD-3 |
| PowerIO.jl | reading the OpenDSS files into BMOPFTools (used inside BMOPFTools) | see its repository | see its repository |
| JuMP.jl and Ipopt | building and solving the optimisation | M. Lubin et al., "JuMP 1.0," Math. Prog. Comp., 2023; A. Wächter and L. T. Biegler, Math. Prog., 2006 | MPL-2.0 / EPL-2.0 |
| PowerModelsDistribution.jl | early study scripts only (scripts/study/) | D. M. Fobes et al., Electric Power Systems Research, 2020 | BSD-3 |
| DataFrames.jl, CSV.jl | tables in the early study scripts | JuliaData, github.com/JuliaData | MIT |
| Julia and its standard library (Printf, Statistics, Random, SHA, Dates) | running all scripts | J. Bezanson, A. Edelman, S. Karpinski and V. B. Shah, "Julia: A fresh approach to numerical computing," SIAM Review, 2017 | MIT |
| Python, pandas, matplotlib | drawing the figures in figures/ | python.org, pandas.pydata.org, matplotlib.org (J. D. Hunter, "Matplotlib: A 2D graphics environment," Computing in Science & Engineering, 2007) | PSF / BSD-3 / matplotlib licence |
| xkcd-script font (optional) | hand-drawn look of the plots | github.com/ipython/xkcd-font | CC BY-NC 3.0 |

## Work this thesis builds on

- K. Petrou *et al.*, "Ensuring distribution network integrity using dynamic operating limits for prosumers," *IEEE Trans. Smart Grid*, vol. 12, no. 5, pp. 3877-3888, 2021.
- M. Z. Liu, L. F. Ochoa, P. K. C. Wong and J. Theunissen, "Using OPF-based operating envelopes to facilitate residential DER services," *IEEE Trans. Smart Grid*, vol. 13, no. 6, pp. 4494-4504, 2022.
- B. Liu and J. H. Braslavsky, "Sensitivity and robustness issues of operating envelopes in unbalanced distribution networks," *IEEE Access*, vol. 10, pp. 92789-92798, 2022, doi: 10.1109/ACCESS.2022.3203062.
- B. Liu, J. H. Braslavsky and N. Mahdavi, "Linear OPF-based robust dynamic operating envelopes with uncertainties in unbalanced distribution networks," *J. Mod. Power Syst. Clean Energy*, doi: 10.35833/MPCE.2023.000653.
- A. Kumarawadu, M. I. Azim, M. Khorasany, R. Razzaghi and R. Heidari, "Smart meter data-driven dynamic operating envelopes for DERs," *Applied Energy*, vol. 384, art. 125469, 2025.
- M. Z. Liu, A. Simonovska, L. F. Ochoa, P. K. C. Wong, K. Chew and J. Theunissen, "Validating real LV feeder models using smart meter data: a practical experience from Project EDGE," CIRED 2023, paper 10741. (Evidence that the impedances in an original feeder model can differ from validated ones: +170 % resistance and +400 % reactance on one feeder.)
- M. Mokhtar, V. Robu, D. Flynn, C. Higgins, J. Whyte, C. Loughran and F. Fulton, "Automating the verification of the low voltage network cables and topologies," *IEEE Trans. Smart Grid*, vol. 11, no. 2, pp. 1657-1666, 2020, doi: 10.1109/TSG.2019.2941722. (LV network data, including cable cross-section, are often incomplete.)
- A. Antić and T. Capuder, "A geographic information system-based modelling, analysing and visualising of low voltage networks," arXiv:2310.00382, 2023. (Unknown LV cable attributes are replaced with the most common cable type in the database.)

## Standards

- AS 60038:2012, *Standard voltages* (230 V +10 % / -6 %, hence the 253 V upper limit).
- AS 61000.3.100:2011, *Limits - Steady state voltage limits in public electricity systems*.
- AS/NZS 4777.2:2020, *Grid connection of energy systems via inverters, Part 2: Inverter requirements* (Volt-VAr and Volt-Watt settings).
- IEC 60228:2004, *Conductors of insulated cables* (cable resistance comparison).

## Use of AI tools

Claude (Anthropic) was used to help set up, document and check code and to draft figures. All simulations were run, and all results checked, by the author.

If I have missed anyone whose work this repository uses, or credited something incorrectly, please open an issue and I will fix it.
