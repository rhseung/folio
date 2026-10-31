// The note editor: CodeMirror with Obsidian-style live preview. Markdown syntax stays hidden and rendered except where
// the cursor is; "source" mode shows the raw text. The app talks to it through `window.cb` and the `folio` handler.
import { EditorState, StateField, StateEffect, RangeSetBuilder, Prec } from "@codemirror/state";
import { EditorView, Decoration, WidgetType, BlockWrapper, keymap, drawSelection, dropCursor } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap, indentWithTab, undo, redo } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { syntaxTree, ensureSyntaxTree, syntaxHighlighting, HighlightStyle, indentUnit } from "@codemirror/language";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { tags, classHighlighter } from "@lezer/highlight";
import { renderMath } from "./math.js";
import { codeLanguage } from "./code.js";

// MARK: Syntax the markdown parser doesn't know: $math$, $$math$$ and [[wikilinks]].

const DOLLAR = 36, BRACKET = 91, BANG = 33;

const mathSyntax = {
  defineNodes: [{ name: "InlineMath" }, { name: "BlockMath", block: true }, { name: "MathMark", style: tags.processingInstruction }],
  parseInline: [{
    name: "InlineMath",
    parse(cx, next, pos) {
      if (next !== DOLLAR || cx.char(pos + 1) === DOLLAR || cx.char(pos + 1) === 32) return -1;
      for (let i = pos + 1; i < cx.end; i++) {
        const c = cx.char(i);
        if (c === 92) { i++; continue; }
        if (c === DOLLAR) {
          if (cx.char(i - 1) === 32 || i === pos + 1) return -1;
          return cx.addElement(cx.elt("InlineMath", pos, i + 1, [cx.elt("MathMark", pos, pos + 1), cx.elt("MathMark", i, i + 1)]));
        }
      }
      return -1;
    },
    before: "Escape",
  }],
  parseBlock: [{
    name: "BlockMath",
    parse(cx, line) {
      if (!line.text.slice(line.pos).startsWith("$$")) return false;
      const start = cx.lineStart + line.pos;
      const rest = line.text.slice(line.pos + 2);
      if (rest.trimEnd().endsWith("$$") && rest.trim().length >= 2) {
        cx.addElement(cx.elt("BlockMath", start, cx.lineStart + line.text.length));
        cx.nextLine();
        return true;
      }
      while (cx.nextLine()) {
        if (line.text.trimEnd().endsWith("$$")) {
          const end = cx.lineStart + line.text.length;
          cx.nextLine();
          cx.addElement(cx.elt("BlockMath", start, end));
          return true;
        }
      }
      cx.addElement(cx.elt("BlockMath", start, cx.lineStart));
      return true;
    },
    // `$$` opens display math even right under a line of text, as the reader's math protection reads it.
    endLeaf: (cx, line) => line.text.slice(line.pos).startsWith("$$"),
    before: "FencedCode",
  }],
};

const wikiSyntax = {
  defineNodes: [{ name: "WikiLink", style: tags.link }],
  parseInline: [{
    name: "WikiLink",
    parse(cx, next, pos) {
      const embed = next === BANG && cx.char(pos + 1) === BRACKET && cx.char(pos + 2) === BRACKET;
      if (!embed && !(next === BRACKET && cx.char(pos + 1) === BRACKET)) return -1;
      const open = pos + (embed ? 3 : 2);
      for (let i = open; i < cx.end - 1; i++) {
        if (cx.char(i) === 10) return -1;
        if (cx.char(i) === 93 && cx.char(i + 1) === 93) return i === open ? -1 : cx.addElement(cx.elt("WikiLink", pos, i + 2));
      }
      return -1;
    },
    before: "Link",
  }],
};

// MARK: Widgets

class MathWidget extends WidgetType {
  constructor(source, display, syntax, at) { super(); this.source = source; this.display = display; this.syntax = syntax; this.at = at; }
  eq(o) { return o.source === this.source && o.display === this.display && o.syntax === this.syntax; }
  toDOM(view) {
    const el = document.createElement(this.display ? "div" : "span");
    el.className = this.display ? "cm-math math display" : "cm-math math";
    el.innerHTML = renderMath(this.source, this.display, this.syntax);
    el.addEventListener("mousedown", (e) => { e.preventDefault(); view.dispatch({ selection: { anchor: this.at } }); view.focus(); });
    return el;
  }
  ignoreEvent() { return false; }
}

