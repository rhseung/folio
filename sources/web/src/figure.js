// 노트 그림을 쓸 때 앱과 CLI가 JavaScriptCore로 부른다(FolioActions의 NoteFigureFinish). 어느 AI가 그려도 같은
// 모양이 되도록 그림에 스타일 표의 `<style>`과 화살촉 `<marker>`를 넣고, `$…$`를 LaTeX 글자 모양(path)으로 바꾸고,
// 라벨 겹침을 검사한다. 스타일 표는 FolioDomain의 FigureStyle이 JSON으로 넘긴다. 낱말 폭은 바깥이 준
// `folioMeasure(글, px, 굵기)`로 잰다. 노트는 그림을 이미지로 보여서 페이지의 글꼴과 CSS를 쓸 수 없다.
import { texToSVG, shareGlyphs } from "./tex-svg.js";
import { parse, serialize, attr, classes, local, setAttr, walk, elements, textOf, replace, ancestors, escapeText } from "./svg-tree.js";
import { identity, multiply, invert, apply, parseTransform, outline, along, inFill } from "./svg-geometry.js";

const OWN = "folio-figure", OWN_DEFS = "folio-figure-defs";
const SOURCE = "data-source";
// 그림 안의 다른 요소처럼 다루지 않는 묶음이다. 화살촉과 무늬는 그 도형을 그릴 때만 쓰인다.
const HIDDEN = new Set(["defs", "marker", "clipPath", "mask", "pattern", "symbol", "style", "title", "desc", "metadata"]);
const SHAPES = new Set(["line", "rect", "circle", "ellipse", "polyline", "polygon", "path"]);

// 마무리한 부분(우리 `<style>`과 `<defs>`, 수식 라벨)을 걷어 쓴 사람이 쓴 모양으로 되돌린다. 고쳐 쓸 때 다시 마무리한다.
// 펼친 원문 안에 다시 `data-source`가 있을 수 있어 더 펼칠 것이 없을 때까지 돈다. 한 번만 펼치면 쓰기 전 검사는 안쪽을
// 속성 글자로만 보고 넘기는데, 마무리가 한 번 더 펼쳐 검사하지 않은 `<script>`가 파일에 남는다. 펼친 원문은 속성보다
// 짧으므로 끝난다.
function unfinish(doc) {
  for (let changed = true; changed; ) {
    changed = false;
    for (const el of [...walk(doc)]) {
      if ((el.name === "style" && attr(el, "id") === OWN) || (el.name === "defs" && attr(el, "id") === OWN_DEFS)) replace(el);
      else if (el.name === "g" && attr(el, SOURCE) != null) {
        const original = elements(parse(attr(el, SOURCE)))[0];
        if (original) {
          replace(el, original);
          changed = true;
        }
      }
    }
  }
}

const mathRuns = (text) => {
  const parts = [];
  let last = 0;
  for (const m of text.matchAll(/(?<!\\)\$((?:\\\$|[^$])+?)(?<!\\)\$/g)) {
    if (m.index > last) parts.push({ word: text.slice(last, m.index) });
    parts.push({ tex: m[1].replace(/\\\$/g, "\\$") });
    last = m.index + m[0].length;
  }
  if (last < text.length) parts.push({ word: text.slice(last) });
  return parts.map((p) => (p.word != null ? { word: p.word.replace(/\\\$/g, "$") } : p));
};

const hasMath = (text) => mathRuns(text).some((p) => p.tex != null);

function font(el, style) {
  for (const a of [el, ...ancestors(el)]) {
    const px = parseFloat(attr(a, "font-size") ?? /font-size\s*:\s*([\d.]+)/.exec(attr(a, "style") ?? "")?.[1]);
    if (Number.isFinite(px)) return px;
    const named = classes(a).find((c) => style.sizes[c]);
    if (named) return style.sizes[named];
  }
  return style.sizes[""];
}

function weight(el, style) {
  for (const a of [el, ...ancestors(el)]) {
    const w = attr(a, "font-weight");
    if (w) return w === "bold" ? 700 : +w || 400;
    if (classes(a).includes(style.bold)) return 700;
  }
  return 400;
}

function anchor(el) {
  for (const a of [el, ...ancestors(el)]) {
    const v = attr(a, "text-anchor") ?? /text-anchor\s*:\s*(\w+)/.exec(attr(a, "style") ?? "")?.[1];
    if (v) return v;
  }
  return "start";
}

const firstNumber = (v) => parseFloat((v ?? "0").trim().split(/[\s,]+/)[0]) || 0;
const shift = { start: 0, middle: 0.5, end: 1 };
const fmt = (n) => +n.toFixed(2);

