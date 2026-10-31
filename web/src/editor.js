// The note editor: CodeMirror showing the markdown source, styled (see "Styled source"). The rendered note is the
// reader beside it. The app talks to it through `window.cb` and the `folio` handler.
import { EditorState, StateField, StateEffect, RangeSetBuilder, Prec } from "@codemirror/state";
import { EditorView, Decoration, WidgetType, BlockWrapper, keymap, drawSelection, dropCursor, showTooltip } from "@codemirror/view";
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
  constructor(source, display, syntax) { super(); this.source = source; this.display = display; this.syntax = syntax; }
  eq(o) { return o.source === this.source && o.display === this.display && o.syntax === this.syntax; }
  toDOM() {
    const el = document.createElement(this.display ? "div" : "span");
    el.className = this.display ? "cm-math math display" : "cm-math math";
    el.innerHTML = renderMath(this.source, this.display, this.syntax);
    return el;
  }
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
        // Positions move as the note is edited, so the image is found at the moment of the drop: in the line the
        // picture is drawn under, by its source.
        const row = view.state.doc.lineAt(Math.max(0, view.posAtDOM(box) - 1));
        const m = new RegExp(`!\\[([^\\]]*)\\]\\(${this.src.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`).exec(row.text);
        if (!m) return;
        const base = imageSize(m[1]).alt, at = row.from + m.index;
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

// MARK: Styled source

const setSyntax = StateEffect.define();
const mathSyntaxField = StateField.define({
  create: () => "latex",
  update: (v, tr) => tr.effects.reduce((a, e) => (e.is(setSyntax) ? e.value : a), v),
});
const setFocused = StateEffect.define();
// An opened note has no caret yet, so the math bubble waits for focus.
const focusedField = StateField.define({
  create: () => false,
  update: (v, tr) => tr.effects.reduce((a, e) => (e.is(setFocused) ? e.value : a), v),
});

// Markdown's marks stay in the text, dimmed, and the text after them takes the style. The caret walks the raw text:
// no mark is hidden, hung in the margin or set in a column of its own, and every line starts at the same x, so a
// line's start is where it looks like it is (docs/SPEC.md "편집 방식"). What is drawn rendered sits below its line
// or floats over the text.
const dim = Decoration.mark({ class: "cm-mark" });
const line = (cls) => Decoration.line({ class: cls });
const CALLOUT = /^\s*>\s*\[!([A-Za-z]+)\]([+-]?)/;