// Obsidian's size syntax, `![alt|300](src)`: a width in pixels after the last bar. Without it an image takes the column.
export const imageSize = (alt) => {
  const m = /^(.*?)\s*\|\s*(\d+)(?:x\d+)?$/.exec(alt);
  return m ? { alt: m[1], width: Number(m[2]) } : { alt, width: null };
};

class ImageWidget extends WidgetType {
  constructor(src, alt) { super(); this.src = src; this.alt = alt; }
  eq(o) { return o.src === this.src && o.alt === this.alt; }
  toDOM(view) {
    const { alt, width } = imageSize(this.alt);
    const box = document.createElement("span");
    box.className = "cm-image-box";
    const img = document.createElement("img");
    img.className = "cm-image";
    img.alt = alt;
    img.src = this.src;
    if (width) img.style.width = `${width}px`;
    const handle = document.createElement("span");
    handle.className = "cm-image-handle";
    handle.title = "끌어서 크기 조절 · 끝까지 넓히면 본문 폭에 맞춤";
    handle.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      e.stopPropagation();
      handle.setPointerCapture(e.pointerId);
      const startX = e.clientX, startWidth = img.getBoundingClientRect().width;
      const max = box.parentElement.getBoundingClientRect().width;
      box.classList.add("resizing");
      // The image is centered, so its width grows by twice what the corner moves.
      const sized = (x) => Math.round(Math.min(max, Math.max(60, startWidth + 2 * (x - startX))));
      const move = (m) => { img.style.width = `${sized(m.clientX)}px`; };
      const up = (u) => {
        handle.removeEventListener("pointermove", move);
        handle.removeEventListener("pointerup", up);
        box.classList.remove("resizing");
        const w = sized(u.clientX);
        // Positions move as the note is edited, so the image is found from its DOM at the moment of the drop.
        const at = view.posAtDOM(box);
        const m = /^!\[([^\]]*)\]/.exec(view.state.doc.sliceString(at, view.state.doc.lineAt(at).to));
        if (!m) return;
        const base = imageSize(m[1]).alt;
        const next = w >= max - 1 ? base : `${base}|${w}`;
        if (next !== m[1]) view.dispatch({ changes: { from: at + 2, to: at + 2 + m[1].length, insert: next } });
      };
      handle.addEventListener("pointermove", move);
      handle.addEventListener("pointerup", up);
    });
    box.append(img, handle);
    return box;
  }
}

class CheckboxWidget extends WidgetType {
  constructor(checked, at) { super(); this.checked = checked; this.at = at; }
  eq(o) { return o.checked === this.checked && o.at === this.at; }
  toDOM(view) {
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = this.checked;
    box.className = "cm-task";
    box.addEventListener("mousedown", (e) => {
      e.preventDefault();
      view.dispatch({ changes: { from: this.at + 1, to: this.at + 2, insert: this.checked ? " " : "x" } });
    });
    return box;
  }
  ignoreEvent() { return false; }
}

class TextWidget extends WidgetType {
  constructor(text, className, attrs = {}) { super(); this.text = text; this.className = className; this.attrs = attrs; }
  eq(o) { return o.text === this.text && o.className === this.className && JSON.stringify(o.attrs) === JSON.stringify(this.attrs); }
  toDOM() {
    const s = document.createElement("span");
    s.className = this.className;
    s.textContent = this.text;
    for (const [k, v] of Object.entries(this.attrs)) s.setAttribute(k, v);
    return s;
  }
  ignoreEvent() { return false; }
}

class RuleWidget extends WidgetType {
  eq() { return true; }
  toDOM() { const d = document.createElement("div"); d.className = "cm-rule"; return d; }
}

