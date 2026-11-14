"""Zoom for GaussianVim's run card: draws the part of a plot or image that is
in view, at the zoom asked for, as a PNG exactly the size of the panel.

Runs while the card is zooming (gv starts it, and stops it when the card hides
or a new run starts). gv sends one JSON request per line on stdin and gets one
JSON answer per line on stdout:

  {"id": 7, "png": ".../plot-001-00003.png", "pickle": ".../plot-001-00003.pickle" or null,
   "z": 2.0, "cx": 0.5, "cy": 0.5, "vw": 820, "vh": 560, "out": ".../zoom-7.png"}
  -> {"id": 7, "out": ".../zoom-7.png", "w": 820, "h": 560, "cx": 0.5, "cy": 0.5}
  -> {"id": 7, "error": "..."}

z = 1 is the whole picture fitted into the vw x vh pixel panel; z = 2 is twice
that. (cx, cy) is the point of the picture (0..1 across, 0..1 down) that sits
in the middle of the panel; the answer gives it back, moved so the view never
goes past the picture's edges.

Plots with a pickled figure (runner/gvplot.py saves one) are drawn again by
matplotlib at the new size, only the visible part, so lines and text stay
sharp at any zoom. Other pictures (and figures that can't be unpickled) are
cut out of the PNG and scaled up.
"""
import io
import json
import os
import pickle
import sys

_fig = {}          # pickle path -> figure (only the last one is kept)


def _figure(path):
    if path not in _fig:
        _fig.clear()
        import matplotlib
        matplotlib.use("Agg")
        with open(path, "rb") as f:
            _fig[path] = pickle.load(f)
    return _fig[path]


def _view(r, iw, ih):
    """Visible window of the zoomed picture: (zoomed size, crop box, centre)."""
    s = min(r["vw"] / iw, r["vh"] / ih) * r["z"]
    zw, zh = iw * s, ih * s
    ow, oh = min(r["vw"], zw), min(r["vh"], zh)
    cx = min(max(r["cx"], ow / zw / 2), 1 - ow / zw / 2)
    cy = min(max(r["cy"], oh / zh / 2), 1 - oh / zh / 2)
    left, top = cx * zw - ow / 2, cy * zh - oh / 2
    return zw, zh, (left, top, left + ow, top + oh), cx, cy


def _save(img, out):
    tmp = out + ".tmp.png"
    # a low dpi tag: gv (Snacks.image) then scales the picture to exactly the
    # box it's given instead of guessing its size from the dpi
    img.save(tmp, dpi=(30, 30))
    os.replace(tmp, out)
    return img.size


def _from_figure(r):
    from matplotlib.transforms import Bbox
    from PIL import Image
    fig = _figure(r["pickle"])
    with Image.open(r["png"]) as im:
        iw, ih = im.size
    zw, zh, (l, t, rr, b), cx, cy = _view(r, iw, ih)
    fw, fh = fig.get_size_inches()
    dpi = zw / fw
    # the visible part, in inches from the bottom left (matplotlib's way)
    box = Bbox.from_extents(l / dpi, fh - b / dpi, rr / dpi, fh - t / dpi)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, bbox_inches=box, pad_inches=0,
                facecolor=fig.get_facecolor())
    buf.seek(0)
    img = Image.open(buf)
    img.load()
    want = (max(1, round(rr - l)), max(1, round(b - t)))
    if img.size != want:              # off by a pixel from rounding
        img = img.resize(want, Image.LANCZOS)
    return img, cx, cy


def _from_png(r):
    from PIL import Image
    with Image.open(r["png"]) as im:
        im.load()
        src = im.convert("RGBA") if im.mode not in ("RGB", "RGBA") else im.copy()
    iw, ih = src.size
    zw, zh, (l, t, rr, b), cx, cy = _view(r, iw, ih)
    k = iw / zw                       # picture pixels per zoomed pixel
    crop = src.crop((round(l * k), round(t * k), round(rr * k), round(b * k)))
    want = (max(1, round(rr - l)), max(1, round(b - t)))
    return crop.resize(want, Image.LANCZOS if k > 0.5 else Image.NEAREST), cx, cy


def handle(r):
    img = None
    if r.get("pickle") and os.path.exists(r["pickle"]):
        try:
            img, cx, cy = _from_figure(r)
        except Exception:
            img = None                # fall back to the PNG
    if img is None:
        img, cx, cy = _from_png(r)
    w, h = _save(img, r["out"])
    return {"id": r["id"], "out": r["out"], "w": w, "h": h, "cx": cx, "cy": cy}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        try:
            ans = handle(r)
        except Exception as err:      # e.g. a PDF: PIL can't read it
            ans = {"id": r.get("id"), "error": f"{type(err).__name__}: {err}"}
        sys.stdout.write(json.dumps(ans) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
