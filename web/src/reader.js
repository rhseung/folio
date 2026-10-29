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