class TableWidget extends WidgetType {
  constructor(source, syntax, at) { super(); this.source = source; this.syntax = syntax; this.at = at; }
  eq(o) { return o.source === this.source && o.syntax === this.syntax; }
  toDOM(view) {
    const rows = this.source.split("\n").filter((l) => l.trim());
    const cells = (l) => l.trim().replace(/^\||\|$/g, "").split(/(?<!\\)\|/).map((c) => c.trim());
    const aligns = cells(rows[1] ?? "").map((c) => (c.startsWith(":") && c.endsWith(":") ? "center" : c.endsWith(":") ? "right" : ""));
    const table = document.createElement("table");
    table.className = "cm-table";
    rows.forEach((row, i) => {
      if (i === 1) return;
      const tr = table.insertRow();
      cells(row).forEach((text, j) => {
        const cell = document.createElement(i === 0 ? "th" : "td");
        cell.innerHTML = inlineHTML(text, this.syntax);
        if (aligns[j]) cell.style.textAlign = aligns[j];
        tr.appendChild(cell);
      });
    });
    table.addEventListener("mousedown", (e) => { e.preventDefault(); view.dispatch({ selection: { anchor: this.at } }); view.focus(); });
    return table;
  }
  ignoreEvent() { return false; }
}

const escapeHTML = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

/** Enough inline markdown for table cells: math, code, bold, italics, strikethrough. */
function inlineHTML(text, syntax) {
  const parts = text.split(/(\$[^$\n]+\$|`[^`\n]+`)/);
  return parts.map((p) => {
    if (/^\$[^$]+\$$/.test(p)) return renderMath(p.slice(1, -1), false, syntax);
    if (/^`[^`]+`$/.test(p)) return `<code>${escapeHTML(p.slice(1, -1))}</code>`;
    return escapeHTML(p)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*])\*(?!\s)(.+?)\*/g, "$1<em>$2</em>")
      .replace(/~~(.+?)~~/g, "<del>$1</del>")
      // A span, not <a>: a click in the table moves the cursor there, and an anchor would also navigate the editor page.
      .replace(/\[([^\]]+)\]\([^)\s]+\)/g, '<span class="cm-link">$1</span>');
  }).join("");
}

// MARK: Live preview

const setSyntax = StateEffect.define();
const setLive = StateEffect.define();
const mathSyntaxField = StateField.define({
  create: () => "latex",
  update: (v, tr) => tr.effects.reduce((a, e) => (e.is(setSyntax) ? e.value : a), v),
});
const setFocused = StateEffect.define();
// Until the editor has focus nothing is "under the cursor", so an opened note reads fully rendered.
const focusedField = StateField.define({
  create: () => false,
  update: (v, tr) => tr.effects.reduce((a, e) => (e.is(setFocused) ? e.value : a), v),
});
const liveField = StateField.define({
  create: () => true,
  update: (v, tr) => tr.effects.reduce((a, e) => (e.is(setLive) ? e.value : a), v),
});

const hide = Decoration.replace({});
// Markup the caret reveals (`## `, `> `) is drawn left of where the text starts, so the text doesn't move under it.
const hang = Decoration.mark({ class: "cm-hang" });
const line = (cls) => Decoration.line({ class: cls });
const CALLOUT = /^\s*>\s*\[!([A-Za-z]+)\]([+-]?)\s?/;
// Mirrors CalloutHeader.numbered: these are counted through the note, unless the title carries its own number.
const NUMBERED = new Set(["definition", "theorem", "lemma", "corollary", "example", "counterexample"]);
const PROVABLE = new Set(["theorem", "lemma", "corollary", "proposition"]);

