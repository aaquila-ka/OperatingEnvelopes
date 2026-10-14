import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from style import *
from data import WR
setup()
# LV3, 12:00 on the profile day (day index 350, lowest demand in the dataset), source 1.03 pu, dropout-secure equal DOE
# results/doe_dropout_records_lv3.csv: issued 3.664, correct 1.947 kW;
# issued on true network worst 255.05 V (worst of the 85 on/off cases)
correct, issued = WR["correct"], WR["issued"]
v_issued, v_correct = WR["v_issued"], 253.0   # correct DOE passes all 85 checks (<= 253 V)
fig, (a1, a2) = plt.subplots(1, 2, figsize=(12, 5.6), gridspec_kw={"width_ratios": [1.15, 1], "wspace": 0.35})
fig.suptitle("A wrong cable record makes the export limit too generous", fontsize=22, x=0.03, ha="left", y=0.99)
fig.text(0.03, 0.885, "12-home street (CSIRO LV3), midday, supply voltage 1.03, safer limit (also safe when homes switch off)",
         fontsize=14, color=MUTED, ha="left")
# left: limits
bars = a1.bar([0, 1], [correct, issued], width=0.55, color=[TRUE_C, WRONG_C], zorder=3)
for b in bars:
    b.set_path_effects([])
a1.set_xticks([0, 1], ["using the TRUE\ncables", "using the WRONG\ncable map"])
a1.set_ylabel("export limit per home (kW)")
a1.set_ylim(0, 4.6)
a1.text(0, correct + 0.12, f"{correct:.2f} kW", ha="center", fontsize=17, color=TRUE_C)
a1.text(1, issued + 0.12, f"{issued:.2f} kW", ha="center", fontsize=17, color=WRONG_C)
a1.annotate("", xy=(1.36, issued), xytext=(1.36, correct),
            arrowprops=dict(arrowstyle="<->", color=INK, lw=2))
a1.text(1.42, (issued + correct) / 2, f"about +1.7 kW\ntoo generous\n(+{100*(issued/correct-1):.0f} %)",
        va="center", fontsize=14)
a1.set_xlim(-0.5, 2.1)
a1.grid(axis="x", visible=False)
a1.set_title("the limit", loc="left", fontsize=17, color=MUTED)
# right: highest voltage on the real street
a2.axhspan(253, 256.6, color=LIMIT_C, alpha=0.08, zorder=0)
a2.axhline(253, color=LIMIT_C, lw=2.2, ls="--", zorder=2)
a2.text(0.5, 253.12, "safe limit 253 V", color=LIMIT_C, fontsize=15, ha="center", va="bottom")
a2.vlines([0, 1], 250, [v_correct, v_issued], colors=[TRUE_C, WRONG_C], lw=3, zorder=3)
a2.scatter([0, 1], [v_correct, v_issued], s=260, c=[TRUE_C, WRONG_C], zorder=4, edgecolors=BG, linewidths=2)
a2.set_ylim(250, 256.6)
a2.set_xticks([0, 1], ["true-cable\nlimit", "wrong-map\nlimit"])
a2.set_ylabel("highest home voltage on the REAL\nstreet, worst on/off case (V)")
a2.text(0.1, v_correct - 0.25, "at most 253 V\n(passes all 85 checks)", ha="left", va="top", fontsize=15, color=TRUE_C)
a2.text(0.88, v_issued + 0.25, f"{v_issued:.2f} V\n(over the limit)", ha="right", fontsize=15, color=WRONG_C)
a2.set_xlim(-0.5, 1.5)
a2.grid(axis="x", visible=False)
a2.set_title("what really happens", loc="left", fontsize=17, color=MUTED)
fig.text(0.03, 0.01, "Real street: all 22 service cables are 4 mm\u00b2, map says 16 mm\u00b2 (85 of 85 on/off cases go over 253 V). With only the one critical cable wrong: same limits,\n"
         "same 255.05 V, 70 of 85 cases over. Voltage axis starts at 250 V. Data: results/doe_dropout_records_lv3.csv", fontsize=10.5, color=MUTED)
fig.subplots_adjust(top=0.78, bottom=0.2, left=0.08, right=0.97)
fig.savefig("fig_wrong_record.png", dpi=200)
print("ok")
