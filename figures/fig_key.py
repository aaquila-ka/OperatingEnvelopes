# fig_key.py: draws fig_key.png, how much too generous the basic limit is across supply
# voltages on both streets. Reads results/doe_source_sweep.csv and results/lv9/lv9_sweep.csv
# (through data.py). Run from this folder: python fig_key.py
import matplotlib.pyplot as plt
from style import *
from data import *
setup()
fig, (a1, a2) = plt.subplots(1, 2, figsize=(12.5, 6.3), sharey=True,
                             gridspec_kw={"width_ratios": [1.5, 1], "wspace": 0.12})
fig.suptitle("How much a wrong cable record matters depends on the grid's supply voltage",
             fontsize=21, x=0.03, ha="left", y=0.985)
fig.text(0.03, 0.875, "Height = how much too generous the export limit is (kW per home). Basic version of the limit.",
         fontsize=14, color=MUTED, ha="left")
def panel(ax, xs, ys, col, title, xlabel, offsets):
    ax.plot(xs, ys, color=col, lw=3.2, zorder=3)
    ax.scatter(xs, ys, s=150, color=col, edgecolors=BG, linewidths=2, zorder=4)
    for x, y, (dx, dy) in zip(xs, ys, offsets):
        ax.annotate(f"{y:.2f}", (x, y), xytext=(dx, dy), textcoords="offset points",
                    ha="center", fontsize=15, color=col)
    ax.set_title(title, loc="left", fontsize=17, color=MUTED)
    ax.set_xlabel(xlabel)
    ax.grid(axis="x", visible=False)
panel(a1, LV3_SWEEP_PU, LV3_SWEEP_GAP, LV3_C, "12-home street (LV3), midday",
      "supply voltage from the grid (1.00 = normal)", [(0, 12), (0, 12), (-14, 10), (-18, 6), (0, 12), (24, 8)])
a1.set_xticks(LV3_SWEEP_PU, ["1.00", "1.01", "1.02", "1.025", "1.03", "1.035"])
a1.set_xlim(0.995, 1.052)
a1.annotate("worst of the\nvalues tested", xy=(1.03, 2.29), xytext=(1.012, 2.25), fontsize=15, color=INK,
            arrowprops=dict(arrowstyle="->", color=INK, lw=1.8), va="center")
a1.text(1.0365, 1.5, "at 1.035 even the\nmap-based limit is\ncut back hard, so\nless is left to\nover-promise",
        fontsize=12.5, color=MUTED, ha="left", va="center")
a1.set_ylabel("too generous by (kW per home)")
a1.set_ylim(0, 2.75)
panel(a2, LV9_SWEEP_PU, LV9_SWEEP_GAP, LV9_C, "123-home street (LV9), each home uses 1 kW",
      "supply voltage from the grid (1.00 = normal)", [(10, 10), (8, 10), (0, 12)])
a2.set_xticks(LV9_SWEEP_PU, ["0.94", "0.97", "1.00"])
a2.set_xlim(0.925, 1.015)
a2.text(0.97, 2.2, "falls as voltage rises\n(we have not yet tested\nbelow 0.94)", fontsize=12.5,
        color=MUTED, ha="center", va="center")
fig.text(0.03, 0.02,
         "12-home street: all 22 service-cable segments really 4 mm\u00b2, map says 16 mm\u00b2 (results/doe_source_sweep.csv, 12:00 rows). "
         "123-home street: its 12 shared cables wrong (results/lv9/lv9_sweep.csv).\n"
         "At low supply voltage both 12-home limits sit near the inverter size (5 kVA), so the wrong map changes little. The 123-home street is already voltage-squeezed\n"
         "at 0.94 (its transformer is set 2.5 % higher, so its 1.00 is about the 12-home street's 1.025), so we only see its falling side.", fontsize=10.5, color=MUTED, va="bottom")
fig.subplots_adjust(top=0.78, bottom=0.25, left=0.07, right=0.98)
fig.savefig("fig_key.png", dpi=200)
print("ok")
