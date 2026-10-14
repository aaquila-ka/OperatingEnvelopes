# style.py: shared colours, fonts and plot settings for every fig_*.py script.
# Reads no results file.
import matplotlib as mpl, matplotlib.pyplot as plt
from matplotlib import font_manager as fm
import os
# Optional hand-drawn font: xkcd-script from github.com/ipython/xkcd-font (CC BY-NC 3.0).
# Put xkcd-script.ttf in this folder to use it; otherwise the plots fall back to DejaVu Sans.
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xkcd-script.ttf")
if os.path.exists(FONT):
    fm.fontManager.addfont(FONT)
    NAME = fm.FontProperties(fname=FONT).get_name()
else:
    NAME = "DejaVu Sans"
BG = "#faf8f3"; INK = "#222222"; MUTED = "#6b6a66"; GRID = "#e4e1d8"
BLUE = "#2a78d6"; ORANGE = "#eb6834"; AQUA = "#1baf7a"; RED = "#d23b3a"; GREY = "#9a988f"
def setup():
    mpl.rcParams.update({
        "font.family": [NAME, "DejaVu Sans"], "font.size": 15, "axes.titlesize": 19, "axes.labelsize": 16,
        "xtick.labelsize": 14, "ytick.labelsize": 14, "legend.fontsize": 14,
        "figure.facecolor": BG, "axes.facecolor": BG, "savefig.facecolor": BG,
        "axes.edgecolor": INK, "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK,
        "text.color": INK, "axes.spines.top": False, "axes.spines.right": False,
        "axes.grid": True, "grid.color": GRID, "grid.linewidth": 1.0, "axes.axisbelow": True,
        "lines.linewidth": 3, "lines.solid_capstyle": "round", "axes.linewidth": 1.4,
    })
# palette: each colour keeps the same meaning across figures
TRUE_C = "#12898a"; WRONG_C = "#f0643c"; LIMIT_C = "#d62839"
LV3_C = "#7b4fbf"; LV9_C = "#2a9d8f"; BASIC_C = "#f4a259"; SAFER_C = "#3a6fd8"
