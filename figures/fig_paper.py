"""Conference paper figures, drawn from real result files (12-home street, 1.03 pu, basic DOE).
fig_paper_1.png: gap at 12:00 for every tested record error (results/doe_record_errors_1200.csv, 20 draws each,
                 plus all 22 segments from results/doe_source_sweep.csv).
fig_paper_2.png: highest home voltage on the true street over the measured day (results/doe_timeseries.csv).
Colours chosen to stay readable in black and white."""
import os
import matplotlib as mpl
mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np, pandas as pd
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
if not os.path.exists(R):
    R = "/home/claude/operatingenvelopes/results"
mpl.rcParams.update({"font.family": "DejaVu Serif", "font.size": 8, "axes.linewidth": 0.7,
                     "axes.spines.top": False, "axes.spines.right": False,
                     "xtick.labelsize": 7.5, "ytick.labelsize": 7.5, "axes.labelsize": 8})
TEAL, ORANGE, RED = "#0B6466", "#E8743B", "#B0262F"
W = 3.0  # inches, one column

# ---- Fig. 1: record errors at 12:00
e = pd.read_csv(os.path.join(R, "doe_record_errors_1200.csv"))
s = pd.read_csv(os.path.join(R, "doe_source_sweep.csv"))
all22 = float(s[(s.setting == "day_1200") & (abs(s.source_pu - 1.03) < 1e-6)].A_gap_kW.iloc[0])
fig, a = plt.subplots(figsize=(W, 1.6))
groups = [("scatter", 0.05, "5"), ("scatter", 0.10, "10"), ("scatter", 0.20, "20"),
          ("wrongtype", 2.0, "2"), ("wrongtype", 5.0, "5"), ("wrongtype", 11.0, "11")]
rng = np.random.default_rng(1)
for i, (sc, lv, lab) in enumerate(groups):
    g = e[(e.scenario == sc) & (np.isclose(e.level, lv))].gap_kW.values
    a.scatter(i + rng.uniform(-0.2, 0.2, len(g)), g, s=9, c=TEAL if sc == "scatter" else ORANGE,
              edgecolors="black", linewidths=0.3, zorder=3)
a.scatter([6], [all22], s=18, marker="D", c=ORANGE, edgecolors="black", linewidths=0.4, zorder=3)
a.axhline(0, color="black", lw=0.6)
a.axvline(2.5, color="0.6", lw=0.5, ls=":")
a.set_xticks(range(7), [g[2] for g in groups] + ["22"])
a.text(1, -0.27, "scatter in R (%)", ha="center", va="top", fontsize=7.5, transform=a.get_xaxis_transform())
a.text(4.5, -0.27, "segments 4 mm²", ha="center", va="top", fontsize=7.5, transform=a.get_xaxis_transform())
a.set_ylim(-0.4, 2.6)
a.set_ylabel("gap (kW)")
fig.subplots_adjust(left=0.17, right=0.98, top=0.96, bottom=0.33)
fig.savefig("fig_paper_1.png", dpi=400)

# ---- Fig. 2: one measured day
t = pd.read_csv(os.path.join(R, "doe_timeseries.csv"))
day = t[t.daylight == "yes"]
hrs = np.array([int(x[:2]) + int(x[3:]) / 60 for x in day.time])
v = day.A_pv_V_VW.values
fig, a = plt.subplots(figsize=(W, 1.4))
a.axhline(253, color=RED, lw=0.8, ls="--")
a.plot(hrs, v, "-o", color=ORANGE, ms=2.4, mec="black", mew=0.3, lw=1)
a.fill_between(hrs, 253, v, where=v > 253, color=ORANGE, alpha=0.25, lw=0)
a.text(6.2, 253.12, "253 V", fontsize=7.5, color=RED)
over = int((v > 253.005).sum()); k = int(np.nanargmax(v))
a.text(hrs[k] + 0.3, v[k] + 0.05, f"{v[k]:.2f} V", fontsize=7.5)
a.text(18.9, 254.45, f"{over} half-hours\nabove 253 V", fontsize=7.5, ha="right")
a.set_xlim(6, 19); a.set_xticks([6, 8, 10, 12, 14, 16, 18])
a.set_ylim(250.8, 255.6)
a.set_xlabel("hour of day")
a.set_ylabel("highest voltage (V)")
fig.subplots_adjust(left=0.17, right=0.98, top=0.96, bottom=0.3)
fig.savefig("fig_paper_2.png", dpi=400)
print("all22", round(all22, 3), "over", over, "peak", round(np.nanmax(v), 2))
