"""GaussianTeX window: gv (GaussianVim) on the left and the PDF on the right,
in one window, like Overleaf. The PDF pane folds away and comes back.

Usage: gvwindow.py <command to run in the terminal...>     (gtex starts it)
       gvwindow.py --gv [gv args...]                       GaussianVim in the same window
                                                           (the LaTeX buttons come when a PDF does)

The left side is a terminal (VTE) running gv; the right side holds zathura,
embedded (zathura -e <id>), so it is not a separate window that pops up
wherever the desktop puts it.

  title bar              Material pills (colors: runner/gvtheme.py): Compile, Files,
                         Find, Copy, Paste, Backup, Share, and the PDF width:
                         35% / 50% / 70%, Show / Hide PDF
  the cards              gv and the PDF sit in rounded cards
  the divider            drag it: the PDF wider / narrower (the width is remembered)
  Ctrl+Shift+Left/Right  the PDF wider / narrower
  "hide" (PDF header)    fold the PDF away; the "PDF" tab at the right edge
                         (or the PDF button in gv's bottom bar) brings it back
  Ctrl+Shift+P           show / hide the PDF
  Ctrl+Shift+C / V       copy / paste (Copy: the selection in gv, or a Shift+drag
                         selection; in the PDF, selecting text copies it)

gv talks to this window through a small socket ($GV_DOCK): one command per
line, the answer is the pane's state (shown / hidden / empty):
  show  hide  toggle  state  focus-term  pid <zathura pid>
  server <gv's server address> <path to gv's nvim>  (so closing the window asks gv to quit)
X11, or Wayland through XWayland (embedding windows needs X11).
"""
import json
import os
import signal
import socket
import subprocess
import sys
import threading

if os.environ.get("DISPLAY") and os.environ.get("XDG_SESSION_TYPE") == "wayland":
    os.environ["GDK_BACKEND"] = "x11"     # Wayland: run through XWayland (embedding zathura needs X11)

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("Vte", "2.91")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango, Vte  # noqa: E402

from gvtheme import mix, palette  # noqa: E402

P = palette()
SURROUND = mix(P["bg"], "#000000", 0.35)       # around the cards
CARD_EDGE = mix(P["bg"], P["outline_variant"], 0.55)


def css():
    p = dict(P, surround=SURROUND, edge=CARD_EDGE, hover=mix(P["primary"], "#ffffff", 0.15),
             head=mix(P["bg_low"], "#000000", 0.15))
    return """
window.gvwin, .gvroot {{ background: {surround}; }}
headerbar {{ background: {head}; border: none; box-shadow: none; padding: 0 10px; min-height: 44px;
             border-bottom: 1px solid {edge}; }}
headerbar .title {{ color: {fg}; font-weight: 800; letter-spacing: 1px; }}
headerbar .subtitle {{ color: {outline}; }}
headerbar button {{ background: transparent; background-image: none; border: none; box-shadow: none;
                    color: {fg_dim}; border-radius: 999px; padding: 4px 14px; min-height: 0; text-shadow: none; }}
headerbar button:hover {{ background: {bg_highest}; color: {fg}; }}
headerbar button:active {{ background: {secondary_container}; }}
headerbar button.titlebutton {{ padding: 6px; }}
headerbar button.titlebutton:hover {{ background: {error}; color: {bg}; }}
headerbar button.gvprimary {{ background: {primary}; color: {on_primary}; font-weight: 800; }}
headerbar button.gvprimary:hover {{ background: {hover}; }}
.gvbrand {{ color: {primary}; font-weight: 900; font-size: 22px; padding: 0 8px 2px 2px; }}
.gvseg {{ background: {bg_high}; border-radius: 999px; padding: 2px; }}
.gvseg button {{ padding: 2px 12px; }}
.gvseg button.gvon {{ background: {secondary_container}; color: {on_secondary_container}; font-weight: 700; }}
.gvlabel {{ color: {outline}; font-size: 11px; }}
#gveditor {{ background: {bg}; border-radius: 16px; border: 1px solid {edge};
             margin: 8px 4px 8px 8px; padding: 12px 6px 8px 12px; }}
#gvpdfcard {{ background: {bg_low}; border-radius: 16px; border: 1px solid {edge};
              margin: 8px 8px 8px 4px; padding: 0 8px 8px 8px; }}
#gvpdfhead {{ background: transparent; padding: 6px 4px; }}
#gvpdfhead label {{ color: {primary}; font-weight: 800; }}
#gvpdfhead button {{ background: transparent; background-image: none; border: none; box-shadow: none;
                     padding: 0 10px; min-height: 0; color: {fg_dim}; border-radius: 999px; }}
#gvpdfhead button:hover {{ background: {bg_highest}; color: {fg}; }}
#gvtab {{ background: {primary_container}; color: {on_primary_container}; border: none; box-shadow: none;
          border-radius: 12px 0 0 12px; padding: 10px 3px; margin: 8px 0; min-width: 0; font-weight: 700; }}
#gvtab:hover {{ background: {primary}; color: {on_primary}; }}
paned > separator {{ background: transparent; background-image: none; min-width: 4px; }}
paned > separator:hover {{ background: alpha({primary}, 0.35); }}
""".format(**p).encode()

