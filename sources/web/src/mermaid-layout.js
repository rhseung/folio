import { renderMermaidSVG, measureTextWidth } from "beautiful-mermaid";
import { texToSVG } from "./tex-svg.js";

// 앱 미리보기(mermaid.js)와 쓰기 전 검사(figure.js)가 함께 쓰는 배치다. 검사가 보는 라벨 자리가 미리보기에 그려지는 자리와
// 같아야 하므로, 라이브러리를 부르는 옵션과 수식 자리 배치를 여기 한 곳에만 둔다.

// 수식 자리는 폭이 같은 키릴 글자로 채워 배치한 뒤 수식으로 바꾼다. 라이브러리가 글자 폭을 어림해 상자 크기를 정하기 때문이다.
export const PLACE = 0x0430, PLACES = 32;
export const MONO = "ui-monospace, Menlo, monospace";
const RUN = new RegExp(`([${String.fromCharCode(PLACE)}-${String.fromCharCode(PLACE + PLACES - 1)}]+)`);
export const PLACED = new RegExp(`[${String.fromCharCode(PLACE)}-${String.fromCharCode(PLACE + PLACES - 1)}]`);

export function prepare(source, scale) {
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

// 색은 그린 뒤 팔레트 변수로 바꾸므로 라이브러리에는 자리값만 준다.
export const render = (text) => renderMermaidSVG(text, { bg: "#ffffff", fg: "#000000", font: "-apple-system", transparent: true });

// `<br/>`로 나눈 라벨은 `<text>` 안에 줄마다 `<tspan x dy>`로 온다. `spans`는 그 줄들의 `{x, dy, content}`다. 줄마다
// 기준선을 쌓아 따로 늘어놓는다. 줄을 이어 `<text>`의 기준선 한 줄에 두면 노드 가운데에 긴 한 줄이 되어 도형 밖으로 넘친다.
export function labelLines(content, x, y, spans) {
  if (!spans.length) return [{ content, x, y }];
  let at = y;
  return spans.map((s) => {
    at += s.dy;
    return { content: s.content, x: s.x, y: at };
  });
}

// 수식 자리가 든 라벨 한 줄을 낱말과 수식 조각으로 왼쪽부터 늘어놓는다. `measure(글, px, 굵기)`는 낱말 폭이다.
export function labelPieces(content, x, anchor, px, weight, maths, mathScale, measure) {
  const pieces = content.split(RUN).filter(Boolean).map((run) => {
    const code = run.charCodeAt(0) - PLACE;
    return code >= 0 && code < PLACES ? { tex: maths[code] } : { word: run, width: measure(run, px, weight) };
  });
  const mpx = px * mathScale;
  for (const p of pieces) if (p.tex != null) p.width = (texToSVG(p.tex).box[2] / 1000) * mpx;
  return line(pieces, x, anchor, mpx);
}

// 클래스 멤버와 ER 속성은 코드라서 LaTeX 타자기체(\texttt)로 그린다. TeX가 공백을 지우므로 공백은 타자기체 한 칸
// 폭만큼 옮긴다. `parts`는 [색, 글]의 목록이고 `measureMono(글, px)`는 고정폭 글꼴의 폭이다.
export function monoPieces(parts, x, anchor, px, mathScale, monoEm, measureMono) {
  const mpx = px * mathScale, space = monoEm * mpx;
  const pieces = [];
  for (const [fill, t] of parts)
    for (const piece of t.match(/ +|[^ ]+/g) ?? []) {
      if (piece[0] === " ") pieces.push({ width: piece.length * space });
      // MathJax의 \texttt는 `\`, `^`, `~`를 그대로 쓰지 못하므로 그 조각만 고정폭 글꼴의 글자로 둔다.
      else if (/[\\^~]/.test(piece)) pieces.push({ word: piece, fill, mono: true, width: measureMono(piece, px) });
      else pieces.push({ tex: `\\texttt{${piece.replace(/[_%#&{}$]/g, "\\$&")}}`, fill });
    }
  for (const p of pieces) if (p.tex) p.width = (texToSVG(p.tex).box[2] / 1000) * mpx;
  return line(pieces, x, anchor, mpx);
}

function line(pieces, x, anchor, mpx) {
  const total = pieces.reduce((s, p) => s + p.width, 0);
  let at = x - total * ({ middle: 0.5, end: 1 }[anchor] ?? 0);
  for (const p of pieces) {
    p.x = at;
    at += p.width;
  }
  return { pieces, mpx };
}

// 수식 조각의 `<svg>` 자리다. 글자 기준선 `y`에서 MathJax 상자의 위쪽(음수)만큼 올린다.
export function mathBox(tex, x, y, mpx) {
  const r = texToSVG(tex);
  const [, by, bw, bh] = r.box;
  return { r, x, y: y + (by / 1000) * mpx, width: (bw / 1000) * mpx, height: (bh / 1000) * mpx };
}
