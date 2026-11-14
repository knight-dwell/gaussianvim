"""GaussianTeX's figure cache: print-resolution copies of oversized pictures, so
pdflatex does not spend most of every compile re-encoding 50-megapixel PNGs.

  gvfastfig.py PROJECT_DIR [MAX_PIXELS_ON_LONG_SIDE=4000]

For every PNG / JPEG in the project whose long side is above the limit, a copy
scaled down to the limit (transparency kept, 8-bit) is written to
PROJECT_DIR/.gvfast/<same relative path>; it is redone when the original
changes. Your files are never touched. gv compiles with TEXINPUTS=.gvfast:
so LaTeX finds these copies first; the "full quality" build skips the cache.
4000 px across a page is about 600 dpi in print, beyond what printers resolve.
Prints how many copies were made / reused.
"""
import os
import sys

from PIL import Image

Image.MAX_IMAGE_PIXELS = None          # thesis figures can be 100+ megapixels

SKIP = {".gvfast", ".git", "__pycache__", "node_modules"}


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
    cache = os.path.join(root, ".gvfast")
    os.makedirs(cache, exist_ok=True)   # always: gv checks for it to know the cache is ready
    made = reused = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for name in filenames:
            if not name.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, root)
            dst = os.path.join(cache, rel)
            if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
                reused += 1
                continue
            try:
                with Image.open(src) as im:
                    if max(im.size) <= limit:
                        continue
                    im.load()
                    scale = limit / max(im.size)
                    small = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
                    if small.mode not in ("RGB", "RGBA", "L", "LA", "P"):
                        small = small.convert("RGBA")
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    tmp = dst + ".tmp" + os.path.splitext(dst)[1]
                    if name.lower().endswith(".png"):
                        small.save(tmp, compress_level=1)
                    else:
                        small.convert("RGB").save(tmp, quality=92)
                    os.replace(tmp, dst)
                    made += 1
            except Exception as err:          # unreadable picture: LaTeX will use the original
                print(f"skip {rel}: {err}", file=sys.stderr)
    print(f"{made} made, {reused} reused")


if __name__ == "__main__":
    main()
