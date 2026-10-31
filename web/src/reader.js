// Runs in the app's own script world: the note page itself has JavaScript off, so nothing in a note can run.
import { renderMath } from "./math.js";
import { highlightBlocks } from "./code.js";

function typeset() {
  const syntax = document.body.dataset.math ?? "latex";
  for (const el of document.querySelectorAll(".math")) {
    // Kept for writing the block back: the rendering replaces the TeX.
    el.dataset.tex ??= el.textContent;
    el.innerHTML = renderMath(el.textContent, el.classList.contains("display"), syntax);
  }
  highlightBlocks(document);
}

const post = (message) => window.webkit?.messageHandlers?.folioReader?.postMessage(message);
const editing = () => document.activeElement?.closest?.('[contenteditable="true"]');

// MARK: Writing a block back as markdown

// A typed character that markdown would read as markup gets a backslash. `*` and `_` with space on both sides, and `_`
// inside a word, can't be emphasis and stay bare, as people write them.
const WORD = /[\p{L}\p{N}]/u;
function escapeText(s) {
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i], prev = s[i - 1], next = s[i + 1];
    const spaced = prev !== undefined && next !== undefined && /\s/.test(prev) && /\s/.test(next);
    const inWord = c === "_" && prev !== undefined && next !== undefined && WORD.test(prev) && WORD.test(next);
    const markup = c === "\\" || c === "`" || c === "$" || ((c === "*" || c === "_") && !spaced && !inWord)
      || (c === "[" && next === "[") || (c === "]" && next === "(") || (c === "~" && next === "~") || (c === "<" && /[A-Za-z/!?]/.test(next ?? ""));
    out += markup ? "\\" + c : c;
  }
  return out;
}

// A typed line that would start a block (`# `, `- `, `> `, `1. `) is kept as text.
function escapeLineStart(line) {
  const n = /^(\d+)([.)])(\s|$)/.exec(line);
  if (n) return n[1] + "\\" + line.slice(n[1].length);
  return /^(#{1,6}(\s|$)|[-+](\s|$)|>|={3,}\s*$)/.test(line) ? "\\" + line : line;
}

const lines = (s) => s.replace(/\n+$/, "").split("\n").map(escapeLineStart).join("\n");

// Per line: emphasis can't span a line break that ends a paragraph, and typing on from bold text carries it to the
// next lines. Spaces go outside the marks, where they don't stop `**` from closing.
function wrap(mark, el) {
  return inline(el).split("\n").map((line) => {
    const [, lead, inner, trail] = /^(\s*)(.*?)(\s*)$/.exec(line);
    return inner ? lead + mark + inner + mark + trail : lead + trail;
  }).join("\n");
}

