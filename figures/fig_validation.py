# fig_validation.py: draws fig_validation.png, BMOPFTools vs OpenDSS voltages with the same
# inverter outputs (12-home street). Reads results/pf_validation_lv3_pinned.csv.
# Run from this folder: python fig_validation.py
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from style import *
setup()
d = pd.read_csv("../results/pf_validation_lv3_pinned.csv"); d = d[d.bus != "b804"]   # b804 = 11 kV side
pn = d[d.quantity != "n-g"]; ng = d[d.quantity == "n-g"]
mx = pn.diff_V.abs().max(); mx_n = ng.diff_V.abs().max()
fig, (a1, a2) = plt.subplots(1, 2, figsize=(12.5, 6.4), gridspec_kw={"width_ratios": [1, 1.1], "wspace": 0.35})
fig.suptitle("The calculator and a second, separate program agree", fontsize=22, x=0.03, ha="left", y=0.985)
fig.text(0.03, 0.885, f"12-home street: all {len(pn)} phase voltages at its {pn.bus.nunique()} low-voltage points, "
         "both programs given the same power at every inverter", fontsize=14, color=MUTED, ha="left")
lo, hi = 243.0, 246.3
a1.plot([lo, hi], [lo, hi], color=GREY, lw=2, ls="--", zorder=2)
a1.text(243.75, 245.3, "dashed line =\nperfect agreement", color=MUTED, fontsize=13, ha="center")
a1.scatter(pn.v_opendss_V, pn.v_bmopf_V, s=60, color=LV3_C, edgecolors=BG, linewidths=1.2, zorder=3)
a1.set_xlim(lo, hi); a1.set_ylim(lo, hi); a1.set_aspect("equal")
a1.set_xticks([243.5, 244.5, 245.5]); a1.set_yticks([243.5, 244.5, 245.5])
a1.set_xlabel("OpenDSS (V)"); a1.set_ylabel("BMOPFTools (V)")
a1.set_title("same voltages from both", loc="left", fontsize=17, color=MUTED)
# right: the differences
rng = np.random.default_rng(1)
y = rng.uniform(-0.3, 0.3, len(pn))
a2.axvspan(-0.25, 0.25, color=GRID, alpha=0.0)
a2.axvline(0, color=GREY, lw=2, ls="--")
a2.scatter(pn.diff_V, y, s=55, color=LV3_C, edgecolors=BG, linewidths=1, zorder=3)
a2.set_xlim(-0.5, 0.5); a2.set_ylim(-1, 1); a2.set_yticks([])
a2.set_xlabel("BMOPFTools minus OpenDSS (V)")
a2.set_title("how far apart (each dot = one voltage)", loc="left", fontsize=17, color=MUTED)
a2.text(0.27, 0.55, f"largest difference: {mx:.2f} V\n(less than 0.05 % of 230 V)", ha="center", fontsize=16, color=INK)
a2.spines["left"].set_visible(False)
fig.text(0.03, 0.015, "Calculator = BMOPFTools by Frederik Geth; second program = OpenDSS (EPRI).\nThis checks the network model: active and reactive power at each inverter fixed to the same values in both. "
         f"Neutral voltages agree within {mx_n:.3f} V.\nOutputs are fixed because BMOPFTools' plain power flow does not apply the inverter rules, so this is the like-for-like test. "
         "Data: results/pf_validation_lv3_pinned.csv", fontsize=10.5, color=MUTED, va="bottom")
fig.subplots_adjust(top=0.78, bottom=0.24, left=0.08, right=0.97)
fig.savefig("fig_validation.png", dpi=200); print(round(mx, 4), round(mx_n, 4))
