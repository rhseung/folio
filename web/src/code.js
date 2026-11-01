// Code block languages, shared so the reader and the editor color code the same way.
import { StreamLanguage } from "@codemirror/language";
import { classHighlighter, highlightCode, tagHighlighter, tags as t } from "@lezer/highlight";
import { pythonLanguage } from "@codemirror/lang-python";
import { cppLanguage } from "@codemirror/lang-cpp";
import { javaLanguage } from "@codemirror/lang-java";
import { javascriptLanguage, typescriptLanguage } from "@codemirror/lang-javascript";
import { rustLanguage } from "@codemirror/lang-rust";
import { goLanguage } from "@codemirror/lang-go";
import { StandardSQL } from "@codemirror/lang-sql";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { stex } from "@codemirror/legacy-modes/mode/stex";
import { swift } from "@codemirror/legacy-modes/mode/swift";

const byName = new Map();
for (const [language, names] of [
  [pythonLanguage, "python py"],
  [cppLanguage, "cpp c++ c h hpp cc"],
  [javaLanguage, "java"],
  [javascriptLanguage, "javascript js jsx mjs"],
  [typescriptLanguage, "typescript ts"],
  [rustLanguage, "rust rs"],
  [goLanguage, "go golang"],
  [StandardSQL.language, "sql"],
  [StreamLanguage.define(shell), "bash sh shell zsh console"],
  [StreamLanguage.define(stex), "latex tex"],
  [StreamLanguage.define(swift), "swift"],
]) for (const n of names.split(" ")) byName.set(n, language);

// classHighlighter leaves called and defined functions and builtins as plain names, which leaves most of a line uncolored.
export const highlighters = [classHighlighter, tagHighlighter([
  { tag: [t.function(t.variableName), t.function(t.propertyName)], class: "tok-function" },
  { tag: t.standard(t.variableName), class: "tok-builtin" },
])];

export const codeLanguage = (info) => byName.get(info.trim().split(/\s/)[0]?.toLowerCase() ?? "") ?? null;

// Same tok-* classes as the editor's code lines, so note.css colors both.
export function highlightBlocks(root) {
  for (const code of root.querySelectorAll("pre[data-lang] > code")) {
    const language = codeLanguage(code.parentElement.dataset.lang);
    if (!language) continue;
    const text = code.textContent, out = document.createDocumentFragment();
    highlightCode(text, language.parser.parse(text), highlighters,
      (s, cls) => { const node = document.createTextNode(s); if (!cls) return out.append(node); const span = document.createElement("span"); span.className = cls; span.append(node); out.append(span); },
      () => out.append("\n"));
    code.replaceChildren(out);
  }
}
