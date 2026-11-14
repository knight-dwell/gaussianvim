"""GaussianVim's Material palette for the GTK windows (gvwindow.py, gvreader.py).

Same colors as lua/gv/material.lua: the rice's generated palette
(~/.config/theme/generated/gaussianvim-colors.lua) when it exists, else the defaults.
"""
import os
import re

DEFAULT = {
    "bg": "#111318", "bg_dim": "#111318", "bg_low": "#1a1b20", "bg_float": "#1e1f25",
    "bg_high": "#282a2f", "bg_highest": "#33353a",
    "fg": "#e2e2e9", "fg_dim": "#c4c6d0", "outline": "#8e9099", "outline_variant": "#44474f",
    "primary": "#adc6ff", "on_primary": "#102f60", "primary_container": "#2b4678",
    "on_primary_container": "#d8e2ff",
    "secondary": "#bfc6dc", "secondary_container": "#3f4759", "on_secondary_container": "#dbe2f9",
    "tertiary": "#debcdf", "on_tertiary": "#402843", "tertiary_container": "#583e5b",
    "error": "#ffb4ab", "red": "#ef6f6c", "green": "#7fc98f", "yellow": "#e6c07b", "cyan": "#5cc8c8",
}


def palette():
    p = dict(DEFAULT)
    try:
        with open(os.path.expanduser("~/.config/theme/generated/gaussianvim-colors.lua")) as f:
            for k, v in re.findall(r'(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"', f.read()):
                p[k] = v
    except OSError:
        pass
    return p


def mix(a, b, t):
    """mix(a, b, 0.2) = 80 % a + 20 % b"""
    ca = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    cb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))
