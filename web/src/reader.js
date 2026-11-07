// Runs in the app's own script world: the page's own scripts never run (the Claude panel turns them off, the note
// preview forbids them by its policy), so nothing in a page can reach this.
import { renderMath } from "./math.js";
import { highlightBlocks } from "./code.js";
import { renderDiagrams } from "./mermaid.js";
import { preview } from "./preview.js";

// Typesets what `root` holds. The preview typesets blocks before they go into the page, so `root` may be detached.
// An embedded note keeps its own math syntax on its box, which may differ from the page's.
export function typeset(root) {
  const page = document.body.dataset.math ?? "latex";
  for (const el of root.querySelectorAll(".math")) {
    const syntax = el.closest("[data-math]:not(body)")?.dataset.math ?? page;
    el.innerHTML = renderMath(el.textContent, el.classList.contains("display"), syntax);
  }
  renderDiagrams(root);
  highlightBlocks(root);
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => typeset(document.body));
else typeset(document.body);

// Marks which edges of an `.edge-fade` scroller have more past them (note.css fades those). The panel's conversation
// scrolls in its own `.chat` box, not the document, so watching the document's scroll never saw it move. Scroll events
// don't bubble, hence the capture; the box is replaced on every update, so nothing is bound to it.
function markEdges(el) {
  const max = el.scrollHeight - el.clientHeight;
  // `column-reverse` starts at the end, and its scrollTop runs from -max at the top to 0 at the bottom.
  const reversed = getComputedStyle(el).flexDirection === "column-reverse";
  const fromStart = reversed ? max + el.scrollTop : el.scrollTop;
  el.classList.toggle("past-start", fromStart > 1);
  el.classList.toggle("past-end", fromStart < max - 1);
}
const markAll = () => document.querySelectorAll(".edge-fade").forEach(markEdges);
// The scroller keeps its own height while what it holds grows or shrinks without a scroll (a callout folding, KaTeX's
// fonts arriving late), so its children are watched instead. Watching starts over after each update: the old box and
// its children are gone, and re-observing them all from the callback would fire it again forever.
const grown = new ResizeObserver((entries) => {
  new Set(entries.map((e) => e.target.closest(".edge-fade"))).forEach((el) => el && markEdges(el));
});
function watch() {
  grown.disconnect();
  for (const el of document.querySelectorAll(".edge-fade")) for (const child of el.children) grown.observe(child);
  markAll();
}
document.addEventListener("scroll", (e) => e.target.classList?.contains("edge-fade") && markEdges(e.target), { capture: true, passive: true });
// Images and diagrams grow the content after it lands.
document.addEventListener("load", markAll, { capture: true });
document.addEventListener("toggle", (e) => { const el = e.target.closest?.(".edge-fade"); if (el) markEdges(el); }, { capture: true });
addEventListener("resize", markAll);
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watch);
else watch();

// The Claude panel swaps its page in place, so it keeps its scroll while an answer streams in.
window.folioReader = {
  update(html) {
    document.body.innerHTML = html;
    typeset(document.body);
    watch();
  },
};

window.folioPreview = preview({ typeset, redraw: () => renderDiagrams(document.body) });

// Diagrams take their colors as values, so a new appearance draws them again; the rest follows the CSS variables.
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => renderDiagrams(document.body));
