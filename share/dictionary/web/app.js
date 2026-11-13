// GaussianVim Dictionary: search by what you want to do. Data comes from app.py
// (window.GV): cheatsheet.tsv, snippets/tex.json, tex-auto.json.
"use strict";
const GV = window.GV || { entries: [], theme: {}, cats: [], query: "" };
for (const [k, v] of Object.entries(GV.theme || {})) document.documentElement.style.setProperty("--" + k, v);

// words people use for the same thing: a search for any of them finds the others
const SYNONYMS = [
  ["delete", "remove", "erase", "cut", "clear", "del"],
  ["copy", "yank", "duplicate"], ["paste", "put"], ["undo", "revert", "back", "mistake"],
  ["redo", "again", "repeat"], ["search", "find", "look", "locate", "grep"],
  ["replace", "substitute", "swap", "rename"], ["open", "launch", "show", "view"],
  ["save", "write", "store"], ["quit", "exit", "close", "leave"],
  ["move", "go", "jump", "navigate", "goto"], ["line", "row"], ["word", "term"],
  ["select", "highlight", "visual", "mark"], ["window", "split", "pane", "panel"],
  ["run", "execute", "start", "launch"], ["stop", "kill", "interrupt", "cancel", "abort", "halt", "terminate"],
  ["program", "code", "script", "python", "file"], ["plot", "graph", "chart", "figure", "picture", "image"],
  ["fraction", "divide", "division", "ratio", "quotient", "frac"],
  ["derivative", "differentiate", "differential", "slope", "rate", "derivate"],
  ["partial", "pd", "del"], ["integral", "integrate", "integration", "area", "int"],
  ["matrix", "array", "matrices"], ["table", "tabular", "grid", "columns", "rows"],
  ["equation", "formula", "math", "maths", "expression"], ["sum", "summation", "sigma", "series"],
  ["limit", "tends", "approaches"], ["power", "exponent", "superscript", "squared", "square", "cube"],
  ["subscript", "index", "lower"], ["root", "sqrt", "radical"], ["infinity", "infinite", "inf"],
  ["greek", "alpha", "beta", "gamma", "delta", "letter"],
  ["vector", "arrow", "bold"], ["gradient", "grad", "nabla"], ["spell", "spelling", "typo", "misspelled"],
  ["grammar", "sentence", "languagetool", "correct"], ["rephrase", "rewrite", "paraphrase", "reword", "improve", "ai", "qwen"],
  ["pdf", "preview", "viewer", "zathura", "output"], ["compile", "build", "latexmk", "typeset"],
  ["error", "bug", "problem", "warning", "diagnostic", "issue"], ["git", "commit", "push", "pull", "branch", "version"],
  ["comment", "uncomment"], ["terminal", "shell", "console", "command"], ["zip", "export", "download", "share", "archive"],
  ["upload", "import", "add"], ["average", "mean", "expectation", "expval"], ["absolute", "modulus", "abs", "magnitude"],
  ["quantum", "dirac", "bra", "ket", "state"], ["time", "dot"], ["bullet", "list", "itemize", "points"],
  ["numbered", "enumerate", "ordered"], ["heading", "section", "chapter", "title"],
  ["start", "beginning", "top", "first"], ["end", "bottom", "last"], ["indent", "tab", "shift"],
  ["case", "uppercase", "lowercase", "capital"], ["clipboard", "system"], ["theme", "colors", "colours", "colorscheme"],
  ["approximately", "approx", "about", "roughly"], ["times", "multiply", "product", "cross"],
  ["less", "smaller", "leq"], ["greater", "bigger", "geq"], ["not", "neq"], ["plus", "minus", "pm"],
  ["template", "snippet", "alias", "shortcut", "abbreviation"], ["zoom", "magnify", "enlarge"],
];
const SYN = new Map();
for (const g of SYNONYMS) for (const w of g) SYN.set(w, [...new Set([...(SYN.get(w) || []), ...g])]);
const STOP = new Set(["a", "an", "the", "to", "i", "want", "how", "do", "of", "in", "on", "for", "with", "my",
  "is", "it", "can", "me", "please", "some", "get", "into", "this", "that", "and", "or", "you", "should", "need", "using",
  "make", "create", "write", "insert", "add", "type", "put", "use", "new", "be", "there", "what", "which", "where", "way"]);

function stem(w) {
  if (w.length > 5 && w.endsWith("ing")) return w.slice(0, -3);
  if (w.length > 4 && w.endsWith("ed")) return w.slice(0, -2);
  if (w.length > 4 && w.endsWith("es")) return w.slice(0, -2);
  if (w.length > 3 && w.endsWith("s")) return w.slice(0, -1);
  return w;
}
const words = s => (s || "").toLowerCase().split(/[^a-z0-9\\^_/;+*.!<>=~-]+/).filter(Boolean);

