# Paper version of Fig. 1 (Oct 2026): one row per record error, basic vs dropout-secure DOE, 12:00.
# Sized for one column of the two-column paper. Every number is read from ../results.
# Run from the figures folder:  python fig_service_errors_paper.py
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from matplotlib.patches import Patch
from style import *
setup()

se = pd.read_csv("../results/doe_service_errors_1200.csv")
ds = pd.read_csv("../results/doe_dropout_service_lv3.csv"); ds = ds[ds.setting == "day_1200"]
ts = pd.read_csv("../results/doe_timeseries_type_l3432.csv")
basic_of = lambda sc, lv: float(se[(se.scenario == sc) & np.isclose(se.level.astype(float), lv)].overpromise_pct.iloc[0])
safe_of = lambda tr: float(ds[ds.truth == tr].gap_pct.iloc[0])

rows = [  # label, basic DOE % too high, dropout-secure DOE % too high
    ("Cable type\none home's service is overhead\n16 mm² ABC, not underground",
     float(ts[ts.time == "12:00"].A_overpromise_pct.iloc[0]), safe_of("type_l3432")),
    ("Cable length\nevery home service 25 % longer\n(route not in the records)",
     basic_of("lengthbias", 1.25), safe_of("lengthbias_1.25")),
    ("House wiring\nmeter to inverter at the\nAS/NZS 4777.1 1 % limit",
     basic_of("wiring", 1.0), safe_of("wiring_100")),
]

fig, ax = plt.subplots(figsize=(8.8, 6.0))
fig.subplots_adjust(left=0.43, right=0.97, top=0.80, bottom=0.14)
fig.suptitle("How much too high is the DOE\nfrom the cable records?", fontsize=20, x=0.03, ha="left", y=0.98)
y = np.arange(len(rows))[::-1].astype(float); h = 0.36
for yi, (lab, b, s) in zip(y, rows):
    ax.barh(yi + h / 2, b, height=h, color=BASIC_C)
    ax.barh(yi - h / 2, s, height=h, color=SAFER_C)
    ax.text(max(b, 0) + 0.8, yi + h / 2, f"{b:.0f} %", va="center", fontsize=15)
    ax.text(max(s, 0) + 0.8, yi - h / 2, f"{s:.0f} %", va="center", fontsize=15)
    ax.text(-0.02, yi, lab, transform=ax.get_yaxis_transform(), ha="right", va="center", fontsize=13.5, linespacing=1.25)
ax.axvline(0, color=INK, lw=1.4)
ax.set_yticks([]); ax.set_xlim(0, 45); ax.set_ylim(-0.7, len(rows) - 0.3)
ax.set_xlabel("records' DOE above the true-street DOE (%)", fontsize=14)
ax.spines["left"].set_visible(False); ax.grid(axis="y", visible=False)
ax.legend(handles=[Patch(color=BASIC_C, label="basic DOE"), Patch(color=SAFER_C, label="dropout-secure DOE")],
          loc="lower right", frameon=False, fontsize=14)
fig.text(0.03, 0.835, "12-home four-wire feeder (CSIRO LV3), 12:00, supply 1.03 pu. 0 % = records exactly right.",
         fontsize=12, color=MUTED)
fig.text(0.03, 0.015, "Data: results/doe_service_errors_1200.csv, doe_dropout_service_lv3.csv, doe_timeseries_type_l3432.csv",
         fontsize=9, color=MUTED)
fig.savefig("fig_service_errors_paper.png", dpi=300)
print([(r[0].split("\n")[0], round(r[1], 1), round(r[2], 1)) for r in rows])