function piece(n) {
  if (n.nodeType === Node.TEXT_NODE) return escapeText(n.data.replace(/\n/g, "").replace(/ /g, " "));
  if (n.nodeType !== Node.ELEMENT_NODE) return "";
  if (n.dataset.src !== undefined) return n.dataset.src;
  if (n.classList.contains("math")) return `$${n.dataset.tex ?? n.textContent}$`;
  switch (n.tagName) {
    case "BR": return "\n";
    case "STRONG": case "B": return wrap("**", n);
    case "EM": case "I": return wrap("*", n);
    case "DEL": case "S": case "STRIKE": return wrap("~~", n);
    case "CODE": {
      const code = n.textContent, fence = "`".repeat(Math.max(0, ...(code.match(/`+/g) ?? []).map((r) => r.length)) + 1);
      return fence + (/^`|`$/.test(code) ? ` ${code} ` : code) + fence;
    }
    case "A": return `[${inline(n)}](${n.getAttribute("href")})`;
    case "IMG": return `![${n.alt}${n.getAttribute("width") ? "|" + n.getAttribute("width") : ""}](${n.getAttribute("src")})`;
    case "INPUT": return n.checked ? "[x]" : "[ ]";
    // What WebKit wraps a new line in when it doesn't put a <br>.
    case "DIV": case "P": return "\n" + inline(n);
    default: return inline(n);
  }
}

function inline(el) {
  let out = "";
  for (const n of el.childNodes) out += piece(n);
  return out;
}

// One level of a nested list, as the note already writes it.
const indentUnit = (src) => /^([ \t]+)(?:[-*+]|\d+[.)])(\s|$)/m.exec(src ?? "")?.[1] ?? "    ";

function list(el, unit, indent) {
  const out = [];
  let number = +(el.getAttribute("start") ?? 1);
  for (const item of el.children) {
    if (item.tagName !== "LI") {
      const text = lines(inline(item));
      if (text) out.push("", text);
      continue;
    }
    const mark = el.tagName === "UL" ? "-" : `${number++}.`;
    let text = "";
    const subs = [];
    for (const n of item.childNodes) {
      if (n.tagName === "UL" || n.tagName === "OL") subs.push(n);
      else text += piece(n);
    }
    text = lines(text.trim()) + (item.id.startsWith("^") ? " " + item.id : "");
    const hang = indent + " ".repeat(mark.length + 1);
    out.push(indent + mark + (text ? " " + text.split("\n").join("\n" + hang) : ""));
    for (const sub of subs) out.push(list(sub, unit, indent + unit));
  }
  return out.join("\n");
}

// The block's markdown as the page now shows it, or null for a block this can't write (callouts, tables, code, math).
function block(el) {
  const id = el.id.startsWith("^") ? " " + el.id : "";
  if (el.tagName === "P") return lines(inline(el)) + id;
  if (/^H[1-6]$/.test(el.tagName)) return "#".repeat(+el.tagName[1]) + " " + lines(inline(el));
  if (el.tagName === "UL" || el.tagName === "OL") return list(el, indentUnit(el.dataset.src), "");
  return null;
}

// Only a block that writes back exactly as it was written can be typed into, so an edit never restyles markdown the
// note didn't change (`_x_` stays `_x_`). The rest stay read-only.
function prepare() {
  if (document.body.dataset.editable === undefined) return;
  for (const el of document.querySelectorAll("body > [data-src]")) {
    if (block(el) !== el.dataset.src) continue;
    el.contentEditable = "true";
    el.spellcheck = false;
    for (const atom of el.querySelectorAll(".math, .wikilink, .embed, img")) atom.contentEditable = "false";
    for (const box of el.querySelectorAll("input[type=checkbox]")) box.disabled = false;
  }
}

// Sends the block's new lines with the lines it replaces; the app writes them only if those lines are still the same,
// so a page that fell behind the note can't overwrite anything. Later blocks shift here at once, for the next edit.
function commit(el) {
  const text = block(el), old = el.dataset.src;
  if (text === null || text === old) return false;
  post({ type: "edit", from: +el.dataset.line, to: +el.dataset.end, old, text });
  const delta = text.split("\n").length - old.split("\n").length;
  el.dataset.src = text;
  el.dataset.end = +el.dataset.end + delta;
  for (let b = el.nextElementSibling; b; b = b.nextElementSibling) {
    if (b.dataset.line === undefined) continue;
    b.dataset.line = +b.dataset.line + delta;
    b.dataset.end = +b.dataset.end + delta;
  }
  return true;
}

let timer, pending = null;
function apply(html) {
  pending = null;
  document.body.innerHTML = html;
  typeset();
  prepare();
}

document.addEventListener("input", (e) => {
  const el = e.target.closest?.('[contenteditable="true"]');
  if (!el) return;
  clearTimeout(timer);
  timer = setTimeout(() => commit(el), 250);
});

document.addEventListener("focusout", (e) => {
  const el = e.target.closest?.('[contenteditable="true"]');
  if (!el) return;
  clearTimeout(timer);
  // A commit brings the note back rendered anew; without one, the newest note held back while typing is shown now.
  if (!commit(el)) setTimeout(() => { if (pending !== null && !editing()) apply(pending); });
});

document.addEventListener("keydown", (e) => {
  const el = e.target.closest?.('[contenteditable="true"]');
  if (!el || e.isComposing) return;
  // A new line in the same block, which the note shows as a line break; a second one leaves a blank line, which
  // starts a new paragraph. Lists keep WebKit's own Enter, which makes the next item.
  if (e.key === "Enter" && !e.shiftKey && el.tagName !== "UL" && el.tagName !== "OL") {
    e.preventDefault();
    document.execCommand("insertLineBreak");
  }
});

// In a block being typed into, a click places the caret; ⌘-click opens the link, and a click ticks a task.
document.addEventListener("mousedown", (e) => {
  const box = e.target.closest?.('[contenteditable="true"] input[type=checkbox]');
  if (!box) return;
  e.preventDefault();
  box.checked = !box.checked;
  commit(box.closest('[contenteditable="true"]'));
});
document.addEventListener("click", (e) => {
  const a = e.target.closest?.("a[href]");
  if (!a || !a.closest('[contenteditable="true"]')) return;
  e.preventDefault();
  if (e.metaKey) post({ type: "open", href: a.href });
});

function start() {
  typeset();
  prepare();
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
else start();

// The app swaps the note in place, so the page keeps its scroll while you type in either view. Beside the editor, the
// page follows its top line by the blocks' `data-line` (HTMLRenderer `sourceLines`).
window.folioReader = {
  // ⌘B and ⌘I, sent by the app (NoteWebView), which takes them by key before the page and the input method do.
  format(command) {
    if (editing()) document.execCommand(command);
  },
  update(html, force = false) {
    // Replacing the block being typed into would drop the caret; the note waits until it's left.
    if (!force && editing()) pending = html;
    else apply(html);
  },
  follow(line, frac) {
    if (editing()) return;
    const blocks = [...document.querySelectorAll("body > [data-line]")];
    const i = blocks.findLastIndex((b) => +b.dataset.line <= line);
    if (i < 0) return window.scrollTo(0, 0);
    const a = blocks[i], b = blocks[i + 1];
    const top = (el) => el.getBoundingClientRect().top + window.scrollY;
    const from = +a.dataset.line, to = b ? +b.dataset.line : from + 1;
    const ya = top(a), yb = b ? top(b) : ya + a.offsetHeight;
    window.scrollTo(0, ya + (yb - ya) * Math.min(1, (line - from + frac) / Math.max(1, to - from)) - 40);
  },
  // For app-tests: the markdown a block writes back, and whether it can be typed into.
  debug: { block, commit },
};