function buildDecorations(state) {
  if (!state.field(liveField)) return { deco: Decoration.none, wrap: BlockWrapper.set([]), atomic: Decoration.none };
  const syntax = state.field(mathSyntaxField);
  const doc = state.doc;
  const sel = state.field(focusedField) ? state.selection.ranges : [];
  const touches = (from, to) => sel.some((r) => r.from <= to && r.to >= from);
  const onLines = (from, to) => touches(doc.lineAt(from).from, doc.lineAt(to).to);
  const decos = [];
  const add = (from, to, deco) => decos.push(deco.range(from, to));
  // Hidden with the caret on its line, so arrows must step over it whole, or they stop in it unseen.
  const atomic = [];
  const codeLines = new Set();
  const counters = {};
  const wraps = [];
  const wrap = (from, to, attributes) => wraps.push(BlockWrapper.create({ tagName: "div", attributes }).range(doc.lineAt(from).from, doc.lineAt(to).to));
  const calloutType = (n) => (n?.name === "Blockquote" ? CALLOUT.exec(doc.lineAt(n.from).text)?.[1].toLowerCase() : undefined);
  const prevBlock = (n) => { let s = n.prevSibling; while (s?.name === "QuoteMark") s = s.prevSibling; return s; };
  const nextBlock = (n) => { let s = n.nextSibling; while (s?.name === "QuoteMark") s = s.nextSibling; return s; };
  // A proof right under a theorem hangs from it, as the reader's `.callout.attached` (CalloutHeader.provable).
  const attached = (n) => calloutType(n) === "proof" && PROVABLE.has(calloutType(prevBlock(n)));

  const tree = ensureSyntaxTree(state, doc.length, 250) ?? syntaxTree(state);
  tree.iterate({
    enter(node) {
      const { from, to, name } = node;
      switch (name) {
        case "ATXHeading1": case "ATXHeading2": case "ATXHeading3": case "ATXHeading4": case "ATXHeading5": case "ATXHeading6": {
          add(from, from, line(`cm-h cm-h${name.slice(-1)}`));
          return;
        }
        case "HeaderMark": {
          if (doc.lineAt(from).from !== from) return;
          const after = doc.sliceString(to, to + 1) === " " ? to + 1 : to;
          add(from, after, onLines(from, to) ? hang : hide);
          return;
        }
        case "EmphasisMark": case "StrikethroughMark": case "CodeMark": {
          const parent = node.node.parent;
          if (parent && parent.name !== "FencedCode" && !touches(parent.from, parent.to)) add(from, to, hide);
          return;
        }
        case "Escape": {
          if (!touches(from, to)) add(from, from + 1, hide);
          return;
        }
        case "Emphasis": add(from, to, Decoration.mark({ class: "cm-em" })); return;
        case "StrongEmphasis": add(from, to, Decoration.mark({ class: "cm-strong" })); return;
        case "Strikethrough": add(from, to, Decoration.mark({ class: "cm-del" })); return;
        case "InlineCode": add(from, to, Decoration.mark({ class: "cm-inline-code" })); return;
        case "InlineMath": {
          if (!touches(from, to)) add(from, to, Decoration.replace({ widget: new MathWidget(doc.sliceString(from + 1, to - 1), false, syntax, from + 1) }));
          else add(from, to, Decoration.mark({ class: "cm-math-source" }));
          return false;
        }
        case "BlockMath": {
          // Inside a quote every line after the first carries its `>` markers, which aren't part of the TeX.
          const text = doc.sliceString(from, to).replace(/^[ \t]*(?:>[ \t]?)+/gm, "").trim();
          if (!onLines(from, to)) {
            // From the line start: in a quote `$$` follows `> `, which left alone would stay behind as an empty line.
            add(doc.lineAt(from).from, to, Decoration.replace({ widget: new MathWidget(text.slice(2, -2).trim(), true, syntax, from + 2), block: true }));
          } else {
            for (let l = doc.lineAt(from).number; l <= doc.lineAt(to).number; l++) add(doc.line(l).from, doc.line(l).from, line("cm-math-block-source"));
          }
          return false;
        }
        case "Image": {
          if (touches(from, to)) return false;
          const m = /^!\[([^\]]*)\]\((\S+?)(?:\s+"[^"]*")?\)$/.exec(doc.sliceString(from, to));
          if (m) add(from, to, Decoration.replace({ widget: new ImageWidget(m[2], m[1]) }));
          return false;
        }
        case "Link": {
          const text = doc.sliceString(from, to);
          const m = /^\[([^\]]*)\]\((\S*?)(?:\s+"[^"]*")?\)$/.exec(text);
          if (!m) return;
          const live = !touches(from, to);
          add(from, to, Decoration.mark({ class: live ? "cm-link cm-live" : "cm-link", attributes: { "data-href": m[2] } }));
          if (live) {
            add(from, from + 1, hide);
            add(from + 1 + m[1].length, to, hide);
          }
          return false;
        }
        case "URL": {
          if (node.node.parent?.name === "Autolink" || node.node.parent?.name === "Document" || node.node.parent?.name === "Paragraph") {
            add(from, to, Decoration.mark({ class: "cm-link", attributes: { "data-href": doc.sliceString(from, to) } }));
          }
          return;
        }
        case "WikiLink": {
          const raw = doc.sliceString(from, to);
          const embed = raw.startsWith("!");
          const inner = raw.slice(embed ? 3 : 2, -2);
          const [target, alias] = inner.split("|");
          if (!touches(from, to)) {
            const shown = alias ?? target.replace("#", " › ");
            add(from, to, Decoration.replace({ widget: new TextWidget(embed ? `↪ ${shown}` : shown, "cm-link cm-live cm-wikilink", { "data-wiki": target }) }));
          } else {
            add(from, to, Decoration.mark({ class: "cm-link cm-wikilink", attributes: { "data-wiki": target } }));
          }
          return false;
        }
        case "HorizontalRule": {
          if (!onLines(from, to)) add(from, to, Decoration.replace({ widget: new RuleWidget() }));
          // `---` takes the rule's height (editor.css `.cm-rule`), so revealing it moves nothing below.
          else add(doc.lineAt(from).from, doc.lineAt(from).from, Decoration.line({ attributes: { style: "line-height: 24px" } }));
          return;
        }
        case "ListMark": {
          const parent = node.node.parent?.parent;
          const text = doc.sliceString(from, to);
          const row = doc.lineAt(from);
          const lead = /^(?:\s*>)*\s*/.exec(row.text)[0];
          if (row.from + lead.length !== from) return;
          // The reader hangs wrapped lines under the text, a step deeper per nesting level; the line does the same.
          let depth = 0;
          for (let n = node.node.parent; n; n = n.parent) if (n.name === "BulletList" || n.name === "OrderedList") depth++;
          const item = node.node.parent;
          add(row.from, row.from, Decoration.line({ class: depth === 1 && !item.prevSibling ? "cm-li cm-li-first" : "cm-li", attributes: { style: `--depth: ${depth}` } }));
          const end = doc.sliceString(to, to + 1) === " " ? to + 1 : to;
          // The line's padding draws the nesting, so the indent stays hidden with the caret on it too.
          if (from > row.from && !lead.includes(">")) { add(row.from, from, hide); atomic.push(hide.range(row.from, from)); }
          const task = doc.sliceString(to, to + 4).match(/^ \[([ xX])\]/);
          const taskEnd = task && (doc.sliceString(to + 4, to + 5) === " " ? to + 5 : to + 4);
          // Shown, the marker takes the bullet's column, so the item's text stays where it was. A task keeps its
          // checkbox there (raw `[ ] ` is wider) and hangs the `-` left of it; Backspace takes the box whole.
          if (onLines(from, to) && task) {
            add(from, end, hang);
            const box = Decoration.replace({ widget: new CheckboxWidget(task[1] !== " ", to + 1) });
            add(end, taskEnd, box);
            atomic.push(box.range(end, taskEnd));
            return;
          }
          if (onLines(from, to)) return add(from, end, Decoration.mark({ class: "cm-list-mark" }));
          if (task) {
            add(from, taskEnd, Decoration.replace({ widget: new CheckboxWidget(task[1] !== " ", to + 1) }));
          } else if (parent?.name === "BulletList" && /^[-*+]$/.test(text)) {
            add(from, end, Decoration.replace({ widget: new TextWidget("", `cm-bullet cm-bullet-${Math.min(depth, 3)}`) }));
          } else if (parent?.name === "OrderedList") {
            // Numbered from the first item, as the reader (CommonMark) does whatever later items say.
            let index = 0;
            for (let s = item.prevSibling; s; s = s.prevSibling) index++;
            const start = parseInt(doc.sliceString(parent.firstChild.firstChild.from, parent.firstChild.firstChild.to), 10);
            add(from, end, Decoration.replace({ widget: new TextWidget(`${start + index}${text.slice(-1)}`, "cm-bullet cm-ol") }));
          }
          return;
        }
        case "Task": {
          const m = /^\[([xX])\]/.exec(doc.sliceString(from, from + 3));
          if (m) add(from + 3, to, Decoration.mark({ class: "cm-task-done" }));
          return;
        }
        case "Blockquote": {
          const first = doc.lineAt(from);
          const callout = CALLOUT.exec(first.text);
          const active = onLines(from, to);
          // One box around the lines, as the reader's card: per-line tints can't round or pad the block as a whole.
          wrap(from, to, { class: callout ? `cm-callout-box cm-callout-${callout[1].toLowerCase()}${attached(node.node) ? " attached" : ""}${attached(nextBlock(node.node)) ? " has-proof" : ""}` : "cm-quote-box" });
          if (callout) {
            const type = callout[1].toLowerCase();
            let label = type[0].toUpperCase() + type.slice(1);
            let head = callout[0].length;
            if (NUMBERED.has(type)) {
              const own = /^(?:[A-Za-z]+\s+)?(\d+(?:\.\d+)*)\b\s*/.exec(first.text.slice(head));
              if (own) { label += " " + own[1]; head += own[0].length; } else label += " " + (counters[type] = (counters[type] ?? 0) + 1);
            }
            // The head keeps its spacing with its source showing, so the callout's body doesn't jump up a step.
            add(first.from, first.from, line("cm-callout-head"));
            if (!active) {
              add(first.from, first.from + head, Decoration.replace({ widget: new TextWidget(label, "cm-callout-label") }));
              if (first.from + head < first.to) add(first.from + head, first.to, Decoration.mark({ class: "cm-callout-title" }));
            }
          }
          return;
        }
        case "QuoteMark": {
          // Marks on a paragraph's later lines sit inside the paragraph, so the quote is an ancestor, not the parent.
          let quote = node.node.parent;
          while (quote && quote.name !== "Blockquote") quote = quote.parent;
          const lineStart = doc.lineAt(from);
          const isCalloutHead = CALLOUT.test(lineStart.text) && lineStart.from <= from && from <= lineStart.from + lineStart.text.indexOf(">");
          const after = doc.sliceString(to, to + 1) === " " ? to + 1 : to;
          if (quote && !onLines(quote.from, quote.to) && !isCalloutHead) add(from, after, hide);
          // Only the line's first mark hangs: a second would land on top of it.
          else if (quote && onLines(quote.from, quote.to) && /^\s*$/.test(doc.sliceString(lineStart.from, from))) add(from, after, hang);
          return;
        }
        case "FencedCode": {
          const first = doc.lineAt(from).number, last = doc.lineAt(to).number;
          const lang = doc.sliceString(from, doc.lineAt(from).to).replace(/^[`~]+/, "").trim();
          const active = onLines(from, to);
          const closed = last > first && /^\s*(`{3,}|~{3,})\s*$/.test(doc.line(last).text);
          wrap(from, to, { class: "cm-code-box" });
          for (let n = first; n <= last; n++) {
            codeLines.add(n);
            add(doc.line(n).from, doc.line(n).from, line("cm-code"));
          }
          // The fences keep their lines when hidden, so the caret coming in moves nothing: the opening one shows only
          // the language, the closing one nothing.
          if (!active && lang) add(doc.lineAt(from).from, doc.lineAt(from).to, Decoration.replace({ widget: new TextWidget(lang, "cm-code-lang") }));
          else if (!active) add(doc.lineAt(from).from, doc.lineAt(from).to, Decoration.mark({ class: "cm-fence" }));
          if (!active && closed) add(doc.line(last).from, doc.line(last).to, Decoration.mark({ class: "cm-fence" }));
          return false;
        }
        case "Table": {
          if (!onLines(from, to)) {
            add(from, to, Decoration.replace({ widget: new TableWidget(doc.sliceString(from, to), syntax, from), block: true }));
          }
          return false;
        }
      }
    },
  });

  // A trailing `^block-id` names the block for links; the reader doesn't show it (BlockID.pattern).
  for (let n = 1; n <= doc.lines; n++) {
    const l = doc.line(n), m = /\s\^[A-Za-z0-9-]+\s*$/.exec(l.text);
    if (m && !codeLines.has(n) && !touches(l.from, l.to)) add(l.from + m.index, l.to, hide);
  }

  decos.sort((a, b) => a.from - b.from || a.value.startSide - b.value.startSide);
  const builder = new RangeSetBuilder();
  let lastReplaceEnd = -1;
  for (const d of decos) {
    const isReplace = d.value.spec.widget !== undefined || d.value === hide || d.value.spec.block;
    if (isReplace && !d.value.spec.class) {
      if (d.from < lastReplaceEnd) continue;
      lastReplaceEnd = d.to;
    }
    builder.add(d.from, d.to, d.value);
  }
  return { deco: builder.finish(), wrap: BlockWrapper.set(wraps, true), atomic: Decoration.set(atomic, true) };
}

const livePreview = StateField.define({
  create: (state) => buildDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.selection || tr.effects.length || syntaxTree(tr.state) !== syntaxTree(tr.startState)) return buildDecorations(tr.state);
    return deco;
  },
  provide: (f) => [EditorView.decorations.from(f, (v) => v.deco), EditorView.blockWrappers.from(f, (v) => v.wrap),
    EditorView.atomicRanges.of((view) => view.state.field(f).atomic)],
});