// `$…$`가 든 `<text>`를 낱말 `<text>`와 수식 `<svg>`를 늘어놓은 `<g>`로 바꾼다. 원래 `<text>`는 고쳐 쓸 수 있게
// `data-source`에 남긴다.
function typeset(el, style, glyphs, problems) {
  const px = font(el, style), bold = weight(el, style), mpx = px * style.mathScale;
  const color = classes(el).find((c) => style.fills.includes(c)) ?? style.ink;
  const runs = [];
  for (const part of mathRuns(textOf(el))) {
    if (part.word != null) {
      if (part.word) runs.push({ word: part.word, width: folioMeasure(part.word, px, bold) });
      continue;
    }
    try {
      const svg = texToSVG(part.tex);
      runs.push({ svg, width: (svg.box[2] / 1000) * mpx });
    } catch (error) {
      problems.push({ kind: "tex", tex: part.tex, reason: String(error.message ?? error) });
      return;
    }
  }
  const total = runs.reduce((sum, r) => sum + r.width, 0);
  const y = firstNumber(attr(el, "y"));
  let x = firstNumber(attr(el, "x")) - total * (shift[anchor(el)] ?? 0);
  const keep = new Set(["x", "y", "dx", "dy", "text-anchor", "transform", "id", "opacity"]);
  const own = el.attrs.filter(([k]) => !keep.has(k)).map(([k, v]) => ` ${k}="${v.replace(/&/g, "&amp;").replace(/"/g, "&quot;")}"`).join("");
  let body = "";
  for (const r of runs) {
    if (r.word != null) body += `<text x="${fmt(x)}" y="${fmt(y)}"${own} xml:space="preserve">${escapeText(r.word)}</text>`;
    else {
      const [bx, by, bw, bh] = r.svg.box;
      body += `<svg x="${fmt(x)}" y="${fmt(y + (by / 1000) * mpx)}" width="${fmt(r.width)}" height="${fmt((bh / 1000) * mpx)}" `
        + `viewBox="${bx} ${by} ${bw} ${bh}" overflow="visible"><g class="${color}">${shareGlyphs(r.svg.body, glyphs)}</g></svg>`;
    }
    x += r.width;
  }
  const group = elements(parse(`<g>${body}</g>`))[0];
  for (const k of ["transform", "id", "opacity"]) if (attr(el, k) != null) setAttr(group, k, attr(el, k));
  group.attrs.push([SOURCE, serialize(el)]);
  group.size = { px, bold };
  replace(el, group);
}

