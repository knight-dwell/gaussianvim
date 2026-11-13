"""Reopen a plot from GaussianVim's run card as a real matplotlib window
(`z` in the card): zoom, pan and save with the toolbar.

Usage: gvview.py plot-001-00001.pickle "window title"
Exits with code 3 when it can't (no Tk, or the figure won't unpickle); gv then
opens the PNG in the image viewer instead.
"""
import pickle
import sys

try:
    import matplotlib
    matplotlib.use("TkAgg")
    import matplotlib.pyplot as plt
    with open(sys.argv[1], "rb") as f:
        fig = pickle.load(f)          # comes back as a pyplot figure (it was one when saved)
    if fig.canvas.manager is None:
        raise RuntimeError("figure has no window")
except Exception as err:
    print(f"gvview: {err}", file=sys.stderr)
    sys.exit(3)

fig.canvas.manager.set_window_title(sys.argv[2] if len(sys.argv) > 2 else "GvPlot")
plt.show()