// MARK: Keys

// Enter on an empty `- ` or `> ` at the end of a list or quote ends it with a blank line, so what's typed next is a
// paragraph of its own. CodeMirror's own handling leaves the line touching the block, and CommonMark then reads the
// text as part of the last item or the quote.
const MARKER = /^(?:(?:[-*+]|\d+[.)])(?: \[[ xX]\])?|>)[ \t]*$/;
function endBlock(view) {
  const { state } = view, range = state.selection.main;
  if (!state.field(liveField) || state.selection.ranges.length > 1 || !range.empty) return false;
  const line = state.doc.lineAt(range.head);
  if (range.head !== line.to) return false;
  // An empty nested item steps out one level, to its parent's indent, as in Obsidian.
  const nested = /^([ \t]+)(\S.*)$/.exec(line.text);
  if (nested && MARKER.test(nested[2])) {
    for (let n = line.number - 1; n >= 1; n--) {
      const m = /^([ \t]*)(?:[-*+]|\d+[.)])\s/.exec(state.doc.line(n).text);
      if (!m) { if (state.doc.line(n).text.trim() && !/^\s/.test(state.doc.line(n).text)) break; continue; }
      if (m[1].length >= nested[1].length) continue;
      const insert = m[1] + nested[2];
      view.dispatch({ changes: { from: line.from, to: line.to, insert }, selection: { anchor: line.from + insert.length }, userEvent: "input" });
      return true;
    }
  }
  if (!MARKER.test(line.text)) return false;
  const next = line.number < state.doc.lines ? state.doc.line(line.number + 1).text : "";
  if (/^\s*(?:[-*+]|\d+[.)])\s|^\s*>/.test(next)) return false;
  view.dispatch({ changes: { from: line.from, to: line.to, insert: "\n" }, selection: { anchor: line.from + 1 }, scrollIntoView: true, userEvent: "input" });
  return true;
}