function buildDecorations(state) {
  const syntax = state.field(mathSyntaxField);
  const doc = state.doc;
  const decos = [];
  const add = (from, to, deco) => decos.push(deco.range(from, to));
  const wraps = [];
  const wrap = (from, to, attributes) => wraps.push(BlockWrapper.create({ tagName: "div", attributes }).range(doc.lineAt(from).from, doc.lineAt(to).to));
  // Drawn under the line, so the source above keeps its place.
  const below = (pos, widget) => add(doc.lineAt(pos).to, doc.lineAt(pos).to, Decoration.widget({ widget, block: true, side: 1 }));
  const codeLines = new Set();

  const tree = ensureSyntaxTree(state, doc.length, 250) ?? syntaxTree(state);
  tree.iterate({
    enter(node) {
      const { from, to, name } = node;
      switch (name) {
        case "ATXHeading1": case "ATXHeading2": case "ATXHeading3": case "ATXHeading4": case "ATXHeading5": case "ATXHeading6":
          add(from, from, line(`cm-h cm-h${name.slice(-1)}`));
          return;
        case "HeaderMark": {
          add(from, to, dim);
          return;
        }
        case "EmphasisMark": case "StrikethroughMark": case "CodeMark": case "MathMark":
          add(from, to, dim);
          return;
        case "Escape": add(from, from + 1, dim); return;
        case "Emphasis": add(from, to, Decoration.mark({ class: "cm-em" })); return;
        case "StrongEmphasis": add(from, to, Decoration.mark({ class: "cm-strong" })); return;
        case "Strikethrough": add(from, to, Decoration.mark({ class: "cm-del" })); return;
        case "InlineCode": add(from, to, Decoration.mark({ class: "cm-inline-code" })); return;
        case "InlineMath": add(from, to, Decoration.mark({ class: "cm-math-source" })); return;
        case "BlockMath": {
          // Inside a quote every line after the first carries its `>` markers, which aren't part of the TeX.
          const text = doc.sliceString(from, to).replace(/^[ \t]*(?:>[ \t]?)+/gm, "").trim();
          for (let l = doc.lineAt(from).number; l <= doc.lineAt(to).number; l++) add(doc.line(l).from, doc.line(l).from, line("cm-math-block-source"));
          if (text.length > 4 && text.endsWith("$$")) below(to, new MathWidget(text.slice(2, -2).trim(), true, syntax));
          return false;
        }
        case "Image": {
          const m = /^!\[([^\]]*)\]\((\S+?)(?:\s+"[^"]*")?\)$/.exec(doc.sliceString(from, to));
          add(from, to, Decoration.mark({ class: "cm-image-source" }));
          if (m) below(to, new ImageWidget(m[2], m[1]));
          return false;
        }
        case "Link": {
          const m = /^\[([^\]]*)\]\((\S*?)(?:\s+"[^"]*")?\)$/.exec(doc.sliceString(from, to));
          if (!m) return;
          add(from, to, Decoration.mark({ class: "cm-link", attributes: { "data-href": m[2] } }));
          add(from, from + 1, dim);
          add(from + 1 + m[1].length, to, dim);
          return false;
        }
        case "URL": {
          const parent = node.node.parent?.name;
          if (parent === "Autolink" || parent === "Document" || parent === "Paragraph") {
            add(from, to, Decoration.mark({ class: "cm-link", attributes: { "data-href": doc.sliceString(from, to) } }));
          }
          return;
        }
        case "WikiLink": {
          const raw = doc.sliceString(from, to), open = raw.startsWith("!") ? 3 : 2;
          add(from, to, Decoration.mark({ class: "cm-link cm-wikilink", attributes: { "data-wiki": raw.slice(open, -2).split("|")[0] } }));
          add(from, from + open, dim);
          add(to - 2, to, dim);
          return false;
        }
        case "HorizontalRule": add(from, to, dim); return;
        case "ListMark": {
          add(from, to, Decoration.mark({ class: "cm-list-mark" }));
          // A click on `[ ]` ticks it.
          if (/^ \[[ xX]\]/.test(doc.sliceString(to, to + 4))) add(to + 1, to + 4, Decoration.mark({ class: "cm-task-mark" }));
          return;
        }
        case "Task":
          if (/^\[[xX]\]/.test(doc.sliceString(from, from + 3))) add(from + 3, to, Decoration.mark({ class: "cm-task-done" }));
          return;
        case "Blockquote": {
          const first = doc.lineAt(from), callout = CALLOUT.exec(first.text);
          wrap(from, to, { class: callout ? `cm-callout-box cm-callout-${callout[1].toLowerCase()}` : "cm-quote-box" });
          if (callout) {
            const type = first.from + first.text.indexOf("[!");
            add(type, first.from + callout[0].length, Decoration.mark({ class: "cm-callout-type" }));
            if (first.from + callout[0].length < first.to) add(first.from + callout[0].length, first.to, Decoration.mark({ class: "cm-callout-title" }));
          }
          return;
        }
        case "QuoteMark": {
          add(from, to, dim);
          return;
        }
        case "FencedCode": {
          const first = doc.lineAt(from), last = doc.lineAt(to);
          wrap(from, to, { class: "cm-code-box" });
          for (let n = first.number; n <= last.number; n++) {
            codeLines.add(n);
            add(doc.line(n).from, doc.line(n).from, line("cm-code"));
          }
          add(first.from, first.to, dim);
          if (last.number > first.number && /^\s*(`{3,}|~{3,})\s*$/.test(last.text)) add(last.from, last.to, dim);
          return false;
        }
        case "Table":
          for (let l = doc.lineAt(from).number; l <= doc.lineAt(to).number; l++) add(doc.line(l).from, doc.line(l).from, line("cm-table-source"));
          return false;
      }
    },
  });

  // A trailing `^block-id` names the block for links; the reader doesn't show it (BlockID.pattern).
  for (let n = 1; n <= doc.lines; n++) {
    const l = doc.line(n), m = /\s\^[A-Za-z0-9-]+\s*$/.exec(l.text);
    if (m && !codeLines.has(n)) add(l.from + m.index, l.to, dim);
  }

  decos.sort((a, b) => a.from - b.from || a.value.startSide - b.value.startSide);
  const builder = new RangeSetBuilder();
  for (const d of decos) builder.add(d.from, d.to, d.value);
  return { deco: builder.finish(), wrap: BlockWrapper.set(wraps, true) };
}

const styledSource = StateField.define({
  create: (state) => buildDecorations(state),
  update(deco, tr) {
    if (tr.docChanged || tr.effects.some((e) => e.is(setSyntax)) || syntaxTree(tr.state) !== syntaxTree(tr.startState)) return buildDecorations(tr.state);
    return deco;
  },
  provide: (f) => [EditorView.decorations.from(f, (v) => v.deco), EditorView.blockWrappers.from(f, (v) => v.wrap)],
});

// Inline math stays source; with the caret in it, its rendering floats under the line, over the text, which keeps its
// place.
function mathTip(state) {
  const { head, empty } = state.selection.main;
  if (!state.field(focusedField) || !empty) return null;
  let node = syntaxTree(state).resolveInner(head, -1);
  while (node && node.name !== "InlineMath") node = node.parent;
  if (!node || head <= node.from) return null;
  const tex = state.doc.sliceString(node.from + 1, node.to - 1), syntax = state.field(mathSyntaxField);
  return {
    pos: node.from,
    create: () => {
      const dom = document.createElement("div");
      dom.className = "cm-math-tip";
      dom.innerHTML = renderMath(tex, false, syntax);
      return { dom };
    },
  };
}
const mathTipField = StateField.define({
  create: mathTip,
  update: (tip, tr) => (tr.docChanged || tr.selection || tr.effects.length ? mathTip(tr.state) : tip),
  provide: (f) => showTooltip.from(f),
});

// MARK: Keys

// Enter on an empty `- ` or `> ` at the end of a list or quote ends it with a blank line, so what's typed next is a
// paragraph of its own. CodeMirror's own handling leaves the line touching the block, and CommonMark then reads the
// text as part of the last item or the quote.
const MARKER = /^(?:(?:[-*+]|\d+[.)])(?: \[[ xX]\])?|>)[ \t]*$/;
function endBlock(view) {
  const { state } = view, range = state.selection.main;
  if (state.selection.ranges.length > 1 || !range.empty) return false;
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
      styledSource,
      mathTipField,
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
        // A click on a task's `[ ]` ticks it; links open on ⌘-click, as a plain click puts the caret in their source.
        mousedown(e, v) {
          const task = e.button === 0 && !e.metaKey && !e.shiftKey ? e.target.closest?.(".cm-task-mark") : null;
          if (task) {
            const at = v.posAtDOM(task) + 1, done = v.state.doc.sliceString(at, at + 1) !== " ";
            v.dispatch({ changes: { from: at, to: at + 1, insert: done ? " " : "x" } });
            e.preventDefault();
            return true;
          }
          const link = e.target.closest?.("[data-href], [data-wiki]");
          if (!link || !e.metaKey) return false;
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
// The preview beside the editor follows its top line, once a frame.
let scrollQueued = false;
window.addEventListener("scroll", () => {
  if (scrollQueued) return;
  scrollQueued = true;
  requestAnimationFrame(() => {
    scrollQueued = false;
    const h = Math.max(0, -view.documentTop), block = view.lineBlockAtHeight(h);
    post({ type: "scroll", line: view.state.doc.lineAt(block.from).number, frac: block.height ? Math.min(1, (h - block.top) / block.height) : 0 });
  });
}, { passive: true });
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
  load({ text, syntax }) {
    view.setState(EditorState.create({ doc: text, extensions }));
    view.dispatch({ effects: setSyntax.of(syntax ?? "latex") });
  },
  setSyntax(syntax) { view.dispatch({ effects: setSyntax.of(syntax) }); },
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