MIN_PDF_PX = 620

STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "gaussianvim", "gvwindow.json")


def reap(proc):
    """wait for a short-lived helper process in the background (no zombies)"""
    threading.Thread(target=proc.wait, daemon=True).start()
    return proc


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(d):
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, "w") as f:
            json.dump(d, f)
    except OSError:
        pass


def terminal_font():
    """the font of gnome-terminal's default profile (gv's icons need its Nerd Font)"""
    try:
        prof = subprocess.run(["gsettings", "get", "org.gnome.Terminal.ProfilesList", "default"],
                              capture_output=True, text=True, timeout=2).stdout.strip().strip("'")
        path = f"org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:{prof}/"
        use_sys = subprocess.run(["gsettings", "get", path, "use-system-font"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
        if use_sys == "false":
            f = subprocess.run(["gsettings", "get", path, "font"], capture_output=True, text=True,
                               timeout=2).stdout.strip().strip("'")
            if f and "Nerd" in f:
                return f
    except Exception:
        pass
    if os.environ.get("GV_FONT"):
        return os.environ["GV_FONT"]
    # a Nerd Font that is installed (the installer adds JetBrainsMono)
    try:
        fams = subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True, timeout=3).stdout
    except Exception:
        fams = ""
    for fam in ("FiraCode Nerd Font", "JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono"):
        if fam in fams:
            return fam + " 12"
    return "Monospace 12"


class Window(Gtk.Window):
    def __init__(self, argv):
        self.gv_mode = argv[:1] == ["--gv"]       # GaussianVim: no LaTeX buttons until there is a PDF
        if self.gv_mode:
            argv = argv[1:] or [os.path.expanduser("~/.local/bin/gv")]
        self.app_name = "GaussianVim" if self.gv_mode else "GaussianTeX"
        super().__init__(title=self.app_name)
        self.get_style_context().add_class("gvwin")
        if self.gv_mode:
            self.set_wmclass("gaussianvim", "GaussianVim")
        else:
            self.set_wmclass("gaussiantex", "GaussianTeX")
        self.set_icon_name("text-x-script")
        self.set_default_size(1500, 900)
        settings = Gtk.Settings.get_default()
        settings.set_property("gtk-application-prefer-dark-theme", True)
        prov = Gtk.CssProvider()
        prov.load_from_data(css())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                                 Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.argv = argv
        self.has_plug = False
        self.shown = False
        self.pdf_frac = float(load_state().get("pdf_frac", 0.45))   # the PDF's share of the width
        if not 0.15 <= self.pdf_frac <= 0.85:
            self.pdf_frac = 0.45
        self.zathura_pids = set()
        self.zathura_pid = None        # the zathura in the pane now
        self.refit_id = None
        self.nvim = None               # (server address, nvim binary), told by gv

        # left: the terminal running gv
        self.term = Vte.Terminal()
        self.term.set_font(Pango.FontDescription(terminal_font()))
        self.term.set_scrollback_lines(2000)
        self.term.set_mouse_autohide(True)
        self.term.set_audible_bell(False)
        self.term.set_cursor_blink_mode(Vte.CursorBlinkMode.OFF)
        bg, fg = Gdk.RGBA(), Gdk.RGBA()
        bg.parse(P["bg"])
        fg.parse(P["fg"])
        self.term.set_colors(fg, bg, None)
        self.term.connect("child-exited", self.on_child_exited)
        self.term.connect("window-title-changed", self.on_title)

        # right: a thin header and the socket zathura embeds into
        self.right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        head.set_name("gvpdfhead")
        title = Gtk.Label(label="\U000f0219  PDF")
        title.set_tooltip_text("Ctrl+click in the PDF: jump to that line in gv.\n"
                               "Select text in the PDF: it is copied.")
        head.pack_start(title, False, False, 0)
        for lbl, tip, d in (("◂ wider", "PDF wider (Ctrl+Shift+Left)", 0.05),
                            ("narrower ▸", "PDF narrower (Ctrl+Shift+Right)", -0.05)):
            b = self.flat_button(lbl, tip, lambda _b, d=d: self.resize_pdf(d))
            head.pack_end(b, False, False, 0)
        hide = Gtk.Button(label="hide ▸")
        hide.set_relief(Gtk.ReliefStyle.NONE)
        hide.set_can_focus(False)
        hide.set_tooltip_text("Fold the PDF away (Ctrl+Shift+P)")
        hide.connect("clicked", lambda *_: (self.hide_pdf(), self.tell_gv()))
        head.pack_end(hide, False, False, 0)
        self.right.pack_start(head, False, False, 0)
        self.sock = Gtk.Socket()
        self.sock.set_can_focus(True)
        self.sock.connect("plug-added", self.on_plug_added)
        self.sock.connect("plug-removed", self.on_plug_removed)
        self.right.pack_start(self.sock, True, True, 0)
        self.right.set_name("gvpdfcard")
        editor = Gtk.Box()
        editor.set_name("gveditor")
        editor.pack_start(self.term, True, True, 0)

        self.paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.paned.set_wide_handle(True)
        self.paned.pack1(editor, True, False)
        self.paned.pack2(self.right, False, True)
        self.paned_w = 0
        self.paned.connect("size-allocate", self.on_paned_alloc)
        self.paned.connect("button-release-event", self.on_paned_release)

        # the "PDF" tab at the right edge while the pane is folded
        self.tab = Gtk.Button(label="◂\nP\nD\nF")
        self.tab.set_name("gvtab")
        self.tab.set_relief(Gtk.ReliefStyle.NONE)
        self.tab.set_can_focus(False)
        self.tab.set_tooltip_text("Show the PDF (Ctrl+Shift+P)")
        self.tab.connect("clicked", lambda *_: (self.show_pdf(), self.tell_gv()))

        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        outer.pack_start(self.paned, True, True, 0)
        outer.pack_end(self.tab, False, False, 0)
        outer.get_style_context().add_class("gvroot")
        self.set_titlebar(self.header())
        self.add(outer)

        self.connect("key-press-event", self.on_key)
        self.connect("size-allocate", self.on_win_alloc)
        self.connect("delete-event", self.on_delete)
        self.maximize()
        self.show_all()
        self.right.hide()             # stays realized: zathura can embed while folded
        self.tab.hide()
        self.show_tex_buttons(not self.gv_mode)

        self.ctl_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", f"gvdock-{os.getpid()}.sock")
        self.start_control()
        self.spawn()

    # the title bar --------------------------------------------------------------------
    def flat_button(self, label, tip, cb):
        b = Gtk.Button(label=label)
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.set_can_focus(False)          # the keyboard stays in gv
        b.set_tooltip_text(tip)
        b.connect("clicked", cb)
        return b

    def header(self):
        """the title bar: Material pills (Compile, Copy / Paste, Backup; PDF width, Show PDF)"""
        bar = Gtk.HeaderBar()
        bar.set_show_close_button(True)
        bar.set_title(self.app_name)
        self.headerbar = bar

        def pill(label, tip, cb, cls=None):
            b = self.flat_button(label, tip, cb)
            if cls:
                b.get_style_context().add_class(cls)
            return b

        def seg(*buttons):
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
            box.get_style_context().add_class("gvseg")
            for b in buttons:
                box.pack_start(b, False, False, 0)
            return box

        brand = Gtk.Label(label="\u223f")            # ∿ a Gaussian-ish wave
        brand.get_style_context().add_class("gvbrand")
        bar.pack_start(brand)
        self.compile_btn = pill("\u25b6  Compile", "Compile the .tex (F5)",
                                lambda *_: self.gv_call("v:lua.GvWinAction('compile')"), "gvprimary")
        bar.pack_start(self.compile_btn)
        bar.pack_start(seg(pill("\U000f024b  Files", "The file tree (Space e)",
                                lambda *_: self.gv_call("v:lua.GvWinAction('files')")),
                           pill("\U000f0349  Find", "Find a file (Space f)",
                                lambda *_: self.gv_call("v:lua.GvWinAction('find')"))))
        bar.pack_start(seg(pill("\U000f018f  Copy", "Copy the selection (Ctrl+Shift+C)", lambda *_: self.copy()),
                           pill("\U000f0192  Paste", "Paste (Ctrl+Shift+V)", lambda *_: self.paste())))
        self.backup_btn = pill("\U000f0b6c  Backup", "Back up / restore this project (Space l B)",
                               lambda *_: self.gv_call("v:lua.GvBackupMenu()"))
        bar.pack_start(self.backup_btn)
        bar.pack_start(pill("\U000f0497  Share", "Share this project with gv users, Sync changes (Space l o)",
                            lambda *_: self.gv_call("v:lua.GvShareMenu()")))

        self.pdf_btn = pill("\U000f0219  Show PDF", "Show / hide the PDF (Ctrl+Shift+P)",
                            lambda *_: self.toggle_pdf(), "gvprimary")
        bar.pack_end(self.pdf_btn)
        self.frac_btns = {}
        for frac in (0.35, 0.5, 0.7):
            self.frac_btns[frac] = pill(f"{int(frac * 100)}%", f"PDF takes {int(frac * 100)}% of the width",
                                        lambda _b, f=frac: self.set_pdf_frac(f))
        self.width_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        lab = Gtk.Label(label="PDF width")
        lab.get_style_context().add_class("gvlabel")
        self.width_box.pack_start(lab, False, False, 0)
        self.width_box.pack_start(seg(*self.frac_btns.values()), False, False, 0)
        bar.pack_end(self.width_box)
        self.mark_frac()
        # narrow windows (a tiling window manager gives GTeX half the screen): the pill
        # labels shrink with "…" (icons stay) instead of pushing the window off-screen
        for b in [self.compile_btn, self.backup_btn, self.pdf_btn, *self.frac_btns.values()] + \
                 [c for box in bar.get_children() if isinstance(box, Gtk.Box) for c in box.get_children()
                  if isinstance(c, Gtk.Button)]:
            lbl = b.get_child()
            if isinstance(lbl, Gtk.Label):
                lbl.set_ellipsize(Pango.EllipsizeMode.END)
        return bar

    def on_win_alloc(self, _w, alloc):
        """compact title bar when the window is narrow: the PDF-width presets go first,
        then the secondary pills show just their icon (the tooltip still names them)"""
        wide = alloc.width >= 1350
        if self.width_box.get_visible() != wide:
            self.width_box.set_visible(wide)
            self.width_box.set_no_show_all(not wide)
        compact = alloc.width < 1150
        if getattr(self, "_compact", None) == compact:
            return
        self._compact = compact
        if not hasattr(self, "_full_labels"):
            self._full_labels = {}
            for box in self.headerbar.get_children():
                kids = box.get_children() if isinstance(box, Gtk.Box) else [box]
                for b in kids:
                    if isinstance(b, Gtk.Button) and b not in (self.compile_btn, self.pdf_btn) \
                            and b not in self.frac_btns.values() and isinstance(b.get_label(), str):
                        self._full_labels[b] = b.get_label()
        for b, full in self._full_labels.items():
            b.set_label(full.split("  ")[0] if compact and "  " in full else full)
        self.compile_btn.set_label("\u25b6  Compile")

    def show_tex_buttons(self, on):
        for w in (self.compile_btn, self.backup_btn, self.pdf_btn, self.width_box):
            w.set_visible(on)
            w.set_no_show_all(not on)
            if on:
                w.show_all()

    def mark_frac(self):
        """the PDF width button closest to the current width is lit"""
        near = min(self.frac_btns, key=lambda f: abs(f - self.pdf_frac))
        for f, b in self.frac_btns.items():
            ctx = b.get_style_context()
            (ctx.add_class if f == near and abs(f - self.pdf_frac) < 0.04 else ctx.remove_class)("gvon")

    def copy(self):
        if self.term.get_has_selection():           # a Shift+drag selection in the terminal
            self.term.copy_clipboard_format(Vte.Format.TEXT)
        else:                                       # the visual selection in gv
            self.gv_call("v:lua.GvWinAction('copy')")

    def paste(self):
        self.term.paste_clipboard()
        self.term.grab_focus()

    def gv_call(self, expr):
        if not self.nvim:
            return
        addr, binary = self.nvim
        try:
            reap(subprocess.Popen([binary, "--server", addr, "--remote-expr", expr],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        except OSError:
            pass
        self.term.grab_focus()

    # the PDF pane -----------------------------------------------------------------
    def set_pdf_frac(self, frac):
        self.pdf_frac = max(0.15, min(0.85, frac))
        save_state({"pdf_frac": self.pdf_frac})
        self.mark_frac()
        if not self.shown:
            if self.has_plug:
                self.show_pdf()
                self.tell_gv()
            return
        self.apply_frac()

    def resize_pdf(self, delta):
        self.set_pdf_frac(self.pdf_frac + delta)

    def apply_frac(self):
        w = self.paned.get_allocated_width()
        if self.shown and w > 100:
            # zathura can't get narrower than ~600 px (its page would be cut off)
            pdf_w = max(int(w * self.pdf_frac), min(MIN_PDF_PX, w // 2))
            pos = w - pdf_w
            if abs(pos - self.paned.get_position()) > 2:
                self.paned.set_position(pos)
                self.schedule_refit()
        return False

    # zathura keeps its zoom when the pane gets narrower / wider (the page is cut
    # off or small): reopening the file in place (D-Bus) fits it to the new width
    def schedule_refit(self):
        if self.refit_id:
            GLib.source_remove(self.refit_id)
        self.refit_id = GLib.timeout_add(350, self.refit_pdf)

    def refit_pdf(self):
        self.refit_id = None
        if not (self.zathura_pid and self.has_plug and self.shown):
            return False
        name = f"org.pwmt.zathura.PID-{self.zathura_pid}"
        path = "/org/pwmt/zathura"

        def got_props(bus, res):
            try:
                props = bus.call_finish(res).unpack()[0]
                f, page = props.get("filename"), int(props.get("pagenumber", 0))
            except Exception:
                return
            if f:
                bus.call(name, path, "org.pwmt.zathura", "OpenDocument", GLib.Variant("(ssi)", (f, "", page)),
                         None, Gio.DBusCallFlags.NONE, 3000, None, lambda b, r: self._finish(b, r))

        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            bus.call(name, path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", ("org.pwmt.zathura",)),
                     GLib.VariantType("(a{sv})"), Gio.DBusCallFlags.NONE, 2000, None, got_props)
        except Exception:
            pass
        return False

    @staticmethod
    def _finish(bus, res):
        try:
            bus.call_finish(res)
        except Exception:
            pass

    def on_paned_alloc(self, _p, alloc):
        # the window got bigger / smaller: the PDF keeps its share of the width
        if alloc.width != self.paned_w:
            self.paned_w = alloc.width
            GLib.idle_add(self.apply_frac)

    def on_paned_release(self, *_):
        # the divider dragged by hand: remember the new width
        w = self.paned.get_allocated_width()
        pos = self.paned.get_position()
        if self.shown and w > 100 and 0 < pos < w:
            frac = 1 - pos / w
            if 0.1 <= frac <= 0.9:
                self.pdf_frac = frac
                self.mark_frac()
                self.schedule_refit()
                if getattr(self, "_save_id", None):
                    GLib.source_remove(self._save_id)
                self._save_id = GLib.timeout_add(300, self._save_frac)
        return False

    def _save_frac(self):
        self._save_id = None
        save_state({"pdf_frac": self.pdf_frac})
        return False

    def state(self):
        if not self.has_plug:
            return "empty"
        return "shown" if self.shown else "hidden"

    def show_pdf(self):
        if self.shown:
            return
        self.shown = True
        self.right.show()
        self.tab.hide()
        self.pdf_btn.set_label("\U000f0219  Hide PDF")
        self.apply_frac()
        GLib.idle_add(self.apply_frac)     # again once the pane has its size

    def hide_pdf(self):
        if not self.shown:
            return
        self.shown = False
        self.pdf_btn.set_label("\U000f0219  Show PDF")
        self.right.hide()
        self.tab.set_visible(self.has_plug)
        self.term.grab_focus()

    def toggle_pdf(self):
        if not self.has_plug:            # no PDF yet: gv compiles / opens it
            self.gv_call("v:lua.GvWinAction('pdf')")
            return
        self.hide_pdf() if self.shown else self.show_pdf()
        self.tell_gv()

    def tell_gv(self):
        """the PDF button in gv's bottom bar follows the pane (hide button, tab, Ctrl+Shift+P)"""
        if not self.nvim:
            return
        addr, binary = self.nvim
        try:
            reap(subprocess.Popen([binary, "--server", addr, "--remote-expr", f"v:lua.GvPdfState('{self.state()}')"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        except OSError:
            pass

    def on_plug_added(self, *_):
        self.has_plug = True
        self.show_tex_buttons(True)
        self.show_pdf()
        self.tell_gv()
        # the keyboard stays in gv
        GLib.timeout_add(300, lambda: (self.term.grab_focus(), False)[1])

    def on_plug_removed(self, *_):
        self.has_plug = False
        self.hide_pdf()
        self.tab.hide()
        self.tell_gv()
        return True                   # keep the socket for the next zathura

    # gv ---------------------------------------------------------------------------
    def spawn(self):
        env = dict(os.environ)
        env.update({
            "GV_DOCK": self.ctl_path,
            "GV_PDF_XID": str(self.sock.get_id()),
            "WINDOWID": str(self.get_window().get_xid()),
            "COLORTERM": "truecolor",
        })
        envv = [f"{k}={v}" for k, v in env.items()]
        self.term.spawn_async(Vte.PtyFlags.DEFAULT, os.getcwd(), self.argv, envv,
                              GLib.SpawnFlags.SEARCH_PATH, None, None, -1, None, None)
        self.term.grab_focus()

    def on_child_exited(self, *_):
        self.quit()

    def on_title(self, term):
        t = term.get_window_title() or ""
        self.headerbar.set_subtitle(t or None)
        self.set_title(f"{t} — {self.app_name}" if t else self.app_name)
        self.headerbar.set_title(self.app_name)

    def on_delete(self, *_):
        # closing the window: ask gv to quit (it asks about unsaved files)
        if self.nvim:
            addr, binary = self.nvim
            try:
                reap(subprocess.Popen([binary, "--server", addr, "--remote-expr", "v:lua.GvWindowClose()"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
                return True
            except OSError:
                pass
        return False

    def on_key(self, _w, ev):
        mods = ev.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)
        if mods == (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK):
            k = Gdk.keyval_to_lower(ev.keyval)
            if k == Gdk.KEY_p:
                self.toggle_pdf()
                return True
            if k == Gdk.KEY_c:
                self.copy()
                return True
            if k == Gdk.KEY_v:
                self.term.paste_clipboard()
                return True
            if ev.keyval in (Gdk.KEY_Left, Gdk.KEY_Right):
                self.resize_pdf(0.05 if ev.keyval == Gdk.KEY_Left else -0.05)
                return True
        return False

    # the control socket (gv -> this window) -----------------------------------------
    def start_control(self):
        try:
            os.unlink(self.ctl_path)
        except FileNotFoundError:
            pass
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.ctl_path)
        os.chmod(self.ctl_path, 0o600)
        self.server.listen(8)
        GLib.io_add_watch(self.server.fileno(), GLib.IO_IN, self.on_conn)

    def on_conn(self, *_):
        try:
            conn, _ = self.server.accept()
        except OSError:
            return True
        conn.settimeout(1.0)
        data = b""
        try:
            while b"\n" not in data:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
        except OSError:
            pass
        for line in data.decode(errors="replace").splitlines():
            self.command(line.strip())
        try:
            conn.sendall((self.state() + "\n").encode())
        except OSError:
            pass
        conn.close()
        return True

    def command(self, cmd):
        if cmd == "show":
            if self.has_plug:
                self.show_pdf()
        elif cmd == "hide":
            self.hide_pdf()
        elif cmd == "toggle":
            if self.has_plug:
                self.toggle_pdf()
        elif cmd == "focus-term":
            self.present()
            self.term.grab_focus()
        elif cmd.startswith("server "):
            parts = cmd.split(" ", 2)
            if len(parts) == 3:
                self.nvim = (parts[1], parts[2])
        elif cmd.startswith("pid "):
            try:
                self.zathura_pid = int(cmd[4:])
                self.zathura_pids.add(self.zathura_pid)
            except ValueError:
                pass

    def quit(self):
        for pid in self.zathura_pids:     # no orphan zathura windows left behind
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        try:
            os.unlink(self.ctl_path)
        except OSError:
            pass
        Gtk.main_quit()


def main():
    argv = sys.argv[1:] or [os.path.expanduser("~/.local/bin/gv")]
    if not os.environ.get("DISPLAY"):
        if argv[0] == "--gv":
            argv = argv[1:] or [os.path.expanduser("~/.local/bin/gv")]
        os.execvp(argv[0], argv)      # no X11: no embedding, just gv
    win = Window(argv)
    signal.signal(signal.SIGTERM, lambda *_: GLib.idle_add(win.quit))
    Gtk.main()


if __name__ == "__main__":
    main()
