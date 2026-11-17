// 라벨 겹침 검사에 쓰는 SVG 기하. 페이지 없이 돌므로 getBBox와 getPointAtLength 대신 도형을 직접 꺾은선으로 편다.
import { attr } from "./svg-tree.js";

export const identity = [1, 0, 0, 1, 0, 0];

export function multiply(m, n) {
  return [
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
  ];
}

export function invert(m) {
  const det = m[0] * m[3] - m[1] * m[2] || 1e-12;
  return [m[3] / det, -m[1] / det, -m[2] / det, m[0] / det, (m[2] * m[5] - m[3] * m[4]) / det, (m[1] * m[4] - m[0] * m[5]) / det];
}

export const apply = (m, [x, y]) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];

const numbers = (s) => (s.match(/[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi) ?? []).map(Number);

export function parseTransform(text) {
  let m = identity;
  for (const [, name, args] of (text ?? "").matchAll(/(\w+)\s*\(([^)]*)\)/g)) {
    const a = numbers(args);
    let n = identity;
    if (name === "matrix" && a.length === 6) n = a;
    else if (name === "translate") n = [1, 0, 0, 1, a[0] ?? 0, a[1] ?? 0];
    else if (name === "scale") n = [a[0] ?? 1, 0, 0, a[1] ?? a[0] ?? 1, 0, 0];
    else if (name === "rotate") {
      const r = ((a[0] ?? 0) * Math.PI) / 180, c = Math.cos(r), s = Math.sin(r);
      n = [c, s, -s, c, 0, 0];
      if (a.length >= 3) n = multiply(multiply([1, 0, 0, 1, a[1], a[2]], n), [1, 0, 0, 1, -a[1], -a[2]]);
    } else if (name === "skewX") n = [1, 0, Math.tan(((a[0] ?? 0) * Math.PI) / 180), 1, 0, 0];
    else if (name === "skewY") n = [1, Math.tan(((a[0] ?? 0) * Math.PI) / 180), 0, 1, 0, 0];
    m = multiply(m, n);
  }
  return m;
}

const num = (el, name, fallback = 0) => {
  const v = parseFloat(attr(el, name));
  return Number.isFinite(v) ? v : fallback;
};

function ellipse(cx, cy, rx, ry) {
  const n = Math.max(24, Math.ceil(Math.PI * (rx + ry)));
  return Array.from({ length: n }, (_, k) => [cx + rx * Math.cos((2 * Math.PI * k) / n), cy + ry * Math.sin((2 * Math.PI * k) / n)]);
}

// 도형을 닫힌 꺾은선과 열린 꺾은선의 목록으로 편다. 좌표는 그 도형 자신의 좌표계다.
export function outline(el) {
  const name = el.name;
  if (name === "line") return [{ points: [[num(el, "x1"), num(el, "y1")], [num(el, "x2"), num(el, "y2")]], closed: false }];
  if (name === "rect") {
    const x = num(el, "x"), y = num(el, "y"), w = num(el, "width"), h = num(el, "height");
    return w > 0 && h > 0 ? [{ points: [[x, y], [x + w, y], [x + w, y + h], [x, y + h]], closed: true }] : [];
  }
  if (name === "circle") return [{ points: ellipse(num(el, "cx"), num(el, "cy"), num(el, "r"), num(el, "r")), closed: true }];
  if (name === "ellipse") return [{ points: ellipse(num(el, "cx"), num(el, "cy"), num(el, "rx"), num(el, "ry")), closed: true }];
  if (name === "polyline" || name === "polygon") {
    const a = numbers(attr(el, "points") ?? "");
    const points = [];
    for (let i = 0; i + 1 < a.length; i += 2) points.push([a[i], a[i + 1]]);
    return [{ points, closed: name === "polygon" }];
  }
  if (name === "path") return pathOutline(attr(el, "d") ?? "");
  return [];
}

