// Runs in the app's own script world: the page's own scripts never run (the Claude panel turns them off, the note
// preview forbids them by its policy), so nothing in a page can reach this.
import { renderMath } from "./math.js";
import { highlightBlocks } from "./code.js";
import { renderDiagrams } from "./mermaid.js";
import { preview } from "./preview.js";

// Typesets what `root` holds. The preview typesets blocks before they go into the page, so `root` may be detached.
export function typeset(root) {
  const syntax = document.body.dataset.math ?? "latex";
  for (const el of root.querySelectorAll(".math")) {
    el.innerHTML = renderMath(el.textContent, el.classList.contains("display"), syntax);
  }
  renderDiagrams(root);
  highlightBlocks(root);
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => typeset(document.body));
else typeset(document.body);

// The Claude panel swaps its page in place, so it keeps its scroll while an answer streams in.
window.folioReader = {
  update(html) {
    document.body.innerHTML = html;
    typeset(document.body);
  },
};

window.folioPreview = preview({ typeset, redraw: () => renderDiagrams(document.body) });

// Diagrams take their colors as values, so a new appearance draws them again; the rest follows the CSS variables.
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => renderDiagrams(document.body));
