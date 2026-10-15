# Figures

Each `fig_*.py` draws one plot straight from the CSV files in `../results/`; no number is typed by hand. Run from this folder, for example `python fig_wrong_record.py` (needs Python 3 with pandas, NumPy and matplotlib).

| Script | Plot | Reads |
|---|---|---|
| fig_wrong_record.py | limit from wrong records vs correct limit, and the voltage each gives (12-home street, 12:00) | doe_dropout_records_lv3.csv |
| fig_day.py | the whole day: sun, both limits, highest voltage | doe_timeseries.csv |
| fig_key.py | how much too generous the limit is across supply voltages, both streets | doe_source_sweep.csv, lv9/lv9_sweep.csv |
| fig_safer.py | basic vs dropout-secure (safer) limit | doe_dirty_snapshot.csv, doe_robust.csv, lv9/lv9_sweep.csv, doe_dropout_records_lv3.csv, lv9/lv9_dropout_records.csv |
| fig_disturb.py | the three kinds of record error and their effect | doe_record_errors.csv, doe_critical_cables.csv, doe_dirty_snapshot.csv |
| fig_validation.py | BMOPFTools vs OpenDSS, same inverter outputs | pf_validation_lv3_pinned.csv |
| fig_logic.py | block diagram of one example, step by step | (drawing only) |

`data.py` collects the numbers shared by several plots; `style.py` sets colours and fonts. The scripts need Python 3 with pandas, NumPy and matplotlib.

**Font.** For the hand-drawn look, put `xkcd-script.ttf` from [ipython/xkcd-font](https://github.com/ipython/xkcd-font) in this folder (the font file is not included here); without it the plots use DejaVu Sans. The xkcd Script font is made by the ipython/xkcd-font contributors from the handwriting of Randall Munroe (xkcd) and is licensed under [CC BY-NC 3.0](https://creativecommons.org/licenses/by-nc/3.0/), as stated in that repository.

**Licence of the images.** The scripts are MIT (see ../LICENSE). The PNG images that show results (all except `fig_logic.png`) are derived from the CSIRO street models, so they are shared under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (see ../data/networks/LICENSE.md). Images drawn with the xkcd Script font also carry that font's non-commercial terms.
