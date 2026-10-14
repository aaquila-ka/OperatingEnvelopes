import matplotlib.pyplot as plt, numpy as np
from style import *
from data import SAFER
setup()
fig, ax = plt.subplots(figsize=(12, 6.2))
fig.suptitle("A safer limit shrinks the over-promise, but a wrong map can still over-promise",
             fontsize=21, x=0.03, ha="left", y=0.985)
fig.text(0.03, 0.875, "How much too generous the export limit is (kW per home), when the cable map is wrong",
         fontsize=14, color=MUTED, ha="left")
x = np.arange(len(SAFER)); w = 0.34
basic = [r[1] for r in SAFER]; safer = [r[2] for r in SAFER]
b1 = ax.bar(x - w/2, basic, w, color=BASIC_C, zorder=3, label="basic limit (checked with everyone exporting)")
b2 = ax.bar(x + w/2, safer, w, color=SAFER_C, zorder=3, label="safer limit (also safe when homes switch off)")
for i, (b, s) in enumerate(zip(basic, safer)):
    ax.text(i - w/2, b + 0.05, f"{b + 1e-9:.2f}", ha="center", fontsize=16, color=INK)
    ax.text(i + w/2, s + 0.05, f"{s + 1e-9:.2f}", ha="center", fontsize=16, color=INK)
    ax.text(i, max(b, s) + 0.33, f"{100*(1-s/b):.0f} % smaller", ha="center", fontsize=15, color=INK)
ax.set_xticks(x, [r[0] for r in SAFER])
ax.set_ylabel("too generous by (kW per home)")
ax.set_ylim(0, 2.95)
ax.grid(axis="x", visible=False)
ax.legend(loc="upper right", frameon=False)
ax.text(2.42, 1.35, "still above zero:\nbeing more careful\ndoes not fix\na wrong map", ha="left",
        va="center", fontsize=14, color=MUTED)
ax.set_xlim(-0.55, 3.15)
fig.text(0.03, 0.02,
         "Supply voltage 1.03 (12-home street) and 0.94 (123-home street). Wrong map: 12-home street, all 22 service cables really 4 mm\u00b2; "
         "123-home street, its 12 shared cables.\nData (results/): basic = doe_dirty_snapshot.csv, doe_robust.csv, lv9/lv9_sweep.csv; "
         "safer = doe_dropout_records_lv3.csv, lv9/lv9_dropout_records.csv.\n123-home street at supply 1.00: the safer gap is only 0.12 kW.", fontsize=10.5, color=MUTED, va="bottom")
fig.subplots_adjust(top=0.78, bottom=0.28, left=0.08, right=0.98)
fig.savefig("fig_safer.png", dpi=200)
print("ok")