// MARK: Look

const highlight = HighlightStyle.define([
  { tag: tags.heading, fontWeight: "700" },
  { tag: tags.strong, fontWeight: "650" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.monospace, fontFamily: "var(--mono)" },
  { tag: [tags.processingInstruction, tags.meta], color: "var(--text-3)" },
  { tag: tags.url, color: "var(--text-3)" },
]);

// MARK: Bridge

const post = (message) => window.webkit?.messageHandlers?.folio?.postMessage(message);

const extensions = [
      history(),
      drawSelection(),
      dropCursor(),
      highlightSelectionMatches(),
      indentUnit.of("    "),
      EditorState.tabSize.of(4),
      EditorView.lineWrapping,
      Prec.high(keymap.of([{ key: "Enter", run: endBlock }])),
      keymap.of([...defaultKeymap, ...historyKeymap, ...searchKeymap, indentWithTab]),
      markdown({ base: markdownLanguage, extensions: [mathSyntax, wikiSyntax], codeLanguages: codeLanguage }),
      syntaxHighlighting(highlight),
      syntaxHighlighting(classHighlighter),
      mathSyntaxField,
      focusedField,
      EditorView.focusChangeEffect.of((_, focusing) => setFocused.of(focusing)),
      liveField,
      livePreview,
      EditorView.updateListener.of((u) => {
        // Sent at once, not debounced: the app saves when the note closes, and a message still waiting then was lost.
        if (u.docChanged) post({ type: "change", text: u.state.doc.toString() });
      }),
      EditorView.domEventHandlers({
        // Files go to the app, which saves them under Notes/assets and inserts the link here. Left to CodeMirror, a
        // dropped image would be read in as text.
        drop(e, v) {
          const files = [...(e.dataTransfer?.files ?? [])];
          if (!files.length) return false;
          e.preventDefault();
          const pos = v.posAtCoords({ x: e.clientX, y: e.clientY }) ?? v.state.selection.main.head;
          sendFiles(files, pos);
          return true;
        },
        paste(e, v) {
          const files = [...(e.clipboardData?.files ?? [])];
          if (!files.length) return false;
          e.preventDefault();
          sendFiles(files, v.state.selection.main.head);
          return true;
        },
        // A rendered link opens on click; once the cursor is inside it (raw text showing), ⌘-click opens it.
        mousedown(e, v) {
          const link = e.target.closest?.("[data-href], [data-wiki]");
          if (!link || !(link.classList.contains("cm-live") || e.metaKey)) return false;
          post(link.dataset.wiki !== undefined ? { type: "open", wiki: link.dataset.wiki } : { type: "open", href: link.dataset.href });
          e.preventDefault();
          return true;
        },
      }),
];

