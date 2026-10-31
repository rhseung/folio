// Runs in the app's own script world: the note page itself has JavaScript off, so nothing in a note can run.
import { renderMath } from "./math.js";
import { highlightBlocks } from "./code.js";

function typeset() {
  const syntax = document.body.dataset.math ?? "latex";
  for (const el of document.querySelectorAll(".math")) {
    el.innerHTML = renderMath(el.textContent, el.classList.contains("display"), syntax);
  }
  highlightBlocks(document);
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", typeset);
else typeset();

// The preview beside the editor. The app swaps the note in place, so the page keeps its scroll while you type, and
// moves it to the editor's top line by the blocks' `data-line` (HTMLRenderer `sourceLines`).
window.folioReader = {
  update(html) {
    document.body.innerHTML = html;
    typeset();
  },
  follow(line, frac) {
    const blocks = [...document.querySelectorAll("body > [data-line]")];
    const i = blocks.findLastIndex((b) => +b.dataset.line <= line);
    if (i < 0) return window.scrollTo(0, 0);
    const a = blocks[i], b = blocks[i + 1];
    const top = (el) => el.getBoundingClientRect().top + window.scrollY;
    const from = +a.dataset.line, to = b ? +b.dataset.line : from + 1;
    const ya = top(a), yb = b ? top(b) : ya + a.offsetHeight;
    window.scrollTo(0, ya + (yb - ya) * Math.min(1, (line - from + frac) / Math.max(1, to - from)) - 40);
  },
};
