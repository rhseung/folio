import { renderMermaidSVG } from "beautiful-mermaid";

// `var(--accent)`로 넘기지 않고 여기서 값을 읽는다. SVG가 자기 `--accent`와 `--line`을 선언하므로, 변수로 넘기면
// 그 변수가 자기 자신을 가리킨다.
function colors() {
  const style = getComputedStyle(document.documentElement);
  const get = (name) => style.getPropertyValue(name).trim();
  return { bg: get("--card"), fg: get("--text"), line: get("--text-3"), accent: get("--accent"), muted: get("--text-2"),
    surface: get("--fill"), border: get("--line") };
}

export function renderDiagrams(root) {
  const blocks = [...root.querySelectorAll("pre[data-lang=mermaid]"), ...root.querySelectorAll("figure.mermaid")];
  if (!blocks.length) return;
  const theme = { ...colors(), font: "-apple-system", transparent: true };
  for (const el of blocks) {
    const source = el.dataset.source ?? el.querySelector("code")?.textContent ?? "";
    try {
      // 라이브러리가 Google에서 글꼴을 받으려 하지만, 노트는 네트워크에서 아무것도 받지 않는다.
      const svg = renderMermaidSVG(source, theme).replace(/@import url\([^)]*\);?/g, "");
      // 미리보기가 이 요소를 붙잡고 있으므로, 화면 모드가 바뀌어 다시 그릴 때는 요소를 바꾸지 않고 안만 바꾼다.
      if (el.tagName === "FIGURE") { el.innerHTML = svg; continue; }
      const figure = document.createElement("figure");
      figure.className = "mermaid";
      figure.dataset.source = source;
      figure.innerHTML = svg;
      el.replaceWith(figure);
    } catch {
    }
  }
}
