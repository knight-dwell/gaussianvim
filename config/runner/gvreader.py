"""GaussianVim's reader: Wikipedia articles and Stack Exchange posts with the
equations typeset and the figures shown (a WebKit window, Material colors).
gv opens it for Space s w / Space s x (and `p` in the text reader), because a
terminal without kitty graphics (the GaussianTeX / GaussianVim window, gnome-terminal)
can't draw maths or pictures itself.

  gvreader.py wiki TITLE                 online Wikipedia (figures + maths)
  gvreader.py zim FILE.zim PATH          offline Wikipedia (Kiwix); maths as MathML
  gvreader.py html FILE.html TITLE BASE  a page gv wrote (Stack Exchange); $...$ by MathJax

One window: a second call shows the new page in the window already open.
Keys: Alt+Left / Backspace back, Alt+Right forward, Ctrl +/-/0 zoom, o open in
the browser, Esc / q close.
"""
import json
import os
import sys
import threading
import urllib.parse
import urllib.request

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
try:
    gi.require_version("WebKit2", "4.1")
except ValueError:
    gi.require_version("WebKit2", "4.0")      # older distributions (Debian 11, Ubuntu 20.04)
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gvtheme import mix, palette  # noqa: E402

P = palette()
UA = "GaussianVim/1.0 (offline physics editor)"
API = "https://en.wikipedia.org/w/api.php"

PAGE_CSS = """
:root {{ color-scheme: dark; }}
html, body {{ background: {bg} !important; color: {fg} !important; }}
body {{ font: 17px/1.65 "Inter", "Noto Sans", "Cantarell", sans-serif; max-width: 920px;
        margin: 0 auto !important; padding: 28px 36px 80px !important; }}
#gvtitle {{ font-size: 30px; font-weight: 800; color: {fg}; margin: 0 0 4px; border: 0; }}
#gvsource {{ display: inline-block; background: {primary_container}; color: {on_primary_container};
             border-radius: 999px; padding: 2px 12px; font-size: 13px; font-weight: 700; margin-bottom: 18px; }}
h1, h2, h3, h4 {{ color: {primary} !important; font-weight: 700; border: 0 !important;
                  font-family: inherit !important; }}
h2 {{ border-bottom: 1px solid {edge} !important; padding-bottom: 4px; margin-top: 1.6em; }}
a, a:visited {{ color: {primary} !important; text-decoration: none; }}
a:hover {{ text-decoration: underline; }}
a.new {{ color: {red} !important; }}
p, li, dd, td, th, div, span, figcaption, caption {{ color: inherit; }}
table, .wikitable, .infobox, .sidebar, .navbox, .ambox, .hatnote, .thumbinner, figure, .mw-heading,
th, td, .toc, #toc, .quotebox, .side-box {{
    background: {bg_low} !important; color: {fg} !important; border-color: {edge} !important; }}
table, .infobox, .sidebar, figure, .thumbinner, .toc, #toc {{ border-radius: 12px; }}
.infobox, .sidebar {{ float: right; margin: 0 0 1em 1.4em; padding: 6px; font-size: 14px; max-width: 320px; }}
figure, .thumb {{ padding: 8px; margin: 1em 0 1em 1.4em; float: right; clear: right; max-width: 340px; }}
figure img, .thumb img {{ border-radius: 8px; background: #fff; }}
img {{ max-width: 100%; height: auto; }}
figcaption, .thumbcaption {{ font-size: 14px; color: {fg_dim} !important; padding-top: 6px; }}
pre, code, kbd {{ background: {bg_high} !important; color: {fg} !important; border-radius: 8px;
                  font-family: "FiraCode Nerd Font", "Fira Code", monospace; font-size: 14px; }}
pre {{ padding: 12px 14px; overflow-x: auto; border: 0 !important; }}
code {{ padding: 1px 5px; }}
pre code {{ padding: 0; }}
blockquote {{ border-left: 3px solid {primary}; margin-left: 0; padding-left: 14px; color: {fg_dim}; }}
hr {{ border: 0; border-top: 1px solid {edge}; margin: 2em 0; }}
sup.reference, .mw-editsection, .navbox, .metadata, .mw-empty-elt, .noprint, .mw-jump-link,
#mw-navigation, .catlinks, .printfooter {{ display: none !important; }}
/* maths: MathML, drawn by WebKit in the text color (Wikipedia hides it behind a picture) */
.mwe-math-mathml-a11y {{ display: inline !important; position: static !important; clip: auto !important;
                         width: auto !important; height: auto !important; overflow: visible !important;
                         opacity: 1 !important; }}
.mwe-math-mathml-display .mwe-math-mathml-a11y, .mwe-math-mathml-display {{ display: block !important;
                         text-align: center; margin: .6em 0; }}
img.mwe-math-fallback-image-inline, img.mwe-math-fallback-image-display {{ display: none !important; }}
math {{ font-size: 1.12em; color: {fg}; }}
math[display="block"] {{ margin: .7em 0; }}
.gvpost {{ background: {bg_low}; border: 1px solid {edge}; border-radius: 16px; padding: 4px 22px 10px; margin: 18px 0; }}
.gvmeta {{ display: inline-block; border-radius: 999px; padding: 2px 12px; font-size: 13px; font-weight: 700;
           background: {secondary_container}; color: {on_secondary_container}; margin-top: 14px; }}
.gvmeta.ok {{ background: {ok_bg}; color: {green}; }}
mjx-container {{ color: {fg}; }}
::selection {{ background: {primary_container}; }}
"""