function sendFiles(files, pos) {
  for (const file of files) {
    const reader = new FileReader();
    reader.onload = () => post({ type: "file", name: file.name || `Pasted ${new Date().toISOString().slice(0, 19).replace(/[T:]/g, "-")}.png`,
      data: String(reader.result).split(",")[1] ?? "", pos });
    reader.readAsDataURL(file);
  }
}

const view = new EditorView({ parent: document.getElementById("editor"), state: EditorState.create({ doc: "", extensions }) });

// WebKit fires `drop` only where `dragover` was cancelled, which the blank page under a short note didn't do; and a
// drop it handles itself inserts its own markup (a broken image for a file it can't read). So every drag is taken here.
document.addEventListener("dragover", (e) => {
  e.preventDefault();
  if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
});
// The page under the note isn't the editor, and the browser put a click there at the end of the nearest line with text.
// Below the note means after it.
document.addEventListener("mousedown", (e) => {
  if (e.button !== 0 || view.dom.contains(e.target) || e.clientY < view.contentDOM.getBoundingClientRect().bottom) return;
  e.preventDefault();
  view.dispatch({ selection: { anchor: view.state.doc.length }, scrollIntoView: true });
  view.focus();
});
document.addEventListener("drop", (e) => {
  if (e.defaultPrevented) return;
  e.preventDefault();
  const pos = view.posAtCoords({ x: e.clientX, y: e.clientY }) ?? view.state.doc.length;
  const files = [...(e.dataTransfer?.files ?? [])];
  const text = e.dataTransfer?.getData("text/plain");
  if (files.length) sendFiles(files, pos);
  else if (text) window.cb.insertAt(pos, text);
});

