# Conference paper Fig. 2: how much the DOE from the cable records exceeds the DOE of the true
# street, for realistic service-line record errors (basic vs dropout-secure DOE), LV3, 12:00, 1.03 pu.
# Sized for one column (7.6 cm) of the two-column UQ template; plain serif style to match the text.
# Every number is read from ../results. Run from the figures folder:  python fig_service_errors_paper.py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from matplotlib.patches import Patch

plt.rcParams.update({"font.family": "serif", "font.serif": ["Times New Roman", "Liberation Serif", "DejaVu Serif"],
                     "font.size": 7.5, "axes.spines.top": False, "axes.spines.right": False})
BASIC_C, SAFE_C = "#E69F00", "#0072B2"   # orange = basic DOE, blue = dropout-secure DOE (colour-blind safe)

se = pd.read_csv("../results/doe_service_errors_1200.csv")
ds = pd.read_csv("../results/doe_dropout_service_lv3.csv"); ds = ds[ds.setting == "day_1200"]
ts = pd.read_csv("../results/doe_timeseries_type_l3432.csv")
basic_of = lambda sc, lv: float(se[(se.scenario == sc) & np.isclose(se.level.astype(float), lv)].overpromise_pct.iloc[0])
safe_of = lambda tr: float(ds[ds.truth == tr].gap_pct.iloc[0])

rows = [  # label, basic DOE % above, dropout-secure DOE % above
    ("Cable type: the 29.5 m service\nof one home is overhead\n16 mm² cable, not underground",
     float(ts[ts.time == "12:00"].A_overpromise_pct.iloc[0]), safe_of("type_l3432")),
    ("Cable length: every home's\nservice is 50 % longer\nthan recorded", basic_of("lengthbias", 1.5), safe_of("lengthbias_1.50")),
    ("Cable length: every home's\nservice is 25 % longer\nthan recorded", basic_of("lengthbias", 1.25), safe_of("lengthbias_1.25")),
    ("House wiring: meter to\ninverter adds a 1 % rise\n(AS/NZS 4777.1 allows 2 %)", basic_of("wiring", 1.0), safe_of("wiring_100")),
]

fig, ax = plt.subplots(figsize=(3.35, 2.15))
fig.subplots_adjust(left=0.47, right=0.97, top=0.98, bottom=0.21)
y = np.arange(len(rows))[::-1].astype(float); h = 0.38
for yi, (lab, b, s) in zip(y, rows):
    ax.barh(yi + h / 2, b, height=h, color=BASIC_C, edgecolor="black", lw=0.4)
    ax.barh(yi - h / 2, s, height=h, color=SAFE_C, edgecolor="black", lw=0.4, hatch="////")
    ax.text(max(b, 0) + 0.6, yi + h / 2, f"{b:.0f} %", va="center", fontsize=7)
    ax.text(max(s, 0) + 0.6, yi - h / 2, f"{s:.0f} %", va="center", fontsize=7)
    ax.text(-0.03, yi, lab, transform=ax.get_yaxis_transform(), ha="right", va="center", fontsize=6.6, linespacing=1.15)
ax.axvline(0, color="black", lw=0.8)
ax.set_yticks([]); ax.set_xlim(0, 44); ax.set_ylim(-0.65, len(rows) - 0.35)
ax.set_xlabel("DOE from the records above the\nDOE of the true street (%)", fontsize=7)
ax.spines["left"].set_visible(False); ax.grid(axis="x", color="#DDDDDD", lw=0.5); ax.set_axisbelow(True)
ax.legend(handles=[Patch(facecolor=BASIC_C, edgecolor="black", lw=0.4, label="basic DOE"),
                   Patch(facecolor=SAFE_C, edgecolor="black", lw=0.4, hatch="////", label="dropout-secure DOE")],
          loc="lower right", frameon=False, fontsize=6.8)
fig.savefig("fig_service_errors_paper.png", dpi=400)
print([(r[0].split(":")[0], round(r[1], 1), round(r[2], 1)) for r in rows])
