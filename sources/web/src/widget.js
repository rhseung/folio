// 위젯 frame에 미리 넣는다. 위젯은 CDN을 쓸 수 없어서, 수식을 그리려면 KaTeX가 frame 안에 있어야 한다. 글에 `$…$`만
// 쓰면 페이지가 조판하고, SVG `<text>` 전체가 `$…$`이면 노트 그림과 같은 MathJax path로 그린다. 위젯 스크립트는 `katex`와
// `folioTypeset(요소)`를 직접 부를 수도 있다. 겉 UI 스타일(widget.css)과 KaTeX 글꼴도 여기서 넣는다.
import katex from "katex";
import "katex/contrib/mhchem";
import { texToSVG } from "./tex-svg.js";

const NS = "http://www.w3.org/2000/svg";
const options = { throwOnError: false, strict: "ignore" };
const SKIP = "script,style,textarea,input,code,pre,.katex,[data-no-math]";

// SVG `<text>`의 수식은 KaTeX가 아니라 노트 그림과 같은 MathJax path로 그린다. KaTeX HTML을 foreignObject에 넣으면
// WebKit이 KaTeX의 `position: relative` 조각을 SVG의 viewBox 배율과 이동 없이 그려서, 그림이 늘거나 줄어도 수식은
// 처음 좌표의 픽셀 자리와 크기에 남는다. path는 SVG 좌표 안의 도형이라 선과 함께 늘어난다.
// 원래 `<text>`는 지우지 않고 숨겨 두고 그 뒤에 그린 묶음을 둔다. 위젯 스크립트가 쥔 `<text>`를 고치면(x, y, 글, 색)
// 아래 MutationObserver가 그 묶음을 다시 그린다.
const MATH = "data-folio-math";
const drawn = new WeakMap();
// 노트 그림의 수식과 같은 크기가 되도록 그림 스타일(FigureStyle)의 mathScale을 곱한다.
const mathScale = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--figure-math-scale")) || 1.21;
const firstNumber = (v) => parseFloat((v ?? "0").trim().split(/[\s,]+/)[0]) || 0;
const SHIFT = { start: 0, middle: 0.5, end: 1 };

function undraw(text) {
  drawn.get(text)?.remove();
  drawn.delete(text);
  text.removeAttribute(MATH);
}

function svgText(text, tex) {
  let svg;
  try {
    svg = texToSVG(tex);
  } catch {
    // 틀린 TeX는 원래 글자 그대로 둔다. 위젯을 쓴 쪽이 그 글자를 보고 고친다.
    return undraw(text);
  }
  const style = getComputedStyle(text);
  // SVG 안의 font-size는 사용자 좌표 단위다. 그래서 수식 크기도 viewBox 배율을 따른다.
  const px = parseFloat(style.fontSize) || 14, mpx = px * mathScale();
  const [bx, by, bw, bh] = svg.box;
  const width = (bw / 1000) * mpx;
  const x = firstNumber(text.getAttribute("x")) + firstNumber(text.getAttribute("dx"));
  const y = firstNumber(text.getAttribute("y")) + firstNumber(text.getAttribute("dy"));
  const left = x - width * (SHIFT[style.textAnchor] ?? 0);

  const group = drawn.get(text) ?? document.createElementNS(NS, "g");
  for (const name of [...group.getAttributeNames()]) group.removeAttribute(name);
  // 색 클래스(`ink`, `p-blue`)와 인라인 fill을 묶음에 옮겨 path가 같은 규칙으로 칠해지게 한다. 다크로 바뀌어도 변수를 따른다.
  for (const name of ["class", "style", "fill", "opacity", "transform"]) {
    if (text.hasAttribute(name)) group.setAttribute(name, text.getAttribute(name));
  }
  if (text.nextSibling !== group) text.after(group);
  // `svg text { fill: … }`처럼 `<text>`에만 걸리는 규칙은 묶음에 닿지 않는다. 그때만 계산된 색을 직접 준다.
  if (getComputedStyle(group).fill !== style.fill) group.style.fill = style.fill;
  if (style.display === "none") group.style.display = "none";
  group.setAttribute("aria-hidden", "true");
  group.setAttribute("pointer-events", "none");
  const r = (n) => +n.toFixed(2);
  group.innerHTML = `<svg x="${r(left)}" y="${r(y + (by / 1000) * mpx)}" width="${r(width)}" height="${r((bh / 1000) * mpx)}" `
    + `viewBox="${bx} ${by} ${bw} ${bh}" overflow="visible">${svg.body}</svg>`;
  drawn.set(text, group);
  text.setAttribute(MATH, "");
}

// 이미 수식으로 그린 `<text>`가 바뀌었을 때 다시 그리거나, 수식이 아니게 되었으면 원래 글자로 되돌린다.
function svgUpdate(text) {
  const m = text.textContent.match(/^\s*\$([^$]+)\$\s*$/);
  if (m) svgText(text, m[1]);
  else undraw(text);
}

// 수식 묶음의 자리와 모양을 정하는 `<text>`의 속성이다. 위젯이 이것을 바꾸면 다시 그린다.
const WATCHED = ["x", "y", "dx", "dy", "text-anchor", "font-size", "class", "style", "fill", "opacity", "transform"];

// 위젯이 수식 `<text>`만 떼어 내면 그 뒤에 둔 묶음이 남는다. 같은 자리에 다시 붙였으면 남겨 둔다.
function forgetRemoved(node) {
  if (!(node instanceof Element)) return;
  const texts = node.matches(`text[${MATH}]`) ? [node] : [...node.querySelectorAll(`text[${MATH}]`)];
  for (const text of texts) if (!text.isConnected) undraw(text);
}

function typeset(root) {
  if (!root) return;
  if (root.nodeType === Node.TEXT_NODE) root = root.parentNode;
  if (!(root instanceof Element) || root.closest(SKIP)) return;
  if (root.namespaceURI === NS && root.tagName === "text") return svgUpdate(root);
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => (n.data.includes("$") && !n.parentElement?.closest(SKIP) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
  });
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const parent = node.parentElement;
    if (!parent) continue;
    if (parent.namespaceURI === NS) {
      if (parent.tagName === "text") svgUpdate(parent);
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
  // 위젯이 나중에 넣거나 바꾼 글만 다시 본다. 조판이 만든 변화는 KaTeX 요소 안이거나 수식 묶음 안이라 건너뛴다.
  new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "characterData") typeset(record.target);
      else if (record.type === "attributes") { if (record.target.hasAttribute(MATH)) svgUpdate(record.target); }
      else {
        record.addedNodes.forEach(typeset);
        record.removedNodes.forEach(forgetRemoved);
      }
    }
  }).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: WATCHED });
  // 앱은 다크로 바꿀 때 페이지를 다시 읽지 않아 DOM이 그대로다. 계산된 색을 직접 준 묶음은 여기서 다시 칠한다.
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    document.querySelectorAll(`text[${MATH}]`).forEach(svgUpdate);
  });
}
if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
else start();