export function finish(source, styleJSON) {
  const style = JSON.parse(styleJSON);
  let doc;
  try {
    doc = parse(source);
  } catch {
    // 올바른 XML이 아니면 Swift의 XMLParser가 줄 번호와 함께 알린다.
    return JSON.stringify({ svg: source, problems: [] });
  }
  const root = elements(doc)[0];
  if (!root || local(root.name) !== "svg") return JSON.stringify({ svg: source, problems: [] });
  unfinish(doc);

  const problems = [], glyphs = new Map();
  for (const el of [...walk(root)]) {
    if (el.name !== "text" || ancestors(el).some((a) => HIDDEN.has(a.name))) continue;
    const children = el.kids.filter((k) => k.t === "el");
    if (children.length) {
      if (children.some((c) => hasMath(textOf(c)))) problems.push({ kind: "tspan", text: textOf(el).trim() });
      continue;
    }
    if (hasMath(textOf(el))) typeset(el, style, glyphs, problems);
  }

  const used = new Set();
  for (const el of walk(root)) {
    for (const [k, v] of el.attrs) {
      if (!/^marker(-start|-mid|-end)?$/.test(k) && k !== "style") continue;
      for (const m of v.matchAll(/url\(\s*#([\w-]+)\s*\)/g)) if (style.markers[m[1]]) used.add(m[1]);
    }
  }
  // 쓴 사람이 같은 id로 둔 촉은 표의 촉으로 바꾼다.
  for (const el of [...walk(root)]) if (el.name === "marker" && used.has(attr(el, "id"))) replace(el);
  const defs = [...used].sort().map((id) => style.markers[id]).join("") + [...glyphs.values()].join("");
  const added = parse(`<style id="${OWN}">${style.css}</style>` + (defs ? `<defs id="${OWN_DEFS}">${defs}</defs>` : ""));
  for (const n of added.kids) n.parent = root;
  root.kids.unshift(...added.kids);

  problems.push(...overlaps(root, style));
  return JSON.stringify({ svg: serialize(doc), problems });
}

export function source(text) {
  try {
    const doc = parse(text);
    unfinish(doc);
    return serialize(doc);
  } catch {
    return text;
  }
}

// MARK: 겹침 검사

// SF Pro의 hhea 값이다. WebKit의 getBBox도 글자 상자를 이 높이로 잡는다.
const ASCENT = 0.95, DESCENT = 0.24;
const PAD = 1, GAP = 1.5;

function ctm(el) {
  let m = identity;
  for (const a of [...ancestors(el)].reverse().concat(el)) {
    if (a.name === "svg" && a.parent?.t === "el") m = multiply(m, [1, 0, 0, 1, firstNumber(attr(a, "x")), firstNumber(attr(a, "y"))]);
    m = multiply(m, parseTransform(attr(a, "transform")));
  }
  return m;
}

function textBox(el, text, style, x, y) {
  const px = font(el, style), w = folioMeasure(text, px, weight(el, style));
  const left = x - w * (shift[anchor(el)] ?? 0);
  return { x: left, y: y - ASCENT * px, w, h: (ASCENT + DESCENT) * px };
}

function union(boxes) {
  const x = Math.min(...boxes.map((b) => b.x)), y = Math.min(...boxes.map((b) => b.y));
  return { x, y, w: Math.max(...boxes.map((b) => b.x + b.w)) - x, h: Math.max(...boxes.map((b) => b.y + b.h)) - y };
}

function labels(root, style) {
  const out = [];
  const name = (text, m, box) => {
    const [x, y] = apply(m, [box.x, box.y]);
    return `${text.trim().slice(0, 24) || "$"} @(${Math.round(x)}, ${Math.round(y)})`;
  };
  const push = (el, box, text) => {
    const m = ctm(el);
    out.push({ el, box, m, inv: invert(m), name: name(text, m, box) });
  };
  for (const el of walk(root)) {
    if (ancestors(el).some((a) => HIDDEN.has(a.name) || attr(a, SOURCE) != null)) continue;
    if (el.name === "g" && attr(el, SOURCE) != null) {
      const boxes = elements(el).map((k) =>
        k.name === "text"
          ? textBox(k, textOf(k), style, firstNumber(attr(k, "x")), firstNumber(attr(k, "y")))
          : { x: firstNumber(attr(k, "x")), y: firstNumber(attr(k, "y")), w: firstNumber(attr(k, "width")), h: firstNumber(attr(k, "height")) });
      if (boxes.length) push(el, union(boxes), textOf(parse(attr(el, SOURCE))).replace(/\$/g, ""));
      continue;
    }
    if (el.name !== "text") continue;
    const placed = elements(el).filter((k) => attr(k, "x") != null || attr(k, "y") != null);
    if (placed.length) {
      for (const k of placed) {
        const text = textOf(k);
        if (text.trim()) push(el, textBox(k, text, style, firstNumber(attr(k, "x") ?? attr(el, "x")), firstNumber(attr(k, "y") ?? attr(el, "y"))), text);
      }
      continue;
    }
    const text = textOf(el);
    if (text.trim()) push(el, textBox(el, text, style, firstNumber(attr(el, "x")), firstNumber(attr(el, "y"))), text);
  }
  return out;
}

// 쓴 사람의 `<style>`에서 `.이름{…}`과 `요소{…}` 꼴의 규칙만 읽는다. 색은 표의 class로만 칠하지만, `fill:none`이나
// 선 굵기는 자기 class로 둘 수 있다.
function rules(root) {
  const out = new Map();
  for (const el of walk(root)) {
    if (el.name !== "style" || attr(el, "id") === OWN) continue;
    for (const [, selectors, body] of textOf(el).replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}@]+)\{([^{}]*)\}/g)) {
      const props = Object.fromEntries([...body.matchAll(/([\w-]+)\s*:\s*([^;]+)/g)].map((m) => [m[1], m[2].trim()]));
      for (const selector of selectors.split(",").map((x) => x.trim())) {
        if (/^\.?[\w-]+$/.test(selector)) out.set(selector, { ...out.get(selector), ...props });
      }
    }
  }
  return out;
}

