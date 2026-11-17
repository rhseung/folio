// 노트 그림을 고치고 검사하려고 SVG를 나무로 읽는다. JavaScriptCore에는 DOMParser가 없다. 그림이 올바른 XML인지는
// 쓰기 전에 Swift의 XMLParser가 따로 보므로, 여기서는 읽은 그대로 다시 쓸 수 있을 만큼만 읽는다.
const entities = { lt: "<", gt: ">", amp: "&", quot: '"', apos: "'" };

export const decode = (s) =>
  s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) =>
    e[0] === "#" ? String.fromCodePoint(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : +e.slice(1)) : entities[e] ?? m);

export const escapeText = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escapeAttr = (s) => escapeText(s).replace(/"/g, "&quot;");

export function parse(source) {
  const root = { t: "doc", kids: [] };
  const stack = [root];
  let i = 0;
  const top = () => stack[stack.length - 1];
  const add = (node) => { node.parent = top(); top().kids.push(node); };
  while (i < source.length) {
    if (source[i] !== "<") {
      const end = source.indexOf("<", i);
      const raw = source.slice(i, end < 0 ? source.length : end);
      add({ t: "text", raw });
      i += raw.length;
      continue;
    }
    const special = [["<!--", "-->"], ["<![CDATA[", "]]>"], ["<?", "?>"], ["<!", ">"]].find(([open]) => source.startsWith(open, i));
    if (special) {
      const [open, close] = special;
      const end = source.indexOf(close, i + open.length);
      if (end < 0) throw new Error("unclosed " + open);
      add({ t: open === "<![CDATA[" ? "cdata" : "raw", raw: source.slice(i, end + close.length) });
      i = end + close.length;
      continue;
    }
    if (source[i + 1] === "/") {
      const end = source.indexOf(">", i);
      const name = source.slice(i + 2, end).trim();
      if (top().name !== name) throw new Error(`</${name}> closes <${top().name}>`);
      stack.pop();
      i = end + 1;
      continue;
    }
    const m = /^<([\w:.-]+)/.exec(source.slice(i, i + 200));
    if (!m) throw new Error("bad tag at " + i);
    const el = { t: "el", name: m[1], attrs: [], kids: [] };
    i += m[0].length;
    const attr = /\s*([\w:.-]+)\s*=\s*("([^"]*)"|'([^']*)')|\s*(\/?>)/y;
    for (;;) {
      attr.lastIndex = i;
      const a = attr.exec(source);
      if (!a) throw new Error(`bad attribute in <${el.name}>`);
      i = attr.lastIndex;
      if (a[5]) {
        add(el);
        if (a[5] === ">") stack.push(el);
        break;
      }
      el.attrs.push([a[1], decode(a[3] ?? a[4])]);
    }
  }
  if (stack.length > 1) throw new Error(`<${top().name}> is not closed`);
  return root;
}

export function serialize(node) {
  if (node.t === "doc") return node.kids.map(serialize).join("");
  if (node.t !== "el") return node.raw;
  const attrs = node.attrs.map(([k, v]) => ` ${k}="${escapeAttr(v)}"`).join("");
  if (!node.kids.length) return `<${node.name}${attrs}/>`;
  return `<${node.name}${attrs}>${node.kids.map(serialize).join("")}</${node.name}>`;
}

export const attr = (el, name) => el.attrs.find(([k]) => k === name)?.[1];
export const classes = (el) => (attr(el, "class") ?? "").split(/\s+/).filter(Boolean);
export const local = (name) => name.slice(name.indexOf(":") + 1);

export function setAttr(el, name, value) {
  const found = el.attrs.find(([k]) => k === name);
  if (found) found[1] = value;
  else el.attrs.push([name, value]);
}

export function* walk(node) {
  for (const kid of node.kids ?? []) {
    if (kid.t !== "el") continue;
    yield kid;
    yield* walk(kid);
  }
}

export const elements = (node) => node.kids.filter((k) => k.t === "el");

export function textOf(node) {
  if (node.t === "text") return decode(node.raw);
  if (node.t === "cdata") return node.raw.slice(9, -3);
  return (node.kids ?? []).map(textOf).join("");
}

export function replace(node, ...nodes) {
  const kids = node.parent.kids;
  for (const n of nodes) n.parent = node.parent;
  kids.splice(kids.indexOf(node), 1, ...nodes);
}

export function ancestors(node) {
  const out = [];
  for (let p = node.parent; p && p.t === "el"; p = p.parent) out.push(p);
  return out;
}
