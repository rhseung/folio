import { renderMermaidSVG } from "beautiful-mermaid";

// Resolved here rather than passed as `var(--accent)`: the SVG declares its own `--accent` and `--line`, which would
// then refer to themselves.
function colors() {
  const style = getComputedStyle(document.documentElement);
  const get = (name) => style.getPropertyValue(name).trim();
  return { bg: get("--card"), fg: get("--text"), line: get("--text-3"), accent: get("--accent"), muted: get("--text-2"),
    surface: get("--fill"), border: get("--line") };
}

// ```mermaid blocks become diagrams; one that doesn't parse stays as its code.
export function renderDiagrams(root) {
  const blocks = [...root.querySelectorAll("pre[data-lang=mermaid]"), ...root.querySelectorAll("figure.mermaid")];
  if (!blocks.length) return;
  const theme = { ...colors(), font: "-apple-system", transparent: true };
  for (const el of blocks) {
    const source = el.dataset.source ?? el.querySelector("code")?.textContent ?? "";
    try {
      // The library asks Google for its fonts; notes load nothing from the network.
      const svg = renderMermaidSVG(source, theme).replace(/@import url\([^)]*\);?/g, "");
      // A diagram drawn again for a new look keeps its element, which the preview holds on to.
      if (el.tagName === "FIGURE") { el.innerHTML = svg; continue; }
      const figure = document.createElement("figure");
      figure.className = "mermaid";
      figure.dataset.source = source;
      figure.innerHTML = svg;
      el.replaceWith(figure);
    } catch {
      // Left as code, which the highlighter treats as plain text.
    }
  }
}