// precomputed search fields
for (const e of GV.entries) {
  e._keys = (e.keys || "").toLowerCase();
  e._keyWords = new Set(e._keys.split(/\s+|\/|,/).filter(Boolean));
  e._title = words(e.title); e._desc = words(e.desc); e._words = words(e.words); e._cat = words(e.catName);
  e._all = [e._title, e._desc, e._words, e._cat];
}

function score(e, tokens, raw) {
  let total = 0, hit = 0;
  if (raw.length > 1 && e._keys.includes(raw)) total += 40;          // typed the keys / alias itself
  for (const t of tokens) {
    const alts = new Set([t, stem(t), ...(SYN.get(t) || []), ...(SYN.get(stem(t)) || [])]);
    let best = 0;
    for (const a of alts) {
      const sa = stem(a), same = a === t;
      const f = same ? 1 : 0.7;                                       // synonyms count a bit less
      if (e._keyWords.has(a)) best = Math.max(best, 14 * f);
      for (const [list, w] of [[e._title, 9], [e._words, 7], [e._desc, 6], [e._cat, 3]]) {
        for (const x of list) {
          if (x === a || stem(x) === sa) best = Math.max(best, w * f);
          else if (same && a.length > 2 && x.startsWith(a)) best = Math.max(best, (w - 2) * f);   // only what you typed
        }
      }
    }
    if (best > 0) { hit++; total += best; }
  }
  if (!tokens.length) return total;
  if (hit < Math.ceil(tokens.length * 0.6)) return 0;                 // most words must match
  return total + hit * 5;
}

// ── state ────────────────────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const state = { q: GV.query || "", group: "all", cat: null, sel: 0, shown: [] };
const esc = s => (s || "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

function keysHtml(e) {
  return esc(e.keys).split(/\s{2,}(or|\/)\s{2,}|\s+(or)\s+(?=[A-Z:])/).filter(x => x !== undefined && x !== "")
    .map(p => (p === "or" || p === "/") ? `<span class="or">${p}</span>` : `<span class="k">${p}</span>`).join("");
}
function mathHtml(src) {
  if (!src || !window.katex) return "";
  try { return katex.renderToString(src, { throwOnError: false, displayMode: false, strict: "ignore" }); }
  catch (_) { return ""; }
}
function card(e, i, showTag) {
  const alias = e.cat === "aliases" || e.cat === "instant";
  return `<div class="card${alias ? " alias" : ""}${i === state.sel ? " sel" : ""}" data-i="${i}">
    <div class="keys">${keysHtml(e)}</div>
    <div class="body">
      ${e.title ? `<div class="title">${esc(e.title)}</div>` : ""}
      <div class="desc">${esc(e.desc)}</div>
      ${e.code && !e.math ? `<pre>${esc(e.code)}</pre>` : ""}
      ${showTag ? `<span class="tag">${esc(e.group)} · ${esc(e.catName)}</span>` : ""}
    </div>
    <div class="math">${e.math ? mathHtml(e.math) : ""}</div>
  </div>`;
}
const HOWTO = {
  aliases: `<div class="howto"><b>How to use:</b> in a .tex file, insert mode, type the alias (e.g. <b>intgrl</b>),
    <b>Tab</b> selects it in the menu, <b>Enter</b> writes it. Type into the highlighted blank, <b>Tab</b> jumps to the next.
    They write plain LaTeX that compiles anywhere (Overleaf too).</div>`,
  instant: `<div class="howto"><b>How to use:</b> inside maths (<b>$…$</b>, equation, align) just type them: they turn
    into LaTeX at once, no menu. <b>//</b> gives \\frac{}{} with the cursor in the numerator, Tab goes to the denominator.
    They never fire in normal text or inside an index like _{xx}. <b>Space u a</b> switches them off.</div>`,
};

function inGroup(e) {
  if (state.group !== "all" && e.group !== state.group) return false;
  return !state.cat || e.cat === state.cat;
}

function render() {
  const raw = state.q.trim().toLowerCase();
  const tokens = words(raw).filter(t => !STOP.has(t));
  let list;
  if (raw) {
    list = GV.entries.filter(inGroup).map(e => [score(e, tokens, raw), e]).filter(x => x[0] > 0)
      .sort((a, b) => b[0] - a[0]).map(x => x[1]);
  } else {
    list = GV.entries.filter(inGroup);
  }
  state.shown = list;
  if (state.sel >= list.length) state.sel = Math.max(0, list.length - 1);
  $("clear").style.visibility = raw ? "visible" : "hidden";
  $("count").textContent = raw ? `${list.length} of ${GV.entries.length}` : `${GV.entries.length} entries`;

  let html = "";
  if (!list.length) {
    html = `<div class="empty">Nothing for “${esc(state.q)}”.<br><br>Try other words, e.g. <b>fraction</b>,
      <b>delete line</b>, <b>stop</b>, <b>pdf</b>, <b>greek</b>, <b>split window</b>.</div>`;
  } else if (raw) {
    if (list.some(e => e.cat === "instant") && list.slice(0, 6).some(e => e.cat === "instant")) html += HOWTO.instant;
    else if (list.slice(0, 6).some(e => e.cat === "aliases")) html += HOWTO.aliases;
    html += list.map((e, i) => card(e, i, true)).join("");
  } else {
    let cat = null, i = 0;
    for (const e of list) {
      if (e.cat !== cat) {
        cat = e.cat;
        html += `<h2>${esc(e.catName)} <span class="g">${esc(e.group)}</span></h2>` + (HOWTO[cat] || "");
      }
      html += card(e, i++, false);
    }
  }
  $("list").innerHTML = html;
  renderChips();
}

function renderChips() {
  const count = g => GV.entries.filter(e => g === "all" || e.group === g).length;
  $("groups").innerHTML = [["all", "Everything"], ["GaussianVim", "GaussianVim (editor)"], ["GaussianTeX", "GaussianTeX (LaTeX)"]]
    .map(([g, n]) => `<button class="chip big${state.group === g && !state.cat ? " on" : ""}" data-g="${g}">${n}<span class="n">${count(g)}</span></button>`).join("");
  const cats = GV.cats.filter(c => state.group === "all" || c.group === state.group)
    .filter(c => GV.entries.some(e => e.cat === c.id));
  $("cats").innerHTML = cats.map(c =>
    `<button class="chip${state.cat === c.id ? " on" : ""}" data-c="${c.id}">${esc(c.name)}</button>`).join("");
}

function select(i, scroll) {
  const cards = document.querySelectorAll(".card");
  if (!cards.length) return;
  state.sel = Math.max(0, Math.min(cards.length - 1, i));
  cards.forEach(c => c.classList.toggle("sel", +c.dataset.i === state.sel));
  if (scroll) cards[state.sel].scrollIntoView({ block: "nearest" });
}

let toastTimer;
function copy(e) {
  const text = e.copy || e.keys;
  try { window.webkit.messageHandlers.gvdict.postMessage(JSON.stringify({ copy: text })); } catch (_) {}
  const t = $("toast");
  t.textContent = "Copied  " + text.replace(/\s+/g, " ").slice(0, 80);
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 1400);
}

