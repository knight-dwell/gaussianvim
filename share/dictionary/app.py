#!/usr/bin/env python3
"""GaussianVim Dictionary: every GaussianVim / GaussianTeX key, command and
LaTeX alias in one searchable window. Search by what you want to do
("make a fraction", "stop the program", "delete a line"); click or Enter copies.

    gv-dict              open (or bring to the front)
    gv-dict fraction     open with a search already typed
    gv-dict --json       print the entries (for testing)

Super+? anywhere, Space ? inside gv, or "GaussianVim Dictionary" in the app menu.
Built fresh every time it opens, so it never goes stale, from:
    ~/.config/gaussianvim/cheatsheet.tsv      keys and commands (4th column: search words)
    ~/.config/gaussianvim/snippets/tex.json   LaTeX aliases (Tab, Enter)
    ~/.config/gaussianvim/tex-auto.json       instant maths aliases
Colours follow the rice theme (~/.config/theme/generated/palette.json).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
CONF = os.path.expanduser("~/.config/gaussianvim")
PALETTE = os.path.expanduser("~/.config/theme/generated/palette.json")

# category id -> (name shown, group)
CATS = [
    ("modes", "Modes", "GaussianVim"), ("move", "Moving around", "GaussianVim"),
    ("delete", "Deleting", "GaussianVim"), ("change", "Changing text", "GaussianVim"),
    ("copy", "Copy and paste", "GaussianVim"), ("undo", "Undo", "GaussianVim"),
    ("search", "Searching", "GaussianVim"), ("replace", "Find and replace", "GaussianVim"),
    ("select", "Selecting", "GaussianVim"), ("files", "Files", "GaussianVim"),
    ("buffers", "Open files (tabs)", "GaussianVim"), ("windows", "Splits", "GaussianVim"),
    ("code", "Code and errors", "GaussianVim"), ("git", "Git", "GaussianVim"),
    ("run", "Run card (F5)", "GaussianVim"), ("terminal", "Terminal", "GaussianVim"),
    ("debug", "Debugger", "GaussianVim"), ("marks", "Marks", "GaussianVim"),
    ("macros", "Macros", "GaussianVim"), ("folds", "Folds", "GaussianVim"),
    ("look", "Look", "GaussianVim"), ("misc", "Misc", "GaussianVim"),
    ("docs", "Docs and Stack Exchange", "GaussianVim"), ("ai", "Claude (AI)", "GaussianVim"),
    ("latex", "LaTeX editor", "GaussianTeX"), ("aliases", "LaTeX aliases (Tab, Enter)", "GaussianTeX"),
    ("instant", "Instant maths aliases (just type)", "GaussianTeX"),
]
CAT_INFO = {c: (n, g) for c, n, g in CATS}


def unescape(body, placeholder):
    """Snippet syntax -> plain LaTeX: ${1:a} -> a, $1 -> placeholder, \\\\ -> \\."""
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body) and body[i + 1] in "\\$}":
            out.append(body[i + 1]); i += 2; continue
        if c == "$":
            m = re.match(r"\$\{(\d+):([^}]*)\}", body[i:])
            if m:
                out.append(m.group(2)); i += m.end(); continue
            m = re.match(r"\$(\d+)|\$\{(\d+)\}", body[i:])      # $1 or ${1} (never eats a LaTeX })
            if m:
                n = m.group(1) or m.group(2)
                out.append("" if n == "0" else placeholder); i += m.end(); continue
        out.append(c); i += 1
    return "".join(out).replace("\t", "  ")


NO_PREVIEW = re.compile(r"\\(begin\{(figure|table|tabular|itemize|enumerate|equation)|(sub)*section)")


def math_preview(code):
    """KaTeX source for a preview, or None (whole-document blocks show as code)."""
    if NO_PREVIEW.search(code) or code.strip().startswith("$") or code.strip().startswith("\\["):
        return None
    return code.replace("\\begin{align}", "\\begin{aligned}").replace("\\end{align}", "\\end{aligned}")


def entries():
    out = []

    def add(**e):
        name, group = CAT_INFO.get(e["cat"], (e["cat"].title(), "GaussianVim"))
        e.setdefault("title", "")
        e.setdefault("words", "")
        e.update(id=len(out), catName=name, group=group)
        out.append(e)

    try:
        with open(os.path.join(CONF, "cheatsheet.tsv"), encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                add(cat=parts[0], keys=parts[1], desc=parts[2], words=parts[3] if len(parts) > 3 else "",
                    copy=parts[1])
    except OSError:
        pass

    try:
        with open(os.path.join(CONF, "snippets", "tex.json"), encoding="utf-8") as f:
            snippets = json.load(f)
    except (OSError, ValueError):
        snippets = {}
    for name, sn in snippets.items():
        body = "\n".join(sn["body"]) if isinstance(sn["body"], list) else sn["body"]
        prefixes = sn["prefix"] if isinstance(sn["prefix"], list) else [sn["prefix"]]
        code = unescape(body, "").rstrip()
        add(cat="aliases", keys="  /  ".join(prefixes), title=name, desc=sn.get("description", ""),
            words=sn.get("keywords", ""), code=code, math=math_preview(unescape(body, r"\square").rstrip()),
            copy=code)

    try:
        with open(os.path.join(CONF, "tex-auto.json"), encoding="utf-8") as f:
            auto = json.load(f)
    except (OSError, ValueError):
        auto = {}
    for trig, a in auto.items():
        code = unescape(a["body"], "")
        add(cat="instant", keys=trig, title="", desc=a.get("description", ""), words=a.get("keywords", ""),
            code=code, math=math_preview(unescape(a["body"], r"\square")), copy=code)
    return out


def theme():
    try:
        with open(PALETTE, encoding="utf-8") as f:
            p = json.load(f)
    except (OSError, ValueError):
        p = {}
    keys = ["primary", "on_primary", "primary_container", "on_primary_container", "secondary",
            "secondary_container", "on_secondary_container", "tertiary", "tertiary_container",
            "on_tertiary_container", "surface", "surface_container", "surface_container_high",
            "surface_container_highest", "surface_container_low", "on_surface", "on_surface_variant",
            "outline", "outline_variant", "error"]
    return {k: p[k] for k in keys if k in p}


def payload():
    return {"entries": entries(), "theme": theme(), "cats": [{"id": c, "name": n, "group": g} for c, n, g in CATS]}


# ── the window ────────────────────────────────────────────────────────────────

def main():
    if "--json" in sys.argv:
        print(json.dumps(payload(), ensure_ascii=False, indent=1))
        return

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("WebKit2", "4.1")
    from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2

    class DictWindow(Gtk.ApplicationWindow):
        def __init__(self, app, query):
            super().__init__(application=app, title="GaussianVim Dictionary")
            self.set_wmclass("gaussianvim-dictionary", "GvDictionary")
            self.set_default_size(1080, 760)
            icon = os.path.join(HERE, "web", "icon.svg")
            if os.path.exists(icon):
                self.set_icon_from_file(icon)
            cache = os.path.join(GLib.get_user_cache_dir(), "gaussianvim-dictionary")
            data = WebKit2.WebsiteDataManager(base_data_directory=os.path.join(cache, "data"),
                                              base_cache_directory=os.path.join(cache, "cache"))
            ctx = WebKit2.WebContext.new_with_website_data_manager(data)
            manager = WebKit2.UserContentManager()
            manager.register_script_message_handler("gvdict")
            manager.connect("script-message-received::gvdict", self.on_message)
            init = payload()
            init["query"] = query
            manager.add_script(WebKit2.UserScript(
                "window.GV = " + json.dumps(init, ensure_ascii=False) + ";",
                WebKit2.UserContentInjectedFrames.TOP_FRAME, WebKit2.UserScriptInjectionTime.START, None, None))
            self.view = WebKit2.WebView(web_context=ctx, user_content_manager=manager)
            self.view.get_settings().set_enable_developer_extras(bool(os.environ.get("GVDICT_DEBUG")))
            bg = Gdk.RGBA()
            bg.parse(init["theme"].get("surface", "#111318"))
            self.view.set_background_color(bg)
            self.add(self.view)
            self.view.load_uri("file://" + os.path.join(HERE, "web", "index.html"))

        def on_message(self, _m, result):
            try:
                msg = json.loads(result.get_js_value().to_string())
            except Exception:
                return
            if "copy" in msg:
                cb = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
                cb.set_text(msg["copy"], -1)
                cb.store()
            if msg.get("close"):
                self.close()

        def set_query(self, q):
            self.view.run_javascript("window.gvSetQuery && gvSetQuery(%s)" % json.dumps(q), None, None, None)

    class App(Gtk.Application):
        def __init__(self):
            super().__init__(application_id="org.gaussianvim.Dictionary",
                             flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
            self.win = None

        def do_command_line(self, cmdline):
            args = [a for a in cmdline.get_arguments()[1:] if not a.startswith("--")]
            q = " ".join(args)
            if self.win is None:
                self.win = DictWindow(self, q)
                self.win.connect("destroy", lambda *_: setattr(self, "win", None))
                self.win.show_all()
            else:
                if q:
                    self.win.set_query(q)
                self.win.present()
            return 0

    App().run(sys.argv)


if __name__ == "__main__":
    main()
