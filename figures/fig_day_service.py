# New Fig. 2 (Oct 2026): the measured day with the critical home's service really overhead 16 mm2 ABC.
# Every number is read from ../results. Run from the figures folder:  python fig_day_service.py
import matplotlib.pyplot as plt, pandas as pd, numpy as np
from style import *
setup()
t = pd.read_csv("../results/doe_timeseries_type_l3432.csv")
h = (t.step - 1) * 0.5                                   # hour of day at the start of each half-hour
sun = 5.0 * t.pv_shape
over = t.A_pv_n_over_253 > 0
n_over = int(over.sum())
pk = t.A_pv_V_VW.max(); ipk = t.A_pv_V_VW.idxmax(); pk_t = t.loc[ipk, "time"]
hi_rows = t[t.A_overpromise_pct > 30]                   # half-hours where the critical home sets the limit
n_hi, lo_p, hi_p = len(hi_rows), hi_rows.A_overpromise_pct.min(), hi_rows.A_overpromise_pct.max()

fig, (a1, a2) = plt.subplots(2, 1, figsize=(13, 9.2), sharex=True, gridspec_kw={"hspace": 0.34})
fig.suptitle("Over the measured day: one home's service cable sets the limit for the whole street",
             fontsize=21, x=0.03, ha="left", y=0.99)
fig.text(0.03, 0.918, "12-home four-wire street (CSIRO LV3), supply 1.03 pu, measured home use on one day, basic DOE, "
         "equal sharing.\nRecords: home b828's 29.5 m service is underground 16 mm² Cu. True street: it is overhead "
         "16 mm² ABC (1.59 x R).", fontsize=13, color=MUTED)
hh = np.append(h, 24.0); ext = lambda v: np.append(np.asarray(v), np.asarray(v)[-1])
a1.fill_between(hh, 0, ext(sun), step="post", color="#f6c945", alpha=0.35, lw=0, label="sun available per home")
a1.step(hh, ext(t.clean_kW), where="post", color=WRONG_C, lw=3, label="DOE from the records")
a1.step(hh, ext(t.A_correct_kW), where="post", color=TRUE_C, lw=3, label="DOE for the true street")
a1.set_ylabel("export limit\n(kW per home)"); a1.set_ylim(0, 5.8)
a1.legend(loc="upper left", frameon=False, ncol=3, fontsize=13)
a1.text(21.3, 1.2, f"{n_hi} of 48 half-hours:\nrecords {lo_p:.0f}–{hi_p:.0f} % too high", fontsize=13.5, ha="center", color=INK)
a1.set_title("the export limit each home is given", loc="left", fontsize=15, color=MUTED)
a1.grid(axis="x", visible=False)

idx = list(np.where(over)[0]); runs = []
for i in idx:
    if runs and i == runs[-1][1] + 1: runs[-1][1] = i
    else: runs.append([i, i])
for a, b in runs:
    a2.axvspan(h[a], h[b] + 0.5, color=LIMIT_C, alpha=0.14, lw=0)
a2.axhline(253, color=LIMIT_C, lw=2.2, ls="--")
a2.text(23.7, 253.05, "limit 253 V", ha="right", color=LIMIT_C, fontsize=14, va="bottom")
day = t.A_pv_V_VW.notna()
a2.plot(h[day] + 0.25, t.A_pv_V_VW[day], color=WRONG_C, lw=3, marker="o", ms=5,
        label="highest home voltage, true street, DOE from the records")
a2.set_ylim(250.8, 254.0)
a2.set_ylabel("highest home\nvoltage (V)")
a2.set_title("on the true street, each home exports what the sun gives, up to the DOE from the records "
             "(Volt-VAr and Volt-Watt on)", loc="left", fontsize=13.5, color=MUTED)
a2.annotate(f"peak {pk:.2f} V at {pk_t}", xy=(h[ipk] + 0.25, pk), xytext=(15.5, 253.75),
            fontsize=13.5, arrowprops=dict(arrowstyle="->", color=INK, lw=1.6), va="center")
a2.text(4.5, 252.0, f"{n_over} half-hours above 253 V\n(shaded)", fontsize=13.5, ha="center", color=LIMIT_C)
a2.legend(loc="upper left", frameon=False, fontsize=12.5)
a2.set_xticks(range(0, 25, 3), [f"{x:02d}:00" for x in range(0, 25, 3)])
a2.set_xlim(0, 24); a2.set_xlabel("time of day")
a2.grid(axis="x", visible=False)
fig.text(0.03, 0.008, "The over-promise is large all day, but on this day the sun limits what homes can export, so it shows as\n"
         "a breach only when the sun is strong. Voltage shown only while the sun is up. Data: results/doe_timeseries_type_l3432.csv",
         fontsize=10.5, color=MUTED)
fig.subplots_adjust(top=0.84, bottom=0.11, left=0.11, right=0.98)
fig.savefig("fig_day_service.png", dpi=200)
print(n_over, round(pk, 2), pk_t, n_hi, round(lo_p, 1), round(hi_p, 1), list(t.time[over]))
