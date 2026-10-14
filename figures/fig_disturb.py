import matplotlib.pyplot as plt, pandas as pd, numpy as np
from matplotlib.patches import FancyBboxPatch
from style import *
setup()
re = pd.read_csv("../results/doe_record_errors.csv")
cc = pd.read_csv("../results/doe_critical_cables.csv")
dd = pd.read_csv("../results/doe_dirty_snapshot.csv").iloc[0]
rows = [("scatter  5 %", re[(re.scenario == "scatter") & (re.level == 0.05)].gap_kW, AQUA),
        ("scatter 10 %", re[(re.scenario == "scatter") & (re.level == 0.10)].gap_kW, AQUA),
        ("scatter 20 %", re[(re.scenario == "scatter") & (re.level == 0.20)].gap_kW, AQUA),
        ("2 of 22 cables wrong type", re[(re.scenario == "wrongtype") & (re.level == 2)].gap_kW, WRONG_C),
        ("5 of 22 cables wrong type", re[(re.scenario == "wrongtype") & (re.level == 5)].gap_kW, WRONG_C),
        ("11 of 22 cables wrong type", re[(re.scenario == "wrongtype") & (re.level == 11)].gap_kW, WRONG_C),
        ("one cable at a time (22 tests)", cc.gap_kW, LV3_C),
        ("all 22 cables wrong type", pd.Series([dd.issued_limit_kW - dd.correct_limit_kW]), LIMIT_C)]
fig = plt.figure(figsize=(13.5, 7.4))
fig.suptitle("How we made the cable records 'dirty', and what it did", fontsize=22, x=0.03, ha="left", y=0.985)
fig.text(0.03, 0.915, "The records always say 16 mm² for every service cable. We change the TRUE street, "
         "then compare the limit from the records with the limit from the true street.", fontsize=13.5, color=MUTED)
# left: the three kinds of disturbance, in words and one formula each
ax0 = fig.add_axes([0.02, 0.08, 0.36, 0.78]); ax0.axis("off")
cards = [
 (AQUA, "1. Scatter (small, random)",
  "every one of the 22 cables gets its own factor\n"
  "  R_true = f x R_record,   f = 1 + s x z  (never below 0.5)\n"
  "  z = random normal number,  s = 5, 10 or 20 %"),
 (WRONG_C, "2. Wrong cable type (a mistake)",
  "m of the 22 cables, picked at random, are\nreally 4 mm² (about 3x the resistance)\n"
  "  m = 2, 5 or 11;   20 random draws each"),
 (LV3_C, "3. Find the critical cables",
  "make ONE cable 4 mm² at a time (22 tests),\nthen all 22 together (worst case)\nresult: 12 of the 22 change the limit\non their own; the worst one alone = all 22"),
]
y = 0.98
for col, title, body in cards:
    ax0.add_patch(FancyBboxPatch((0.0, y - 0.30), 1.0, 0.29, boxstyle="round,pad=0.01,rounding_size=0.03",
                                 fc=col, alpha=0.12, ec=col, lw=2, transform=ax0.transAxes))
    ax0.text(0.03, y - 0.04, title, fontsize=16, color=col, va="top", transform=ax0.transAxes)
    ax0.text(0.03, y - 0.10, body, fontsize=12.5, color=INK, va="top", transform=ax0.transAxes, linespacing=1.3)
    y -= 0.33
# right: the result of every draw
ax = fig.add_axes([0.6, 0.14, 0.31, 0.72])
rng = np.random.default_rng(3)
for k, (lab, g, col) in enumerate(rows):
    yy = len(rows) - 1 - k
    ax.scatter(g, yy + rng.uniform(-0.18, 0.18, len(g)), s=46, color=col, edgecolors=BG, linewidths=0.8, zorder=3)
    ax.text(-0.12, yy, lab, ha="right", va="center", fontsize=13)
    ax.text(2.03, yy, f"up to {g.max() + 1e-9:.2f}", ha="left", va="center", fontsize=12.5, color=col)
ax.axvline(0, color=GREY, lw=1.5, ls="--")
ax.set_yticks([]); ax.set_xlim(-0.1, 2.0); ax.set_ylim(-0.6, len(rows) - 0.4)
ax.set_xlabel("limit from records is too generous by (kW per home)")
ax.set_title("each dot = one random 'true street'", loc="left", fontsize=14, color=MUTED)
ax.spines["left"].set_visible(False); ax.grid(axis="y", visible=False)
fig.text(0.03, 0.012, "12-home street (LV3), each home uses 1 kW, supply voltage 1.03, basic limit. At midday the same tests give up to 2.29 kW. "
         "Data: results/doe_record_errors.csv, doe_critical_cables.csv, doe_dirty_snapshot.csv", fontsize=10.5, color=MUTED)
fig.savefig("fig_disturb.png", dpi=200); print("ok")
