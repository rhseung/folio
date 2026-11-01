// Runs in the app's own script world: the page itself has JavaScript off, so nothing in it can run.
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

// The app swaps the page in place, so it keeps its scroll while an answer streams in.
window.folioReader = {
  update(html) {
    document.body.innerHTML = html;
    typeset();
  },
};