// ── events ───────────────────────────────────────────────────────────────
const q = $("q");
q.value = state.q;
q.addEventListener("input", () => { state.q = q.value; state.sel = 0; render(); $("list").scrollTop = 0; });
$("clear").addEventListener("click", () => { q.value = state.q = ""; render(); q.focus(); });
$("list").addEventListener("click", ev => {
  const c = ev.target.closest(".card");
  if (!c) return;
  select(+c.dataset.i);
  copy(state.shown[+c.dataset.i]);
});
$("groups").addEventListener("click", ev => {
  const b = ev.target.closest("[data-g]"); if (!b) return;
  state.group = b.dataset.g; state.cat = null; state.sel = 0; render(); $("list").scrollTop = 0;
});
$("cats").addEventListener("click", ev => {
  const b = ev.target.closest("[data-c]"); if (!b) return;
  state.cat = state.cat === b.dataset.c ? null : b.dataset.c; state.sel = 0; render(); $("list").scrollTop = 0;
});
document.addEventListener("keydown", ev => {
  if (ev.key === "ArrowDown") { select(state.sel + 1, true); ev.preventDefault(); }
  else if (ev.key === "ArrowUp") { select(state.sel - 1, true); ev.preventDefault(); }
  else if (ev.key === "PageDown") { select(state.sel + 8, true); ev.preventDefault(); }
  else if (ev.key === "PageUp") { select(state.sel - 8, true); ev.preventDefault(); }
  else if (ev.key === "Enter") { if (state.shown[state.sel]) copy(state.shown[state.sel]); ev.preventDefault(); }
  else if (ev.key === "Escape") {
    if (q.value) { q.value = state.q = ""; render(); }
    else { try { window.webkit.messageHandlers.gvdict.postMessage(JSON.stringify({ close: true })); } catch (_) {} }
    ev.preventDefault();
  } else if (document.activeElement !== q && ev.key.length === 1 && !ev.ctrlKey && !ev.metaKey) {
    q.focus();
  }
});
window.gvSetQuery = s => { q.value = state.q = s; state.sel = 0; render(); q.focus(); };
render();
q.focus();
