# Street models (CSIRO LV3 and LV9, modified)

**Source:** F. Geth, R. Heidari, J. Clark, K. Lucas and N. Nimalsiri, "Realistic Australian medium voltage feeder with associated low voltage feeders," v1, CSIRO Data Collection, 2025, doi: [10.25919/ghnz-bk28](https://doi.org/10.25919/ghnz-bk28).
**Licence:** [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (attribution, non-commercial, share alike). The files here are **modified** copies and are shared under the same licence; see [LICENSE.md](LICENSE.md).

Both folders are OpenDSS models (`Master.dss` is the entry point). Every change I made to the CSIRO files is listed below, so anyone can tell what came from CSIRO and what was changed. I found the changes by comparing my files line by line with the unmodified copy of the dataset distributed with BMOPFTools.jl (first release, `test/data/LV/`, which states that it is an unmodified copy of the DOI dataset). Files not listed under a folder are unchanged.

## LV3_55bus_withPV (12 homes) (modified)

- `Master.dss`
  - source line: `bus1=B804` changed to `bus1=sourcebus`, and `pu=1.00` written out (1.00 is also the OpenDSS default, so the source value itself is unchanged; the scripts set the value they need, usually 1.03);
  - added `redirect PVSystems.dss`;
  - `batchedit load..* kw=1` commented out (`// batchedit load..* kw=1`), so the loads come from `Loads.dss`;
  - removed the lines `solve`, `export Voltages` and `export Powers`;
  - added a short meter line from the new source bus to the 11 kV bus, `new line.for_energymeter lineCode=ughv_400al_triplex_ug_4w_bundled bus1=sourcebus.1.2.3.0 bus2=B804.1.2.3.4 length=0.0001 units=km phases=4`, and an energy meter on it, `New EnergyMeter.Source Element=line.for_energymeter Terminal=1`;
  - added `Set MaxControlIter=100` and `Set tolerance=0.00001`.
- `Transformers.dss`: LV winding written as `bus=B641.1.2.3.4` instead of `bus=B641`, so the transformer star point is on the neutral conductor (without the node list, OpenDSS ties it to ground).
- `Loads.dss`: `kw=1 kvar=0.539743` added to each of the 12 loads. This is the same as the original CSIRO setting (the `batchedit load..* kw=1` in the original `Master.dss` plus the OpenDSS default power factor of 0.88), written into the file instead of set by batchedit.
- `PVSystems.dss` (new file, not in the dataset): 12 rooftop systems of 5 kVA / 5 kW, connected phase-to-neutral (`.x.4`), one inverter control `invall` with the AS/NZS 4777.2 Australia A Volt-VAr and Volt-Watt curves, and tighter control tolerances (`VarChangeTolerance=1e-6 VoltageChangeTolerance=1e-7 ActivePChangeTolerance=1e-6`). The line for `Ld24_LOAD_A` also carries `pf=-0.95`; `scripts/bmopf/load_lv3.jl` links all 12 to `invall` after import (see the header of that file).
- Unchanged from the dataset: `Groundings.dss`, `Linecodes.dss`, `lines.dss`, `Switches.dss`.

Other files in this folder are not part of the CSIRO dataset:

- `runOpenDSS.jl` is adapted from `data/LV9_258bus/run_LV9.jl` in Frederik Geth's [GPSTTopic82024](https://github.com/frederikgeth/GPSTTopic82024) repository (BSD 3-Clause, Copyright 2025 Frederik Geth). The licence notice and the list of my changes are at the top of the file.
- `lv3_55bus_EXP_VOLTAGES.csv`, `lv3_55bus_EXP_POWERS.csv`, `busdistances.csv` and the three `volt_distance_*.pdf` plots were made by running that script on an earlier version of this model. They are not thesis results. Because they come from the CSIRO model, they are shared under CC BY-NC-SA 4.0 as well.

## LV9_258bus_withPV (123 homes) (modified)

Built by `scripts/bmopf/lv9/prepare_lv9.jl` from the CSIRO LV9 copy distributed with BMOPFTools.jl (commit b7aa9a1, `test/data/LV/LV9_258bus`). In that copy the loads had already been edited (2 kW at 0.95 power factor, batchedit removed); the script writes the loads again at the CSIRO default, so compared with the unmodified dataset the changes are:

- `Master.dss`
  - source line: `bus1=B1690` changed to `bus1=sourcebus`, and `pu=1.00` written out (same value as the default);
  - added `redirect PVSystems.dss`;
  - removed the lines `batchedit load..* kw=1`, `solve` and `export Voltages`;
  - added the same meter line and energy meter as LV3, here to the 11 kV bus B1690 (`bus2=B1690.1.2.3.4`);
  - added `Set MaxControlIter=100` and `Set tolerance=0.00001`.
- `Transformers.dss`: LV winding written as `bus=B342.1.2.3.4` instead of `bus=B342` (star point on the neutral).
- `Loads.dss`: a comment line added at the top, and `kw=1 kvar=0.539743` added to each of the 123 loads (the CSIRO default, as for LV3).
- `PVSystems.dss` (new file): one 5 kVA / 5 kW PV per home, connected phase-to-neutral, with the same inverter curves and tolerances as LV3.
- Unchanged from the dataset: `Groundings.dss`, `Linecodes.dss`, `lines.dss`, `Switches.dss`.

Note: in the dataset copy two closed switches are commented out (`Switch_3773_CLOSED`, `Switch_4284_CLOSED`), so LV9 is run as a radial network. I have not changed this. It still has to be checked against the DOI download (REPRODUCE.md known issue 15).
