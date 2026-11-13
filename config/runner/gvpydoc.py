"""Offline docs for installed Python packages (SciPy and friends), for gv's
docs search (lua/gv/docs.lua): the same text as help() in Python.

  gvpydoc.py index scipy [more ...]   JSON list of public functions / classes
  gvpydoc.py show scipy.integrate.quad
"""
import importlib
import inspect
import json
import pkgutil
import pydoc
import sys
import warnings


def index(pkgs):
    out, seen = [], set()
    warnings.simplefilter("ignore")
    for name in pkgs:
        try:
            pkg = importlib.import_module(name)
        except Exception:
            continue
        mods = [pkg]
        for info in pkgutil.walk_packages(getattr(pkg, "__path__", []), name + "."):
            parts = info.name.split(".")
            if any(p.startswith("_") or p in ("tests", "test", "conftest", "setup") for p in parts[1:]):
                continue
            try:
                mods.append(importlib.import_module(info.name))
            except Exception:
                continue
        for mod in mods:
            out.append({"name": mod.__name__, "type": "module"})
            for attr in getattr(mod, "__all__", None) or dir(mod):
                if attr.startswith("_"):
                    continue
                obj = getattr(mod, attr, None)
                if not (inspect.isfunction(obj) or inspect.isclass(obj) or inspect.isbuiltin(obj)
                        or type(obj).__name__ in ("ufunc", "_lazywhere")):
                    continue
                full = mod.__name__ + "." + attr
                if full in seen:
                    continue
                seen.add(full)
                out.append({"name": full, "type": mod.__name__})
    print(json.dumps(out))


def show(name):
    warnings.simplefilter("ignore")
    try:
        print(pydoc.render_doc(name, renderer=pydoc.plaintext))
    except Exception as err:
        print(f"No documentation for {name}: {err}")


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "index":
        index(sys.argv[2:])
    elif len(sys.argv) > 2 and sys.argv[1] == "show":
        show(sys.argv[2])
    else:
        print(__doc__)
