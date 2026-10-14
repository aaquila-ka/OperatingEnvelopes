"""Conference paper figure: real results from many runs (12-home street, 1.03 pu, basic DOE).
(a) gap at 12:00 for every tested record error (results/doe_record_errors_1200.csv, 20 draws each);
(b) highest home voltage on the true street over the measured day (results/doe_timeseries.csv).
Colours chosen to stay readable in black and white."""
import os
import matplotlib as mpl
mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np, pandas as pd
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
if not os.path.exists(R):
    R = "/home/claude/operatingenvelopes/results"
mpl.rcParams.update({"font.family": "DejaVu Serif", "font.size": 7.5, "axes.linewidth": 0.7,
                     "axes.spines.top": False, "axes.spines.right": False,
                     "xtick.labelsize": 6.5, "ytick.labelsize": 6.5, "axes.labelsize": 7})
TEAL, ORANGE, RED = "#0B6466", "#E8743B", "#B0262F"
e = pd.read_csv(os.path.join(R, "doe_record_errors_1200.csv"))
s = pd.read_csv(os.path.join(R, "doe_source_sweep.csv"))
all22 = float(s[(s.setting == "day_1200") & (abs(s.source_pu - 1.03) < 1e-6)].A_gap_kW.iloc[0])
t = pd.read_csv(os.path.join(R, "doe_timeseries.csv"))

fig, (a1, a2) = plt.subplots(1, 2, figsize=(3.3, 2.3), gridspec_kw={"wspace": 0.62, "width_ratios": [1.05, 1]})
groups = [("scatter", 0.05, "5"), ("scatter", 0.10, "10"), ("scatter", 0.20, "20"),
          ("wrongtype", 2.0, "2"), ("wrongtype", 5.0, "5"), ("wrongtype", 11.0, "11")]
rng = np.random.default_rng(1)
for i, (sc, lv, lab) in enumerate(groups):
    g = e[(e.scenario == sc) & (np.isclose(e.level, lv))].gap_kW.values
    x = i + rng.uniform(-0.18, 0.18, len(g))
    a1.scatter(x, g, s=6, c=TEAL if sc == "scatter" else ORANGE, edgecolors="black", linewidths=0.25, zorder=3)
a1.scatter([6], [all22], s=14, marker="D", c=ORANGE, edgecolors="black", linewidths=0.4, zorder=3)
a1.axhline(0, color="black", lw=0.6)
a1.set_xticks(range(7), [g[2] for g in groups] + ["22"], fontsize=6.5)
a1.text(1, -0.16, "scatter\n(%)", ha="center", va="top", fontsize=6.5, transform=a1.get_xaxis_transform())
a1.text(4.5, -0.16, "4 mm²\nsegments", ha="center", va="top", fontsize=6.5, transform=a1.get_xaxis_transform())
a1.set_ylim(-0.4, 2.6)
a1.set_ylabel("gap: too generous by (kW)")
a1.set_title("(a) record errors, 12:00", fontsize=7, loc="left")

day = t[t.daylight == "yes"] if "daylight" in t else t
hrs = [int(x[:2]) + int(x[3:]) / 60 for x in day.time]
v = day.A_pv_V_VW.values
a2.axhline(253, color=RED, lw=0.8, ls="--")
a2.plot(hrs, v, "-o", color=ORANGE, ms=2, mec="black", mew=0.25, lw=0.9)
a2.fill_between(hrs, 253, v, where=v > 253, color=ORANGE, alpha=0.25, lw=0)
a2.text(6.3, 253.12, "253 V", fontsize=6.5, color=RED)
over = int((v > 253.005).sum())
k = int(np.nanargmax(v))
a2.annotate(f"{v[k]:.2f} V", (hrs[k], v[k]), xytext=(hrs[k] - 5.2, v[k] + 0.2), fontsize=6.5,
            arrowprops=dict(arrowstyle="-", lw=0.4))
a2.text(13.0, 251.25, f"{over} half-hours\nabove 253 V", fontsize=6.5, ha="center")
a2.set_xlim(6, 19); a2.set_xticks([6, 9, 12, 15, 18], ["6", "9", "12", "15", "18"])
a2.set_ylim(250.5, 255.6)
a2.set_xlabel("hour of day")
a2.set_ylabel("highest home voltage (V)")
a2.set_title("(b) one day", fontsize=7, loc="left")
fig.subplots_adjust(left=0.15, right=0.98, top=0.9, bottom=0.25)
fig.savefig("fig_paper.png", dpi=400)
print("all22", round(all22, 3), "over", over, "peak", round(np.nanmax(v), 2))
