import { renderMermaidSVG, measureTextWidth } from "beautiful-mermaid";
import { texToSVG, shareGlyphs } from "./tex-svg.js";

// mermaid 도식을 노트 그림과 같은 색, 글꼴, 화살촉으로 그린다. 라이브러리는 SVG 속성에 CSS 변수(--_text, --_line …)를
// 쓰므로 그 변수를 그림 팔레트 변수(--ink, --p-blue …)로 다시 정의한다. 팔레트 변수는 앱이 페이지에 넣고(FigureStyle)
// 라이트·다크를 따라가므로 도식은 값을 갖지 않는다. 라이브러리가 바꿀 수 없게 둔 크기 상수는 build.mjs가 고친다.
const NAMED = { blue: "p-blue", red: "p-red", green: "p-green", orange: "p-orange", magenta: "p-magenta", cyan: "p-cyan" };
const STEALTH = /^(arrowhead(-start)?(-[\w]+)?|seq-arrow|cls-arrow)$/;
// 수식 자리는 폭이 같은 키릴 글자로 채워 배치한 뒤 수식으로 바꾼다. 라이브러리가 글자 폭을 어림해 상자 크기를 정하기 때문이다.
const PLACE = 0x0430, PLACES = 32;
const SVGNS = "http://www.w3.org/2000/svg";
const MONO = "ui-monospace, Menlo, monospace";

function look() {
  const style = getComputedStyle(document.documentElement);
  const get = (name) => style.getPropertyValue(name).trim();
  return { sans: get("--figure-sans") || "-apple-system, sans-serif", mathScale: parseFloat(get("--figure-math-scale")) || 1.21,
    monoEm: parseFloat(get("--figure-mono-em")) || 0.525, arrow: [5.75, 4.3, 1.15].map((d, i) => parseFloat(get(["--figure-arrow-length", "--figure-arrow-width", "--figure-arrow-notch"][i])) || d) };
}

function scopedStyle(sans) {
  const map = { "--bg": "paper", "--fg": "ink", "--_text": "ink", "--_text-sec": "ink", "--_text-muted": "muted", "--_text-faint": "muted",
    "--_line": "ink", "--_arrow": "ink", "--_node-fill": "paper", "--_node-stroke": "ink", "--_group-fill": "paper", "--_group-hdr": "paper",
    "--_inner-stroke": "grid", "--_key-badge": "grid" };
  const vars = Object.entries(map).map(([k, v]) => `${k}:var(--${v})`).join(";");
  return `svg.folio-mermaid{${vars}}svg.folio-mermaid text{font-family:${sans}}`;
}

function stealth(id, fill, [length, width, notch]) {
  const L = length * 2, W = width * 2, N = notch * 2;
  const marker = document.createElementNS(SVGNS, "marker");
  for (const [k, v] of Object.entries({ id, viewBox: `0 0 ${L} ${W}`, refX: L - 1.6, refY: W / 2, markerWidth: length, markerHeight: width,
    markerUnits: "strokeWidth", orient: "auto-start-reverse" })) marker.setAttribute(k, v);
  marker.innerHTML = `<path d="M0,0 L${L},${W / 2} L0,${W} L${N},${W / 2} z" fill="${fill}"/>`;
  return marker;
}

function prepare(source, scale) {
  const maths = [];
  const charWidth = (ch) => measureTextWidth(ch, 100, 400) / 100;
  const text = source.replace(/(?<!\\)\$([^$\n]+?)\$/g, (whole, tex) => {
    if (maths.length >= PLACES) return whole;
    const ch = String.fromCharCode(PLACE + maths.length);
    let em = 1;
    try { em = (texToSVG(tex).box[2] / 1000) * scale; } catch {}
    maths.push(tex);
    return ch.repeat(Math.max(1, Math.round(em / charWidth(ch))));
  });
  return { text, maths };
}

let canvas = null;
function measure(text, px, weight, sans) {
  canvas ??= document.createElement("canvas").getContext("2d");
  canvas.font = `${weight} ${px}px ${sans}`;
  return canvas.measureText(text).width;
}

function baseline(text) {
  const px = parseFloat(text.getAttribute("font-size")) || 14;
  const dy = text.getAttribute("dy") ?? "0";
  return { px, y: parseFloat(text.getAttribute("y")) + (dy.endsWith("em") ? parseFloat(dy) * px : parseFloat(dy) || 0) };
}

