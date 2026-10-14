"""Column-width version of the main result for the conference paper.
Colour to match the poster, but dark teal vs light orange so it still reads in black and white."""
import matplotlib as mpl
mpl.use("Agg")
import matplotlib.pyplot as plt
from data import WR

mpl.rcParams.update({"font.family": "DejaVu Serif", "font.size": 8, "axes.linewidth": 0.8,
                     "axes.spines.top": False, "axes.spines.right": False})
correct, issued, v_issued = WR["correct"], WR["issued"], WR["v_issued"]
fig, (a1, a2) = plt.subplots(1, 2, figsize=(3.3, 2.15), gridspec_kw={"wspace": 0.75})
a1.bar([0, 1], [correct, issued], width=0.6, color=["#0B6466", "#F4A582"], edgecolor="black", lw=0.6)
for x, v in [(0, correct), (1, issued)]:
    a1.text(x, v + 0.08, f"{v:.2f}", ha="center", fontsize=8)
a1.set_xticks([0, 1], ["true\ncables", "wrong\nrecords"])
a1.set_ylabel("export limit per home (kW)")
a1.set_ylim(0, 4.3)
a1.set_title("(a) limit", fontsize=8, loc="left")
a2.axhline(253, color="#B0262F", lw=0.9, ls="--")
a2.text(0.62, 253.1, "253 V limit", ha="center", va="bottom", fontsize=7)
a2.plot([0], [253.0], "o", color="#0B6466", ms=4.5, mec="black", mew=0.5)
a2.plot([1], [v_issued], "o", color="#F4A582", ms=4.5, mec="black", mew=0.5)
a2.vlines([0, 1], 250, [253.0, v_issued], colors=["#0B6466", "#C2410C"], lw=1.2)
a2.text(1, v_issued + 0.28, f"{v_issued:.2f}", ha="center", fontsize=8)
a2.text(0.12, 252.35, "≤ 253", ha="left", fontsize=7)
a2.set_xticks([0, 1], ["true\ncables", "wrong\nrecords"])
a2.set_xlim(-0.6, 1.6)
a2.set_ylim(250, 256)
a2.set_ylabel("highest home voltage (V)")
a2.set_title("(b) true street", fontsize=8, loc="left")
fig.subplots_adjust(left=0.16, right=0.98, top=0.88, bottom=0.2)
fig.savefig("fig_paper.png", dpi=400)
print(correct, issued, v_issued)
