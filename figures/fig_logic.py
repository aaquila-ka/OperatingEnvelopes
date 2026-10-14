# fig_logic.py: draws fig_logic.png, a block diagram of one example, step by step.
# Drawing only: it reads no results file.
# Run from this folder: python fig_logic.py
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from style import *
setup()
fig = plt.figure(figsize=(14, 8.2)); ax = fig.add_axes([0, 0, 1, 1]); ax.axis("off")
ax.set_xlim(0, 100); ax.set_ylim(0, 100)
ax.text(2, 98.6, "The logic of one example, step by step", fontsize=23, va="top")
ax.text(2, 93.4, "The same steps are repeated for every street, day, time, supply voltage and kind of record error",
        fontsize=13.5, color=MUTED, va="top")
def box(x, y, w, h, col, title, body="", tsize=14, bsize=11.5, alpha=0.14):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.35,rounding_size=1.2", fc=col, alpha=alpha,
                                ec=col, lw=2))
    ax.text(x + w / 2, y + h - 1.4, title, ha="center", va="top", fontsize=tsize, color=col)
    if body:
        ax.text(x + w / 2, y + h - 5.6, body, ha="center", va="top", fontsize=bsize, color=INK, linespacing=1.25)
def arrow(x0, y0, x1, y1, col=INK, rad=0.0):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>", mutation_scale=18, lw=2, color=col,
                                 connectionstyle=f"arc3,rad={rad}"))
# inputs column
ax.text(2, 87.5, "1  inputs", fontsize=14, color=MUTED)
ins = [("street model", "CSIRO: 12 and 123 homes"), ("home electricity use", "1 kW each, or a real day"),
       ("supply voltage", "0.94 to 1.035 x 230 V"), ("cable records", "every service cable 16 mm²")]
for k, (t, b) in enumerate(ins):
    box(2, 74 - k * 13, 18, 10.5, LV9_C, t, b, tsize=13, bsize=11)
# rows
ax.text(25, 87.5, "2  two versions of the street", fontsize=14, color=MUTED)
ax.text(49, 87.5, "3  calculator on each", fontsize=14, color=MUTED)
box(25, 64, 19, 18, WRONG_C, "RECORDED street", "all service cables\n16 mm² (what the\ncompany believes)")
box(25, 35, 19, 20, TRUE_C, "TRUE street", "some cables changed:\nscatter, or wrong\ntype (4 mm²)")
box(49, 66, 13, 14, GREY, "calculator", "optimal\npower flow", tsize=13)
box(49, 38, 13, 14, GREY, "calculator", "optimal\npower flow", tsize=13)
box(66, 64, 15, 18, WRONG_C, "limit from\nrecords", "\n\nwhat the company\nwould send")
box(66, 35, 15, 20, TRUE_C, "correct\nlimit", "\n\nthe answer key")
arrow(20.6, 60, 24.6, 72); arrow(20.6, 54, 24.6, 45)
arrow(44.6, 73, 48.6, 73, WRONG_C); arrow(62.6, 73, 65.6, 73, WRONG_C)
arrow(44.6, 45, 48.6, 45, TRUE_C); arrow(62.6, 45, 65.6, 45, TRUE_C)
box(85, 60, 13, 22, LIMIT_C, "4  test", "put the limit\nfrom records\non the TRUE\nstreet ->\nvoltages", tsize=14, bsize=11)
box(85, 30, 13, 24, INK, "5  dataset\nrow", "\n\ninputs, both\nlimits, gap,\nhighest voltage,\nhomes > 253 V", tsize=14, bsize=11, alpha=0.08)
arrow(81.6, 73, 84.6, 73, WRONG_C); arrow(91.5, 59.4, 91.5, 54.6, LIMIT_C); arrow(81.6, 45, 84.6, 43, TRUE_C)
# rule box
ax.add_patch(FancyBboxPatch((2, 4.6), 96, 18.4, boxstyle="round,pad=0.35,rounding_size=1.2", fc=BG, ec=MUTED, lw=1.5, ls="--"))
ax.text(4, 21.2, "the calculator's rule", fontsize=14, color=MUTED, va="top")
ax.text(4, 16.3, "find the biggest export x allowed for every home, so that\n"
        "  - every home's voltage stays between 207 V and 253 V\n"
        "  - each inverter follows its Volt-VAr / Volt-Watt rules and its 5 kVA size",
        fontsize=12, va="top", linespacing=1.3)
ax.text(52, 21.2, "why the cable matters", fontsize=14, color=MUTED, va="top")
ax.text(52, 16.3, "voltage rise ≈ (R x P + X x Q) / V\n"
        "thinner cable -> bigger R -> bigger rise -> smaller safe x\n"
        "gap = limit from records - correct limit", fontsize=12, va="top", linespacing=1.3)
ax.text(2, 0.6, "Calculator = Fred Geth's BMOPFTools / PowerOptLab (four-wire, neutral included), checked against OpenDSS. "
        "R, X = cable resistance and reactance; P, Q = exported power; V = voltage.", fontsize=10.5, color=MUTED)
fig.savefig("fig_logic.png", dpi=200); print("ok")