function mathSVG(tex, x, y, mpx, fill, glyphs) {
  const r = texToSVG(tex);
  const [bx, by, bw, bh] = r.box, width = (bw / 1000) * mpx;
  const svg = `<svg x="${x}" y="${y + (by / 1000) * mpx}" width="${width}" height="${(bh / 1000) * mpx}" viewBox="${bx} ${by} ${bw} ${bh}" `
    + `overflow="visible"><g fill="${fill}">${shareGlyphs(r.body, glyphs)}</g></svg>`;
  return { svg, width };
}

const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");

// 노드와 선 라벨의 수식 자리를 낱말 `<text>`와 수식 `<svg>`를 늘어놓은 `<g>`로 바꾼다.
function typesetLabel(text, maths, glyphs, l) {
  const { px, y } = baseline(text);
  const fill = text.getAttribute("fill") ?? "var(--_text)";
  const weight = text.getAttribute("font-weight") ?? 400;
  const runs = text.textContent.split(new RegExp(`([${String.fromCharCode(PLACE)}-${String.fromCharCode(PLACE + PLACES - 1)}]+)`));
  const pieces = runs.filter(Boolean).map((run) => {
    const code = run.charCodeAt(0) - PLACE;
    return code >= 0 && code < PLACES ? { tex: maths[code] } : { word: run, width: measure(run, px, weight, l.sans) };
  });
  const mpx = px * l.mathScale;
  for (const p of pieces) if (p.tex != null) p.width = (texToSVG(p.tex).box[2] / 1000) * mpx;
  const total = pieces.reduce((s, p) => s + p.width, 0);
  const anchor = text.getAttribute("text-anchor") ?? "start";
  let x = parseFloat(text.getAttribute("x")) - total * ({ middle: 0.5, end: 1 }[anchor] ?? 0);
  let out = "";
  for (const p of pieces) {
    if (p.tex != null) out += mathSVG(p.tex, x, y, mpx, fill, glyphs).svg;
    else out += `<text x="${x}" y="${y}" font-size="${px}" font-weight="${weight}" fill="${fill}" xml:space="preserve">${escape(p.word)}</text>`;
    x += p.width;
  }
  return out;
}

// 클래스 멤버와 ER 속성은 코드라서 그림의 코드처럼 LaTeX 타자기체(\texttt) path로 그린다. TeX가 공백을 지우므로
// 공백은 타자기체 한 칸 폭만큼 옮긴다.
function typesetMono(text, glyphs, l) {
  const { px, y } = baseline(text), mpx = px * l.mathScale, space = l.monoEm * mpx;
  const spans = [...text.querySelectorAll("tspan")];
  const parts = spans.length ? spans.map((s) => [s.getAttribute("fill") ?? text.getAttribute("fill") ?? "var(--_text)", s.textContent])
    : [[text.getAttribute("fill") ?? "var(--_text)", text.textContent]];
  const runs = [];
  for (const [fill, t] of parts)
    for (const piece of t.match(/ +|[^ ]+/g) ?? []) {
      if (piece[0] === " ") runs.push({ width: piece.length * space });
      // MathJax의 \texttt는 `\`, `^`, `~`를 그대로 쓰지 못하므로 그 조각만 고정폭 글꼴의 글자로 둔다.
      else if (/[\\^~]/.test(piece)) runs.push({ word: piece, fill, width: measure(piece, px, 400, MONO) });
      else runs.push({ tex: `\\texttt{${piece.replace(/[_%#&{}$]/g, "\\$&")}}`, fill });
    }
  for (const r of runs) if (r.tex) r.width = (texToSVG(r.tex).box[2] / 1000) * mpx;
  const total = runs.reduce((s, r) => s + r.width, 0);
  const anchor = text.getAttribute("text-anchor") ?? "start";
  let x = parseFloat(text.getAttribute("x")) - total * ({ middle: 0.5, end: 1 }[anchor] ?? 0);
  let out = "";
  for (const r of runs) {
    if (r.tex) out += mathSVG(r.tex, x, y, mpx, r.fill, glyphs).svg;
    else if (r.word) out += `<text x="${x}" y="${y}" font-size="${px}" font-family="${MONO}" fill="${r.fill}" xml:space="preserve">${escape(r.word)}</text>`;
    x += r.width;
  }
  return out;
}

