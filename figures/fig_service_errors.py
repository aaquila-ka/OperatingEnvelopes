# New Fig. 1 (Oct 2026): plausible service-record errors at 12:00, basic and dropout-secure DOE.
# Every number is read from ../results. Run from the figures folder:  python fig_service_errors.py
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from matplotlib.lines import Line2D
from style import *
setup()

se = pd.read_csv("../results/doe_service_errors_1200.csv")
ds = pd.read_csv("../results/doe_dropout_service_lv3.csv"); ds = ds[ds.setting == "day_1200"]
ts = pd.read_csv("../results/doe_timeseries_type_l3432.csv")
crit_basic = float(ts[ts.time == "12:00"].A_overpromise_pct.iloc[0])     # critical home only, basic DOE
dsv = lambda tr: float(ds[ds.truth == tr].gap_pct.iloc[0])                # dropout-secure, % too high
g = lambda sc, lv: se[(se.scenario == sc) & np.isclose(se.level.astype(float), lv)].overpromise_pct

TYPE_C, LEN_C, BIAS_C, WIRE_C = WRONG_C, AQUA, BLUE, LV3_C
groups = [
 ("Cable type: records say underground 16 mm² Cu, true service is overhead 16 mm² ABC (1.59 x R)", TYPE_C, [
    ("critical home only (29.5 m)", pd.Series([crit_basic]), dsv("type_l3432")),
    ("1 random home", g("type", 1), None),
    ("3 random homes", g("type", 3), None),
    ("6 random homes", g("type", 6), None),
    ("all 12 homes", g("type", 12), dsv("type_all12"))]),
 ("Length scatter: junction and meter positions approximate", LEN_C, [
    ("each service ±10 %", g("length", 0.10), None),
    ("each service ±20 %", g("length", 0.20), None),
    ("each service ±30 %", g("length", 0.30), None)]),
 ("Length bias: cable route not modelled, every home service longer", BIAS_C, [
    ("all services +10 %", g("lengthbias", 1.10), None),
    ("all services +25 %", g("lengthbias", 1.25), dsv("lengthbias_1.25")),
    ("all services +50 %", g("lengthbias", 1.50), dsv("lengthbias_1.50"))]),
 ("House wiring, meter to inverter (AS/NZS 4777.1 1 % rise: up to 0.106 Ω loop)", WIRE_C, [
    ("25 % of the allowance", g("wiring", 0.25), None),
    ("50 % of the allowance", g("wiring", 0.50), None),
    ("100 % of the allowance", g("wiring", 1.00), dsv("wiring_100"))]),
]

fig = plt.figure(figsize=(13.5, 10.5))
fig.suptitle("How much too high is the DOE computed from the cable records?", fontsize=22, x=0.03, ha="left", y=0.985)
fig.text(0.03, 0.905, "12-home four-wire street (CSIRO LV3), 12:00 measured loads, supply 1.03 pu, equal sharing. "
         "Records: every home service 16 mm² Cu\nunderground, inverter at the meter. The true street differs in one way "
         "at a time; the DOE from the records is compared with the true-street DOE.", fontsize=13, color=MUTED)
ax = fig.add_axes([0.33, 0.09, 0.52, 0.71])
tr = ax.get_yaxis_transform()
rng = np.random.default_rng(3)
y = 0.0
for title, col, rows in groups:
    ax.text(-0.58, y, title, transform=tr, fontsize=14, color=col, va="center", ha="left", fontweight="bold")
    y -= 1.0
    for lab, s, dval in rows:
        s = s.dropna()
        ax.scatter(s, y + rng.uniform(-0.18, 0.18, len(s)), s=52, color=col, edgecolors=BG, linewidths=0.8, zorder=3)
        if dval is not None:
            ax.scatter([dval], [y], marker="D", s=95, color=SAFER_C, edgecolors=INK, linewidths=1.0, zorder=4)
        ax.text(-0.015, y, lab, transform=tr, ha="right", va="center", fontsize=13)
        txt = f"up to {s.max():.0f} %" if len(s) > 1 else f"{s.iloc[0]:+.0f} %"
        if dval is not None:
            txt += f"   ◆ {dval:.0f} %"
        ax.text(1.015, y, txt, transform=tr, ha="left", va="center", fontsize=12.5, color=col)  # value(s) of this row
        y -= 1.0
    y -= 0.5
ax.axvline(0, color=GREY, lw=1.5, ls="--")
ax.set_ylim(y + 1.0, 0.6); ax.set_yticks([]); ax.set_xlim(-5, 45)
ax.set_xlabel("DOE from the records above the true-street DOE (%)")
ax.spines["left"].set_visible(False); ax.grid(axis="y", visible=False)
handles = [Line2D([], [], marker="o", ls="", color=GREY, ms=9, label="basic DOE, one dot per random true street (20 draws)"),
           Line2D([], [], marker="D", ls="", color=SAFER_C, mec=INK, ms=9, label="dropout-secure DOE (85 on/off cases)")]
fig.legend(handles=handles, loc="upper left", bbox_to_anchor=(0.03, 0.855), ncol=2, frameon=False, fontsize=13)
fig.text(0.03, 0.012, "Below 0 % the records give a lower DOE than the true street. "
         "Data: results/doe_service_errors_1200.csv, doe_dropout_service_lv3.csv, doe_timeseries_type_l3432.csv",
         fontsize=10.5, color=MUTED)
fig.savefig("fig_service_errors.png", dpi=200)
print("critical home: basic", round(crit_basic, 1), "% / dropout-secure", round(dsv("type_l3432"), 1), "%")
