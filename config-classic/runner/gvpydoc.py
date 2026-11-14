"""Offline docs for installed Python packages (SciPy and friends), for gv's
docs search (lua/gv/docs.lua).

  gvpydoc.py index scipy [more ...]    JSON list of modules, functions, classes (+ summaries)
  gvpydoc.py md scipy.integrate.quad   the page as Markdown: signature in a code block,
                                       Parameters / Returns / Examples ..., maths as $...$
  gvpydoc.py show NAME                 plain help() text
"""
import importlib
import inspect
import json
import pkgutil
import pydoc
import re
import sys
import warnings

warnings.simplefilter("ignore")


def summary(obj):
    doc = inspect.getdoc(obj) or ""
    for line in doc.splitlines():
        line = line.strip()
        if line and not re.match(r"^[=\-~*#^]+$", line) and not line.startswith(("..", ">>>")) \
                and not re.match(r"^[\w.]+\(.*\)$", line):
            return re.sub(r":\w+:`~?([^`]+)`", r"\1", line)[:120]
    return ""


def index(pkgs):
    out, seen = [], set()
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
            out.append({"name": mod.__name__, "type": "module", "summary": summary(mod)})
            for attr in getattr(mod, "__all__", None) or dir(mod):
                if attr.startswith("_"):
                    continue
                obj = getattr(mod, attr, None)
                if inspect.ismodule(obj):
                    continue
                if not (inspect.isfunction(obj) or inspect.isclass(obj) or inspect.isbuiltin(obj)
                        or type(obj).__name__ in ("ufunc", "_lazywhere")):
                    continue
                full = mod.__name__ + "." + attr
                if full in seen:
                    continue
                seen.add(full)
                out.append({"name": full, "type": "class" if inspect.isclass(obj) else "function",
                            "summary": summary(obj)})
    print(json.dumps(out))


SECTIONS_LISTS = {"Parameters", "Returns", "Yields", "Raises", "Other Parameters", "Attributes",
                  "Warns", "Receives", "Methods"}


def rst_inline(s):
    s = re.sub(r":math:`([^`]+)`", r"$\1$", s)
    s = re.sub(r":(?:func|meth|class|mod|obj|attr|data|ref|py:\w+):`~?([^`]+)`", r"`\1`", s)
    s = re.sub(r"``([^`]+)``", r"`\1`", s)
    return s


def numpydoc_to_md(doc):
    lines = doc.splitlines()
    out, section, i = [], None, 0
    code, output = [], []

    def flush_code():
        nonlocal code, output
        if code:
            out.extend(["```python", *code, "```"])
        if output:
            out.extend(["```text", *output, "```"])
        if code or output:
            out.append("")
        code, output = [], []

    while i < len(lines):
        line = lines[i]
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        # a numpydoc section header: "Parameters" underlined by -----
        if line.strip() and re.match(r"^\s*-{3,}\s*$", nxt):
            flush_code()
            section = line.strip()
            out.extend(["", "## " + section, ""])
            i += 2
            continue
        # .. math:: blocks
        if line.strip().startswith(".. math::"):
            flush_code()
            body, i = [line.strip()[len(".. math::"):].strip()], i + 1
            while i < len(lines) and (not lines[i].strip() or lines[i].startswith((" ", "\t"))):
                if lines[i].strip():
                    body.append(lines[i].strip())
                i += 1
            formula = " ".join(b for b in body if b)
            if formula:
                out.extend(["", "$$" + formula + "$$", ""])
            continue
        stripped = line.strip()
        if stripped.startswith((">>> ", "... ")) or stripped in (">>>", "..."):
            if output:
                flush_code()
            code.append(stripped[4:] if len(stripped) > 3 else "")
            i += 1
            continue
        if code and stripped:            # output printed by the example above
            output.append(stripped)
            i += 1
            continue
        flush_code()
        if section in SECTIONS_LISTS and stripped and not line.startswith((" ", "\t")):
            name, _, typ = stripped.partition(" : ")
            out.append(f"- **{name.strip()}**" + (f" : *{typ.strip()}*" if typ else ""))
        elif section in SECTIONS_LISTS and stripped:
            out.append("  " + rst_inline(stripped))
        elif section == "See Also" and stripped and not line.startswith((" ", "\t")):
            name, _, rest = stripped.partition(" : ")
            out.append(f"- `{name.strip()}`" + (f" : {rst_inline(rest)}" if rest else ""))
        else:
            out.append(rst_inline(line))
        i += 1
    flush_code()
    return out


def md(name):
    obj = pydoc.locate(name)
    if obj is None:
        print(f"# {name}\n\nNot found (is the package installed for this Python?).")
        return
    kind = "module" if inspect.ismodule(obj) else "class" if inspect.isclass(obj) else "function"
    out = [f"# {name}", "", f"*{kind}*", ""]
    if kind != "module":
        try:
            sig = str(inspect.signature(obj))
            out += ["```python", f"{name.split('.')[-1]}{sig}", "```", ""]
        except (TypeError, ValueError):
            pass
    out += numpydoc_to_md(inspect.getdoc(obj) or "(no docstring)")
    if kind == "class":
        methods = [(n, m) for n, m in inspect.getmembers(obj) if not n.startswith("_") and callable(m)]
        if methods:
            out += ["", "## Methods", ""]
            out += [f"- `{n}` : {summary(m)}" for n, m in methods]
    print("\n".join(out))


def show(name):
    try:
        print(pydoc.render_doc(name, renderer=pydoc.plaintext))
    except Exception as err:
        print(f"No documentation for {name}: {err}")


if __name__ == "__main__":
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 2 else (None, [])
    if cmd == "index":
        index(args)
    elif cmd == "md":
        md(args[0])
    elif cmd == "show":
        show(args[0])
    else:
        print(__doc__)