MATHJAX = """<script>
window.MathJax = { tex: { inlineMath: [['$', '$'], ['\\\\(', '\\\\)']], displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
  processEscapes: true }, options: { skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'] } };
</script><script async src="https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-mml-chtml.js"></script>"""


def css():
    return PAGE_CSS.format(**dict(P, edge=mix(P["bg"], P["outline_variant"], 0.7),
                                  ok_bg=mix(P["bg"], P["green"], 0.2)))


def page(title, source, body, extra_head=""):
    t = GLib.markup_escape_text(title)
    return (f'<!doctype html><html><head><meta charset="utf-8"><title>{t}</title>{extra_head}</head>'
            f'<body><h1 id="gvtitle">{t}</h1><div id="gvsource">{GLib.markup_escape_text(source)}</div>'
            f"{body}</body></html>")


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


class Reader(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="GaussianVim Reader")
        self.set_wmclass("gaussianvim-reader", "GaussianVim Reader")
        self.set_default_size(1100, 950)
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", True)
        prov = Gtk.CssProvider()
        prov.load_from_data(f"""
headerbar {{ background: {mix(P['bg_low'], '#000000', 0.15)}; border: none; box-shadow: none; min-height: 42px;
            border-bottom: 1px solid {mix(P['bg'], P['outline_variant'], 0.55)}; }}
headerbar .title {{ color: {P['fg']}; font-weight: 800; }}
headerbar .subtitle {{ color: {P['outline']}; }}
headerbar button {{ background: transparent; background-image: none; border: none; box-shadow: none;
                   color: {P['fg_dim']}; border-radius: 999px; padding: 4px 12px; min-height: 0; }}
headerbar button:hover {{ background: {P['bg_highest']}; color: {P['fg']}; }}
headerbar button.titlebutton:hover {{ background: {P['error']}; color: {P['bg']}; }}
window {{ background: {P['bg']}; }}
""".encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        bar = Gtk.HeaderBar(show_close_button=True, title="Reader")
        self.bar = bar
        self.set_titlebar(bar)
        for label, tip, cb in (("←", "Back (Alt+Left)", lambda *_: self.view.go_back()),
                               ("→", "Forward (Alt+Right)", lambda *_: self.view.go_forward())):
            b = Gtk.Button(label=label, tooltip_text=tip)
            b.connect("clicked", cb)
            bar.pack_start(b)
        b = Gtk.Button(label="Open in browser", tooltip_text="o")
        b.connect("clicked", lambda *_: self.open_external())
        bar.pack_end(b)

        ucm = WebKit2.UserContentManager()
        ucm.add_style_sheet(WebKit2.UserStyleSheet(css(), WebKit2.UserContentInjectedFrames.ALL_FRAMES,
                                                   WebKit2.UserStyleLevel.USER, None, None))
        ctx = WebKit2.WebContext.get_default()
        ctx.register_uri_scheme("gvzim", self.zim_request)
        self.view = WebKit2.WebView.new_with_user_content_manager(ucm)
        bgc = Gdk.RGBA()
        bgc.parse(P["bg"])
        self.view.set_background_color(bgc)
        s = self.view.get_settings()
        s.set_enable_developer_extras(False)
        s.set_user_agent(UA)
        self.view.connect("decide-policy", self.on_policy)
        self.view.connect("notify::title", lambda v, _p: self.bar.set_subtitle(v.get_title() or None))
        self.add(self.view)
        self.connect("key-press-event", self.on_key)
        self.zims = {}            # gvzim host -> (path, Archive)
        self.external = None      # the page's address on the web
        self.show_all()

    # what to show ----------------------------------------------------------------
    def run(self, args):
        kind = args[0] if args else ""
        if kind == "wiki" and len(args) >= 2:
            self.wiki(args[1])
        elif kind == "zim" and len(args) >= 3:
            host = "z%d" % (abs(hash(args[1])) % 10 ** 8)
            self.zims.setdefault(host, (args[1], None))
            self.bar.set_title("Wikipedia (offline)")
            self.external = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(args[2])
            self.view.load_uri(f"gvzim://{host}/" + urllib.parse.quote(args[2]))
        elif kind == "html" and len(args) >= 2:
            with open(args[1], encoding="utf-8") as f:
                body = f.read()
            title = args[2] if len(args) > 2 else "GaussianVim"
            base = args[3] if len(args) > 3 else "https://stackexchange.com/"
            self.bar.set_title("Stack Exchange")
            self.external = base
            self.view.load_html(page(title, urllib.parse.urlparse(base).netloc, body, MATHJAX), base)
        self.present()

    def wiki(self, title):
        self.bar.set_title("Wikipedia")
        self.external = "https://en.wikipedia.org/wiki/" + urllib.parse.quote(title.replace(" ", "_"))
        self.view.load_html(page(title, "Wikipedia", "<p>loading …</p>"), self.external)

        def work():
            url = (f"{API}?action=parse&page={urllib.parse.quote(title)}&prop=text|displaytitle&format=json"
                   "&formatversion=2&redirects=1&disableeditsection=1&disablelimitreport=1")
            try:
                d = fetch_json(url)["parse"]
                html = page(d.get("title", title), "Wikipedia", d["text"])
            except Exception as err:
                html = page(title, "Wikipedia", f"<p>Couldn't load the article ({GLib.markup_escape_text(str(err))}).</p>")
            GLib.idle_add(lambda: self.view.load_html(html, self.external) and False)
        threading.Thread(target=work, daemon=True).start()

    # offline Wikipedia: gvzim://host/Path straight from the .zim
    def zim_request(self, req):
        host = urllib.parse.urlparse(req.get_uri()).netloc
        path = urllib.parse.unquote(req.get_path().lstrip("/"))
        try:
            zpath, arch = self.zims[host]
            if arch is None:
                from libzim.reader import Archive
                arch = Archive(zpath)
                self.zims[host] = (zpath, arch)
            entry = arch.get_entry_by_path(path)
            if entry.is_redirect:
                entry = entry.get_redirect_entry()
            item = entry.get_item()
            data, mime = bytes(item.content), item.mimetype
            if mime.startswith("text/html"):
                data = data.replace(b"<body", b'<body data-gv="1"', 1)
            stream = Gio.MemoryInputStream.new_from_bytes(GLib.Bytes.new(data))
            req.finish(stream, len(data), mime)
        except Exception as err:
            req.finish_error(GLib.Error.new_literal(GLib.quark_from_string("gvzim"), str(err), 1))

    # links: Wikipedia articles stay here, the rest opens in the browser
    def on_policy(self, _view, decision, dtype):
        if dtype != WebKit2.PolicyDecisionType.NAVIGATION_ACTION:
            return False
        action = decision.get_navigation_action()
        if action.get_navigation_type() != WebKit2.NavigationType.LINK_CLICKED:
            return False
        uri = action.get_request().get_uri()
        u = urllib.parse.urlparse(uri)
        if u.scheme == "gvzim":
            self.external = "https://en.wikipedia.org/wiki/" + u.path.lstrip("/")
            return False
        if u.netloc.endswith("wikipedia.org") and u.path.startswith("/wiki/") and ":" not in u.path[6:]:
            decision.ignore()
            self.wiki(urllib.parse.unquote(u.path[6:]).replace("_", " "))
            return True
        if u.fragment and uri.split("#")[0] == (self.view.get_uri() or "").split("#")[0]:
            return False
        decision.ignore()
        Gio.AppInfo.launch_default_for_uri(uri, None)
        return True

    def open_external(self):
        if self.external:
            Gio.AppInfo.launch_default_for_uri(self.external, None)

    def on_key(self, _w, ev):
        ctrl = ev.state & Gdk.ModifierType.CONTROL_MASK
        alt = ev.state & Gdk.ModifierType.MOD1_MASK
        k = ev.keyval
        if k in (Gdk.KEY_Escape, Gdk.KEY_q) and not ctrl:
            self.close()
        elif (alt and k == Gdk.KEY_Left) or k == Gdk.KEY_BackSpace:
            self.view.go_back()
        elif alt and k == Gdk.KEY_Right:
            self.view.go_forward()
        elif ctrl and k in (Gdk.KEY_plus, Gdk.KEY_equal):
            self.view.set_zoom_level(self.view.get_zoom_level() + 0.1)
        elif ctrl and k == Gdk.KEY_minus:
            self.view.set_zoom_level(max(0.4, self.view.get_zoom_level() - 0.1))
        elif ctrl and k == Gdk.KEY_0:
            self.view.set_zoom_level(1.0)
        elif k == Gdk.KEY_o and not ctrl:
            self.open_external()
        elif k == Gdk.KEY_j:
            self.view.run_javascript("window.scrollBy(0, 60)", None, None, None)
        elif k == Gdk.KEY_k:
            self.view.run_javascript("window.scrollBy(0, -60)", None, None, None)
        else:
            return False
        return True


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="org.gaussianvim.Reader",
                         flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
        self.win = None

    def do_command_line(self, cmdline):
        args = cmdline.get_arguments()[1:]
        if self.win is None:
            self.win = Reader(self)
        self.win.run(args)
        return 0


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
