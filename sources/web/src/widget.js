// 위젯 frame에 미리 넣는다. 위젯은 CDN을 쓸 수 없어서, 수식을 그리려면 KaTeX가 frame 안에 있어야 한다. 글에 `$…$`만
// 쓰면 페이지가 조판하고, SVG `<text>` 전체가 `$…$`이면 foreignObject로 바꿔 그린다. 위젯 스크립트는 `katex`와
// `folioTypeset(요소)`를 직접 부를 수도 있다. 겉 UI 스타일(widget.css)과 KaTeX 글꼴도 여기서 넣는다.
import katex from "katex";
import "katex/contrib/mhchem";

const NS = "http://www.w3.org/2000/svg";
const options = { throwOnError: false, strict: "ignore" };
const SKIP = "script,style,textarea,input,code,pre,.katex,[data-no-math]";

function svgText(text, tex) {
  const size = parseFloat(text.getAttribute("font-size")) || parseFloat(getComputedStyle(text).fontSize) || 14;
  const anchor = text.getAttribute("text-anchor") || getComputedStyle(text).textAnchor || "start";
  const x = +text.getAttribute("x") || 0, y = +text.getAttribute("y") || 0;
  const w = 400, h = size * 3, box = document.createElementNS(NS, "foreignObject");
  box.setAttribute("x", anchor === "middle" ? x - w / 2 : anchor === "end" ? x - w : x);
  // 글자의 x-height 가운데(기준선 위 0.3em)에 상자 가운데를 맞춘다.
  box.setAttribute("y", y - size * 0.3 - h / 2);
  box.setAttribute("width", w);
  box.setAttribute("height", h);
  box.setAttribute("pointer-events", "none");
  for (const name of ["class", "transform"]) if (text.hasAttribute(name)) box.setAttribute(name, text.getAttribute(name));
  const div = document.createElement("div");
  const align = anchor === "middle" ? "center" : anchor === "end" ? "flex-end" : "flex-start";
  div.style.cssText = `width:${w}px;height:${h}px;display:flex;align-items:center;justify-content:${align};font-size:${size}px;line-height:1;color:${getComputedStyle(text).fill}`;
  div.innerHTML = katex.renderToString(tex, options);
  box.append(div);
  text.replaceWith(box);
}

function typeset(root) {
  if (!root) return;
  if (root.nodeType === Node.TEXT_NODE) root = root.parentNode;
  if (!(root instanceof Element) || root.closest(SKIP)) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => (n.data.includes("$") && !n.parentElement?.closest(SKIP) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const parent = node.parentElement;
    if (!parent) continue;
    if (parent.namespaceURI === NS) {
      const m = parent.tagName === "text" && parent.textContent.match(/^\s*\$([^$]+)\$\s*$/);
      if (m) svgText(parent, m[1]);
      continue;
    }
    const parts = node.data.split(/(?<!\\)\$([^$]+?)(?<!\\)\$/);
    if (parts.length < 2) continue;
    const out = document.createDocumentFragment();
    parts.forEach((part, i) => {
      if (i % 2 === 0) { if (part) out.append(part.replace(/\\\$/g, "$")); return; }
      const span = document.createElement("span");
      span.innerHTML = katex.renderToString(part, options);
      out.append(span.firstChild);
    });
    node.replaceWith(out);
  }
}

const style = document.createElement("style");
style.id = "folio-widget-kit";
style.textContent = WIDGET_CSS;
document.documentElement.prepend(style);
window.katex = katex;
window.folioTypeset = typeset;

function start() {
  typeset(document.body);
  // 위젯이 나중에 넣거나 바꾼 글만 다시 본다. 조판이 만든 변화는 KaTeX 요소 안이라 건너뛴다.
  new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "characterData") typeset(record.target);
      else record.addedNodes.forEach(typeset);
    }
  }).observe(document.body, { childList: true, subtree: true, characterData: true });
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
else start();
