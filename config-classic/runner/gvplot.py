"""matplotlib backend used by GaussianVim's run card (F5).

Works like Spyder's Plots pane: plt.show() opens no window. Each figure is saved
as a PNG in $GV_PLOT_DIR, and gv draws it inside the run card (lua/gv/run.lua),
so nothing pops up and the plot keeps its shape. A pickled copy is saved next to
the PNG, so `z` in the card can reopen the figure as a real window with
matplotlib's zoom / pan / save toolbar (runner/gvview.py).

  plt.show()    saves every open figure, then starts fresh figures (like Jupyter)
  plt.pause()   saves the figure again (at most twice a second), so a live
                animation updates in the card
  at the end    figures the script made but never showed are saved too

Selected with MPLBACKEND=module://gvplot (gv sets it and puts this folder on
PYTHONPATH, only for scripts started with F5). Without GV_PLOT_DIR (backend
chosen by hand) the PNGs go next to the script instead.
"""
import atexit
import itertools
import glob
import os
import pickle
import sys
import time
import weakref

from matplotlib._pylab_helpers import Gcf
from matplotlib.backend_bases import FigureManagerBase
from matplotlib.backends.backend_agg import FigureCanvasAgg

PLOT_DIR = os.environ.get("GV_PLOT_DIR")
DPI = 150
_numbers = itertools.count(1)        # plot number in the card, one per figure
_versions = itertools.count(1)       # every save gets a new file name (gv caches images by name)
_number = weakref.WeakKeyDictionary()
_saved_at = weakref.WeakKeyDictionary()


def _save(fig, force=True):
    """Save one figure where gv looks for it: plot-<number>-<version>.png (+ .pickle)."""
    now = time.monotonic()
    if not force and now - _saved_at.get(fig, 0) < 0.5:
        return
    _saved_at[fig] = now
    if not PLOT_DIR:
        base = os.path.splitext(os.path.basename(sys.argv[0] or "plot"))[0]
        path = os.path.abspath(f"{base}_figure{fig.number}.png")
        fig.savefig(path, dpi=DPI)
        print(f"[gv] figure {fig.number} saved to {path}")
        return
    os.makedirs(PLOT_DIR, exist_ok=True)
    first = fig not in _number
    if first:
        _number[fig] = next(_numbers)
    stem = os.path.join(PLOT_DIR, f"plot-{_number[fig]:03d}")
    new = f"{stem}-{next(_versions):05d}"
    try:                             # for `z` (real window); some figures can't be pickled
        with open(new + ".pickle", "wb") as f:
            pickle.dump(fig, f)
    except Exception:
        pass
    fig.savefig(new + ".tmp.png", dpi=DPI)
    os.replace(new + ".tmp.png", new + ".png")      # gv only ever sees finished PNGs
    for old in glob.glob(stem + "-*"):               # older versions of this plot
        if not old.startswith(new):
            try:
                os.remove(old)
            except OSError:
                pass
    if first:
        print(f"[gv] plot {_number[fig]} is in the run card")


class FigureManager(FigureManagerBase):
    def show(self):
        _save(self.canvas.figure)

    @classmethod
    def pyplot_show(cls, *, block=None):
        managers = Gcf.get_all_fig_managers()
        for manager in managers:
            _save(manager.canvas.figure, force=block is not False)
        if block is not False:           # plt.show(): done with these figures
            Gcf.destroy_all()


class FigureCanvas(FigureCanvasAgg):
    manager_class = FigureManager


@atexit.register
def _unshown():
    for manager in Gcf.get_all_fig_managers():
        _save(manager.canvas.figure)
