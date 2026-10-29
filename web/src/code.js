// Code block languages, shared so the reader and the editor color code the same way.
import { StreamLanguage } from "@codemirror/language";
import { classHighlighter, highlightCode } from "@lezer/highlight";
import { pythonLanguage } from "@codemirror/lang-python";
import { cppLanguage } from "@codemirror/lang-cpp";
import { javaLanguage } from "@codemirror/lang-java";
import { javascriptLanguage, typescriptLanguage } from "@codemirror/lang-javascript";
import { rustLanguage } from "@codemirror/lang-rust";
import { goLanguage } from "@codemirror/lang-go";
import { StandardSQL } from "@codemirror/lang-sql";
import { shell } from "@codemirror/legacy-modes/mode/shell";
import { stex } from "@codemirror/legacy-modes/mode/stex";

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
]) for (const n of names.split(" ")) byName.set(n, language);

export const codeLanguage = (info) => byName.get(info.trim().split(/\s/)[0]?.toLowerCase() ?? "") ?? null;

// Same tok-* classes as the editor's code lines, so note.css colors both.
export function highlightBlocks(root) {
  for (const code of root.querySelectorAll("pre[data-lang] > code")) {
    const language = codeLanguage(code.parentElement.dataset.lang);
    if (!language) continue;
    const text = code.textContent, out = document.createDocumentFragment();
    highlightCode(text, language.parser.parse(text), classHighlighter,
      (s, cls) => { const node = document.createTextNode(s); if (!cls) return out.append(node); const span = document.createElement("span"); span.className = cls; span.append(node); out.append(span); },
      () => out.append("\n"));
    code.replaceChildren(out);
  }
}