// CSS 규칙이 표시 속성보다 우선하므로 style 속성, class, 속성 순으로 본다. 위에서 받은 값도 따라간다.
function property(el, prop, style, own = (a) => null) {
  for (const a of [el, ...ancestors(el)]) {
    const inline = new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`).exec(attr(a, "style") ?? "")?.[1]?.trim();
    if (inline) return inline;
    const named = own(a);
    if (named) return named;
    for (const c of classes(a)) if (style.rules.get("." + c)?.[prop]) return style.rules.get("." + c)[prop];
    if (style.rules.get(a.name)?.[prop]) return style.rules.get(a.name)[prop];
    const value = attr(a, prop);
    if (value) return value.trim();
  }
  return null;
}

const paint = (el, prop, style) =>
  property(el, prop, style, (a) => classes(a).find((c) => (prop === "fill" ? style.fills : style.strokes).includes(c)))
  ?? (prop === "fill" ? "black" : "none");

function number(el, prop, style, fallback) {
  const v = parseFloat(property(el, prop, style));
  return Number.isFinite(v) ? v : fallback;
}

const opaque = (el, style) => number(el, "fill-opacity", style, 1) === 1 && number(el, "opacity", style, 1) === 1;
const describe = (el) => el.name + classes(el).map((c) => "." + c).join("");

function inside(label, p, gap) {
  const [x, y] = apply(label.inv, p), b = label.box;
  return x > b.x - gap && x < b.x + b.w + gap && y > b.y - gap && y < b.y + b.h + gap;
}

function grid(label, nx = 8, ny = 4) {
  const out = [], b = label.box;
  for (let i = 0; i <= nx; i++)
    for (let j = 0; j <= ny; j++) out.push(apply(label.m, [b.x + PAD + ((b.w - 2 * PAD) * i) / nx, b.y + PAD + ((b.h - 2 * PAD) * j) / ny]));
  return out;
}

function overlaps(root, given) {
  const style = { ...given, rules: rules(root) };
  const found = [];
  const all = labels(root, style);
  for (let a = 0; a < all.length; a++)
    for (let c = a + 1; c < all.length; c++)
      if (grid(all[c]).some((p) => inside(all[a], p, -PAD)) || grid(all[a]).some((p) => inside(all[c], p, -PAD)))
        found.push({ kind: "labels", a: all[a].name, b: all[c].name });

  const shapes = [];
  for (const el of walk(root)) {
    if (!SHAPES.has(el.name) || ancestors(el).some((a) => HIDDEN.has(a.name) || attr(a, SOURCE) != null || (a.name === "svg" && a !== root)))
      continue;
    const m = ctm(el);
    const runs = outline(el).map((r) => ({ closed: r.closed, points: r.points.map((p) => apply(m, p)) }));
    const fill = el.name === "line" ? "none" : paint(el, "fill", style);
    const filled = fill !== "none" && fill !== "transparent";
    shapes.push({ el, runs, fill, filled, cover: filled && opaque(el, style) });
  }
  // 불투명하게 칠한 도형(종이색 정점 원과 상자)은 먼저 그린 선을 가린다. 가린 선 조각은 겹침이 아니다.
  const hidden = (k, p) => shapes.some((s, j) => j > k && s.cover && inFill(s.runs, p));
  shapes.forEach((s, k) => {
    if (classes(s.el).includes(style.grid) || ancestors(s.el).some((a) => classes(a).includes(style.grid))) return;
    const hits = new Set();
    const stroke = paint(s.el, "stroke", style);
    const width = number(s.el, "stroke-width", style, 1);
    if (stroke !== "none" && width > 0) {
      const gap = GAP + width / 2;
      for (const p of along(s.runs)) for (const label of all) if (!hits.has(label) && inside(label, p, gap) && !hidden(k, p)) hits.add(label);
      for (const label of hits) found.push({ kind: "line", a: label.name, shape: describe(s.el) });
    }
    // 라벨이 칠한 면 안에 다 들어가면 상자 속 라벨이다. 경계에 걸칠 때만 겹침이다.
    if (s.filled && s.fill !== style.paper && s.el.name !== "polyline") {
      for (const label of all) {
        if (hits.has(label)) continue;
        const ins = grid(label).map((p) => inFill(s.runs, p));
        if (ins.some(Boolean) && !ins.every(Boolean)) found.push({ kind: "fill", a: label.name, shape: describe(s.el) });
      }
    }
  });

  const box = viewBox(root);
  if (box) {
    for (const label of all) {
      if (grid(label, 2, 1).some(([x, y]) => x < box[0] || y < box[1] || x > box[0] + box[2] || y > box[1] + box[3]))
        found.push({ kind: "outside", a: label.name });
    }
  }
  return found;
}

function viewBox(root) {
  const v = (attr(root, "viewBox") ?? "").trim().split(/[\s,]+/).map(Number);
  if (v.length === 4 && v.every(Number.isFinite)) return v;
  const w = parseFloat(attr(root, "width")), h = parseFloat(attr(root, "height"));
  return Number.isFinite(w) && Number.isFinite(h) ? [0, 0, w, h] : null;
}