function replaceWith(el, markup) {
  const g = document.createElementNS(SVGNS, "g");
  g.innerHTML = markup;
  el.replaceWith(g);
}

function restyle(svg, maths, l) {
  svg.removeAttribute("style");
  svg.classList.add("folio-mermaid");
  const style = svg.querySelector("style");
  if (style) style.textContent = scopedStyle(l.sans);
  for (const el of svg.querySelectorAll("*")) {
    for (const name of ["fill", "stroke", "color"]) {
      const v = el.getAttribute(name);
      if (NAMED[v]) el.setAttribute(name, `var(--${NAMED[v]})`);
    }
  }
  // 선 위 라벨의 바탕은 선을 가리는 종이 조각으로만 남긴다. 그림의 라벨에는 상자가 없다.
  for (const rect of svg.querySelectorAll('rect[fill="var(--bg)"][stroke="var(--_inner-stroke)"]')) rect.setAttribute("stroke", "none");
  for (const el of svg.querySelectorAll('[fill="var(--_node-fill)"][stroke-width="0.75"]')) el.setAttribute("stroke-width", "1.1");
  for (const marker of svg.querySelectorAll("marker")) {
    if (STEALTH.test(marker.id)) {
      const fill = marker.querySelector("[fill]")?.getAttribute("fill");
      marker.replaceWith(stealth(marker.id, fill && fill !== "none" ? fill : "var(--_arrow)", l.arrow));
    } else if (marker.id.startsWith("cls-")) {
      // UML 촉(상속, 합성)은 모양을 둔다. viewBox 없이 그려져서 선 굵기만큼 커지면 테두리가 칸 밖에서 잘린다.
      marker.setAttribute("overflow", "visible");
      for (const shape of marker.querySelectorAll('[stroke-width="1.5"]')) shape.setAttribute("stroke-width", "1.1");
    }
  }
  // 라이브러리는 선 라벨을 흐린 색으로 쓰지만 그림의 선 라벨은 본문 색이다. 왼쪽 정렬 글(멤버의 형식)은 흐린 색으로 둔다.
  for (const text of svg.querySelectorAll('text[text-anchor="middle"][fill="var(--_text-muted)"]')) text.setAttribute("fill", "var(--_text-sec)");

  const glyphs = new Map();
  for (const text of [...svg.querySelectorAll("text.mono")]) replaceWith(text, typesetMono(text, glyphs, l));
  const placed = new RegExp(`[${String.fromCharCode(PLACE)}-${String.fromCharCode(PLACE + PLACES - 1)}]`);
  for (const text of [...svg.querySelectorAll("text")]) if (placed.test(text.textContent)) replaceWith(text, typesetLabel(text, maths, glyphs, l));
  if (glyphs.size) {
    const defs = document.createElementNS(SVGNS, "defs");
    defs.innerHTML = [...glyphs.values()].join("");
    svg.prepend(defs);
  }
}

export function renderDiagrams(root) {
  const blocks = [...root.querySelectorAll("pre[data-lang=mermaid]"), ...root.querySelectorAll("figure.mermaid")];
  if (!blocks.length) return;
  const l = look();
  for (const el of blocks) {
    const source = el.dataset.source ?? el.querySelector("code")?.textContent ?? "";
    try {
      const { text, maths } = prepare(source, l.mathScale);
      // 색은 restyle이 팔레트 변수로 바꾸므로 라이브러리에는 자리값만 준다. 라이브러리가 Google에서 글꼴을 받으려
      // 하지만 그 `<style>`은 통째로 바뀐다.
      const svg = renderMermaidSVG(text, { bg: "#ffffff", fg: "#000000", font: "-apple-system", transparent: true });
      const figure = el.tagName === "FIGURE" ? el : document.createElement("figure");
      figure.innerHTML = svg.replace(/@import url\([^)]*\);?/g, "");
      restyle(figure.querySelector("svg"), maths, l);
      // 미리보기가 이 요소를 붙잡고 있으므로, 화면 모드가 바뀌어 다시 그릴 때는 요소를 바꾸지 않고 안만 바꾼다.
      if (figure === el) continue;
      figure.className = "mermaid";
      figure.dataset.source = source;
      el.replaceWith(figure);
    } catch {
    }
  }
}
