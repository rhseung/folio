import { renderMath } from "./math.js";
import { highlightBlocks } from "./code.js";
import { renderDiagrams } from "./mermaid.js";
import { preview } from "./preview.js";
import { figures } from "./figures.js";

// 미리보기는 블록을 페이지에 넣기 전에 조판하므로 `root`가 문서에 붙어 있지 않을 수 있다. 임베드한 노트는 자기
// 상자에 수식 문법을 따로 두며, 그 문법은 페이지의 문법과 다를 수 있다.
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

// Claude 패널의 대화는 문서가 아니라 자기 `.chat` 상자 안에서 스크롤되므로, 문서의 스크롤만 보면 움직임을 알 수 없다.
// scroll 이벤트는 버블링되지 않으므로 capture로 받는다. 상자는 업데이트마다 새로 만들어지므로 상자에 리스너를 달지 않는다.
function markEdges(el) {
  const max = el.scrollHeight - el.clientHeight;
  // `column-reverse`는 끝에서 시작하고, scrollTop은 맨 위의 -max에서 맨 아래의 0까지 움직인다.
  const reversed = getComputedStyle(el).flexDirection === "column-reverse";
  const fromStart = reversed ? max + el.scrollTop : el.scrollTop;
  el.classList.toggle("past-start", fromStart > 1);
  el.classList.toggle("past-end", fromStart < max - 1);
}
const markAll = () => document.querySelectorAll(".edge-fade").forEach(markEdges);
// 콜아웃을 접거나 KaTeX 글꼴이 늦게 도착해 내용이 스크롤 없이 커지거나 줄어도 스크롤 상자의 높이는 그대로이므로, 상자
// 대신 자식들을 관찰한다. 업데이트마다 관찰을 처음부터 다시 시작한다. 이전 상자와 자식은 이미 사라졌고, 콜백 안에서
// 모두 다시 관찰하면 콜백이 끝없이 다시 호출된다.
const grown = new ResizeObserver((entries) => {
  new Set(entries.map((e) => e.target.closest(".edge-fade"))).forEach((el) => el && markEdges(el));
});
function watch() {
  grown.disconnect();
  for (const el of document.querySelectorAll(".edge-fade")) for (const child of el.children) grown.observe(child);
  markAll();
}
document.addEventListener("scroll", (e) => e.target.classList?.contains("edge-fade") && markEdges(e.target), { capture: true, passive: true });
document.addEventListener("load", markAll, { capture: true });
document.addEventListener("toggle", (e) => { const el = e.target.closest?.(".edge-fade"); if (el) markEdges(el); }, { capture: true });
addEventListener("resize", markAll);
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watch);
else watch();

window.folioReader = {
  update(html) {
    document.body.innerHTML = html;
    typeset(document.body);
    watch();
  },
};

window.folioPreview = preview({ typeset, redraw: () => renderDiagrams(document.body) });
figures();

// 그림은 색을 CSS 변수가 아니라 값으로 받으므로, 화면 모드가 바뀌면 다시 그려야 한다.
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => renderDiagrams(document.body));
