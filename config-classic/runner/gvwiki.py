"""Offline Wikipedia (Kiwix .zim files) for gv's Wikipedia search (lua/gv/wiki.lua).

  gvwiki.py search FILE.zim "kondo effect"    JSON [{title, path}] (titles first, then full text)
  gvwiki.py article FILE.zim PATH             the article as Markdown, maths as $...$ / $$...$$

Needs the libzim package (pip install --user libzim).
"""
import html as htmllib
import json
import re
import subprocess
import sys


def archive(path):
    from libzim.reader import Archive
    return Archive(path)


def search(path, text, limit=40):
    zim = archive(path)
    out, seen = [], set()

    def add(p):
        p = getattr(p, "path", p)            # full-text results are objects, suggestions are paths
        try:
            entry = zim.get_entry_by_path(p)
        except KeyError:
            return
        if entry.is_redirect:
            entry = entry.get_redirect_entry()
        if entry.path in seen:
            return
        seen.add(entry.path)
        out.append({"title": entry.title, "path": entry.path})

    try:
        from libzim.suggestion import SuggestionSearcher
        sug = SuggestionSearcher(zim).suggest(text)
        for p in sug.get_results(0, limit):
            add(p)
    except Exception:
        pass
    if len(out) < limit:
        try:
            from libzim.search import Query, Searcher
            res = Searcher(zim).search(Query().set_query(text))
            for p in res.get_results(0, limit - len(out)):
                add(p)
        except Exception:
            pass
    print(json.dumps(out))


MATH_ATTR = re.compile(r'(?:alttext|alt|data-latex)="([^"]*)"')


def latex_of(fragment):
    m = MATH_ATTR.search(fragment)
    if not m:
        return None
    tex = htmllib.unescape(m.group(1)).strip()
    tex = re.sub(r"^\{\\displaystyle\s*(.*)\}$", r"\1", tex, flags=re.S)
    tex = re.sub(r"^\{\\textstyle\s*(.*)\}$", r"\1", tex, flags=re.S)
    return " ".join(tex.split())


def article(path, entry_path):
    zim = archive(path)
    entry = zim.get_entry_by_path(entry_path)
    if entry.is_redirect:
        entry = entry.get_redirect_entry()
    html = bytes(entry.get_item().content).decode("utf-8", "replace")
    # drop what isn't the article
    for pat in (r"<script.*?</script>", r"<style.*?</style>", r"<link[^>]*>",
                r'<(div|table)[^>]*class="[^"]*(navbox|metadata|mw-editsection|reflist|infobox)[^"]*".*?</\1>'):
        html = re.sub(pat, "", html, flags=re.S | re.I)
    # maths: keep the LaTeX (from the MathML alttext or the fallback image's alt)
    store = []

    def keep(m):
        frag = m.group(0)
        tex = latex_of(frag)
        if not tex:
            return frag
        display = "display" in frag[:200] and ('display="block"' in frag or "mwe-math-mathml-display" in frag
                                                 or "mwe-math-fallback-image-display" in frag)
        store.append((tex, display))
        return f"GVMATH{len(store) - 1}X"

    html = re.sub(r'<span[^>]*class="[^"]*mwe-math-element[^"]*".*?</span>\s*(?:<img[^>]*mwe-math-fallback[^>]*>)?\s*</span>',
                  keep, html, flags=re.S)
    html = re.sub(r"<math\b.*?</math>", keep, html, flags=re.S)
    html = re.sub(r'<img[^>]*class="[^"]*mwe-math-fallback[^"]*"[^>]*>', keep, html)
    html = re.sub(r"<img[^>]*>", "", html)
    # a <dd> holding only maths is a displayed equation (Wikipedia indents them that way)
    for m in re.finditer(r"<dd[^>]*>\s*GVMATH(\d+)X\s*([.,;:]?)\s*</dd>", html):
        n = int(m.group(1))
        store[n] = (store[n][0], True)
    html = re.sub(r"<h1\b.*?</h1>", "", html, flags=re.S)        # gv shows the title itself
    # links between articles: wiki:Title (gv follows them with Enter)
    html = re.sub(r'<a [^>]*href="(?:\./)?([^"#:]+)"[^>]*>', lambda m: f'<a href="WIKILINK{m.group(1)}">', html)
    md = subprocess.run(["pandoc", "-f", "html", "-t", "gfm-raw_html", "--wrap=none"], input=html,
                        capture_output=True, text=True).stdout
    md = re.sub(r"\]\(WIKILINK([^)\s]+)\)", lambda m: f"](wiki:{m.group(1)})", md)
    md = re.sub(r"GVMATH(\d+)X", lambda m: (f"\n\n$${store[int(m.group(1))][0]}$$\n\n" if store[int(m.group(1))][1]
                                             else f"${store[int(m.group(1))][0]}$"), md)
    print(md)


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "search":
        search(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 4 and sys.argv[1] == "article":
        article(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