function pathOutline(d) {
  const tokens = d.match(/[a-df-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi) ?? [];
  const runs = [];
  let run = null, x = 0, y = 0, sx = 0, sy = 0, command = "", lastControl = null, i = 0;
  const take = () => +tokens[i++];
  const start = () => { run = { points: [[x, y]], closed: false }; runs.push(run); };
  const to = (px, py) => { if (!run) start(); run.points.push([px, py]); x = px; y = py; };
  const curve = (pts) => {
    const length = pts.reduce((sum, p, k) => (k ? sum + Math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) : 0), 0);
    const steps = Math.max(4, Math.ceil(length / 2));
    for (let s = 1; s <= steps; s++) to(...bezier(pts, s / steps));
  };
  while (i < tokens.length) {
    if (/[a-z]/i.test(tokens[i])) command = tokens[i++];
    const rel = command === command.toLowerCase() && command !== "z" ? 1 : 0;
    const ox = rel * x, oy = rel * y;
    const c = command.toUpperCase();
    if (c === "M") {
      x = ox + take(); y = oy + take(); sx = x; sy = y; start();
      command = rel ? "l" : "L";
      lastControl = null;
      continue;
    }
    if (c === "Z") { if (run) { run.closed = true; run = null; } x = sx; y = sy; lastControl = null; continue; }
    if (c === "L") { to(ox + take(), oy + take()); lastControl = null; }
    else if (c === "H") { to(ox + take(), y); lastControl = null; }
    else if (c === "V") { to(x, oy + take()); lastControl = null; }
    else if (c === "C" || c === "S") {
      const c1 = c === "C" ? [ox + take(), oy + take()] : lastControl ? [2 * x - lastControl[0], 2 * y - lastControl[1]] : [x, y];
      const c2 = [ox + take(), oy + take()], end = [ox + take(), oy + take()];
      curve([[x, y], c1, c2, end]);
      lastControl = c2;
    } else if (c === "Q" || c === "T") {
      const c1 = c === "Q" ? [ox + take(), oy + take()] : lastControl ? [2 * x - lastControl[0], 2 * y - lastControl[1]] : [x, y];
      const end = [ox + take(), oy + take()];
      curve([[x, y], c1, end]);
      lastControl = c1;
    } else if (c === "A") {
      const rx = take(), ry = take(), rotation = take(), large = take(), sweep = take();
      arc(x, y, rx, ry, rotation, large, sweep, ox + take(), oy + take(), to);
      lastControl = null;
    } else i++;
  }
  return runs.filter((r) => r.points.length > 1);
}

function bezier(pts, t) {
  let p = pts;
  while (p.length > 1) p = p.slice(1).map((q, k) => [p[k][0] + (q[0] - p[k][0]) * t, p[k][1] + (q[1] - p[k][1]) * t]);
  return p[0];
}

// SVG 명세 부록의 끝점 표기를 중심 표기로 바꾸는 식이다.
function arc(x1, y1, rx, ry, degrees, large, sweep, x2, y2, to) {
  rx = Math.abs(rx); ry = Math.abs(ry);
  if (!rx || !ry) return to(x2, y2);
  const phi = (degrees * Math.PI) / 180, cos = Math.cos(phi), sin = Math.sin(phi);
  const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  const px = cos * dx + sin * dy, py = -sin * dx + cos * dy;
  const scale = (px * px) / (rx * rx) + (py * py) / (ry * ry);
  if (scale > 1) { rx *= Math.sqrt(scale); ry *= Math.sqrt(scale); }
  const sign = large === sweep ? -1 : 1;
  const k = sign * Math.sqrt(Math.max(0, (rx * rx * ry * ry - rx * rx * py * py - ry * ry * px * px) / (rx * rx * py * py + ry * ry * px * px)));
  const cxp = (k * rx * py) / ry, cyp = (-k * ry * px) / rx;
  const cx = cos * cxp - sin * cyp + (x1 + x2) / 2, cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
  const angle = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
  const t1 = angle(1, 0, (px - cxp) / rx, (py - cyp) / ry);
  let dt = angle((px - cxp) / rx, (py - cyp) / ry, (-px - cxp) / rx, (-py - cyp) / ry);
  if (!sweep && dt > 0) dt -= 2 * Math.PI;
  if (sweep && dt < 0) dt += 2 * Math.PI;
  const steps = Math.max(8, Math.ceil((Math.abs(dt) * Math.max(rx, ry)) / 2));
  for (let s = 1; s <= steps; s++) {
    const t = t1 + (dt * s) / steps;
    to(cx + rx * Math.cos(t) * cos - ry * Math.sin(t) * sin, cy + rx * Math.cos(t) * sin + ry * Math.sin(t) * cos);
  }
}

// 꺾은선 위에 1px마다 점을 찍는다. 좌표는 이미 그림 전체의 좌표계로 옮긴 것이다.
export function* along(runs, step = 1) {
  for (const { points, closed } of runs) {
    const pts = closed ? [...points, points[0]] : points;
    yield pts[0];
    for (let k = 1; k < pts.length; k++) {
      const [ax, ay] = pts[k - 1], [bx, by] = pts[k];
      const n = Math.max(1, Math.ceil(Math.hypot(bx - ax, by - ay) / step));
      for (let s = 1; s <= n; s++) yield [ax + ((bx - ax) * s) / n, ay + ((by - ay) * s) / n];
    }
  }
}

// 칠한 면은 모든 꺾은선을 닫힌 것으로 보고 even-odd로 판정한다. 그림의 면은 대개 한 겹이라 nonzero와 다르지 않다.
export function inFill(runs, [x, y]) {
  let inside = false;
  for (const { points } of runs) {
    for (let k = 0, j = points.length - 1; k < points.length; j = k++) {
      const [xi, yi] = points[k], [xj, yj] = points[j];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}
