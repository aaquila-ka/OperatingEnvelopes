# fig_day.py: draws fig_day.png, the whole day on the 12-home street: sun, the correct and
# the issued limit, and the highest home voltage. Reads results/doe_timeseries.csv.
# Run from this folder: python fig_day.py
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from style import *
setup()
t = pd.read_csv("../results/doe_timeseries.csv")
h = (t.step - 1) * 0.5                                   # hour of day at start of each half-hour
sun = 5.0 * t.pv_shape
over = t.A_pv_n_over_253 > 0
n_over = int(over.sum()); pk = t.A_pv_V_VW.max(); pk_t = t.loc[t.A_pv_V_VW.idxmax(), "time"]
gmin, gmax = t.A_gap_kW.min(), t.A_gap_kW.max()
fig, (a1, a2) = plt.subplots(2, 1, figsize=(12.5, 8.4), sharex=True, gridspec_kw={"hspace": 0.32})
fig.suptitle("Over a whole day, the wrong-map limit stays about 2 kW too generous",
             fontsize=22, x=0.03, ha="left", y=0.99)
fig.text(0.03, 0.915, "12-home street (LV3), supply voltage 1.03, real home use on one day "
         "(the lowest-demand day in the dataset), basic version of the limit", fontsize=13.5, color=MUTED)
hh = np.append(h, 24.0); ext = lambda v: np.append(np.asarray(v), np.asarray(v)[-1])
a1.fill_between(hh, 0, ext(sun), step="post", color="#f6c945", alpha=0.35, lw=0, label="sun available per home")
a1.step(hh, ext(t.clean_kW), where="post", color=WRONG_C, lw=3, label="limit from the WRONG cable map")
a1.step(hh, ext(t.A_correct_kW), where="post", color=TRUE_C, lw=3, label="limit using the TRUE cables")
a1.set_ylabel("kW per home"); a1.set_ylim(0, 5.6)
a1.legend(loc="upper left", frameon=False, ncol=3, fontsize=13)
a1.text(21.2, 3.1, f"gap all day:\n{gmin:.1f} to {gmax:.1f} kW", fontsize=14, ha="center", color=INK)
a1.text(3.3, 0.7, "whenever the sun rises above the\nTRUE limit, the street goes\nover 253 V (see below)", fontsize=12, ha="center", va="center", color=MUTED)
a1.set_title("the export limit", loc="left", fontsize=16, color=MUTED)
a1.grid(axis="x", visible=False)
# bottom: what really happens when homes export what the sun gives, up to the wrong-map limit
idx = list(np.where(over)[0]); runs = []
for i in idx:
    if runs and i == runs[-1][1] + 1: runs[-1][1] = i
    else: runs.append([i, i])
for a, b in runs:
    a2.axvspan(h[a], h[b] + 0.5, color=LIMIT_C, alpha=0.12, lw=0)
a2.axhline(253, color=LIMIT_C, lw=2.2, ls="--")
a2.text(0.3, 253.12, "safe limit 253 V", color=LIMIT_C, fontsize=14, va="bottom")
day = t.A_pv_V_VW.notna()
a2.plot(h[day] + 0.25, t.A_pv_V_VW[day], color=WRONG_C, lw=3, marker="o", ms=5)
a2.set_ylim(250.5, 255.8)
a2.set_ylabel("highest home\nvoltage (V)")
a2.set_title("what really happens on the true street: homes export all their sun (the ~4 kW wrong-map limit never stops them)",
             loc="left", fontsize=15, color=MUTED)
a2.annotate(f"peak {pk:.2f} V (11:30 to 12:00)", xy=(h[t.A_pv_V_VW.idxmax()] + 0.25, pk), xytext=(14.6, 255.45),
            fontsize=14, arrowprops=dict(arrowstyle="->", color=INK, lw=1.6), va="center")
a2.text(5.0, 254.6, f"{n_over} half-hours above 253 V\n(shaded)", fontsize=14, ha="center", color=LIMIT_C)
a2.set_xticks(range(0, 25, 3), [f"{x:02d}:00" for x in range(0, 25, 3)])
a2.set_xlim(0, 24); a2.set_xlabel("time of day")
a2.grid(axis="x", visible=False)
fig.text(0.03, 0.008, "Wrong map: all 22 service-cable segments really 4 mm², map says 16 mm². "
         "Inverter Volt-VAr and Volt-Watt on. Voltage only shown while the sun is up. Data: results/doe_timeseries.csv", fontsize=10.5, color=MUTED)
fig.subplots_adjust(top=0.85, bottom=0.12, left=0.1, right=0.98)
fig.savefig("fig_day.png", dpi=200)
print(n_over, round(pk, 2), pk_t, round(gmin, 3), round(gmax, 3), list(t.time[over]))