window.cb = {
  /** Replaces the whole text without an undo step, as when a note is opened. */
  load({ text, syntax, live }) {
    view.setState(EditorState.create({ doc: text, extensions }));
    view.dispatch({ effects: [setSyntax.of(syntax ?? "latex"), setLive.of(live ?? true)] });
  },
  setSyntax(syntax) { view.dispatch({ effects: setSyntax.of(syntax) }); },
  setLive(live) { view.dispatch({ effects: setLive.of(live) }); },
  insert(text) {
    const { from, to } = view.state.selection.main;
    view.dispatch({ changes: { from, to, insert: text }, selection: { anchor: from + text.length }, scrollIntoView: true });
    view.focus();
  },
  /** Inserts where a drop the app took natively landed, in page coordinates. */
  insertAtPoint(x, y, text) { window.cb.insertAt(view.posAtCoords({ x, y }) ?? view.state.doc.length, text); },
  /** Inserts at a position from an earlier message (a drop point), mapped through edits made since. */
  insertAt(pos, text) {
    const at = Math.min(pos, view.state.doc.length);
    const lead = at > 0 && view.state.doc.sliceString(at - 1, at) !== "\n" && text.startsWith("!") ? "\n" : "";
    view.dispatch({ changes: { from: at, insert: lead + text }, selection: { anchor: at + lead.length + text.length }, scrollIntoView: true });
    view.focus();
  },
  text: () => view.state.doc.toString(),
  focus: () => view.focus(),
  undo: () => undo(view),
  redo: () => redo(view),
  // For app-tests' layout checks: a web view with no window never takes focus, so they set the focus state directly.
  debug: { view, tree: () => ensureSyntaxTree(view.state, view.state.doc.length, 1000), focus: (on) => view.dispatch({ effects: setFocused.of(on) }) },
};

post({ type: "ready" });
