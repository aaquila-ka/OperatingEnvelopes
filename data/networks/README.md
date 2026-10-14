# Street models (CSIRO LV3 and LV9)

**Source:** F. Geth, R. Heidari, J. Clark, K. Lucas and N. Nimalsiri, "Realistic Australian medium voltage feeder with associated low voltage feeders," v1, CSIRO Data Collection, 2025, doi: [10.25919/ghnz-bk28](https://doi.org/10.25919/ghnz-bk28).
**Licence:** CC BY-NC-SA 4.0 (attribution, non-commercial, share alike). These modified copies are shared under the same licence.

Both folders are OpenDSS models (`Master.dss` is the entry point). The changes made for this thesis are listed below so anyone can tell what came from CSIRO and what was changed.

## LV3_55bus_withPV (12 homes)

Taken from the CSIRO dataset. Changes:

- `Master.dss`: source kept at the dataset's 1.00 pu (the scripts set the value they need, usually 1.03); the line `batchedit load..* kw=1` commented out so the loads come from `Loads.dss`; `Set MaxControlIter=100`.
- `Transformers.dss`: LV winding written as `bus=B641.1.2.3.4`, so the transformer star point is on the neutral conductor (without the node list, OpenDSS ties it to ground).
- `PVSystems.dss` (added): 12 rooftop systems of 5 kVA / 5 kW, connected phase-to-neutral (`.x.4`), one inverter control `invall` with the AS/NZS 4777.2 Australia A Volt-VAr and Volt-Watt curves and tighter control tolerances.
- `Loads.dss`: all 12 loads at the original CSIRO setting, 1 kW and 0.539743 kvar (power factor 0.88).
- `scripts/bmopf/load_lv3.jl` also sets the inverter curves after import into BMOPFTools (see the header of that file).

The other files in the folder (`runOpenDSS.jl`, the `*_EXP_*.csv` exports and the PDFs) come with the dataset; the exports and PDFs were produced by an early run on an older version of the model and are not thesis results.

## LV9_258bus_withPV (123 homes)

Built by `scripts/bmopf/lv9/prepare_lv9.jl` from the CSIRO LV9 copy distributed with BMOPFTools.jl (commit b7aa9a1, `test/data/LV/LV9_258bus`). The same changes as LV3 are applied: loads reset to the CSIRO default 1 kW / 0.539743 kvar, one 5 kVA / 5 kW PV per home connected phase-to-neutral with the same inverter curves, the transformer star point on the neutral, and the source at 1.00 pu.

Note: in that copy two closed switches are commented out (`Switch_3773_CLOSED`, `Switch_4284_CLOSED`), so LV9 is run as a radial network. This still has to be checked against the DOI download (REPRODUCE.md known issue 15).
