import { StreamLanguage } from "@codemirror/language";
import { classHighlighter, highlightCode, styleTags, tagHighlighter, tags as t } from "@lezer/highlight";
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
export const languageNames = [];
for (const [language, names] of [
  // 이 문법은 데코레이터의 `@`에만 태그를 달아서, 그대로 두면 데코레이터 이름이 일반 변수로 칠해진다.
  [pythonLanguage.configure({ props: [styleTags({ "Decorator/VariableName Decorator/PropertyName": t.meta })] }), "python py"],
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
]) {
  languageNames.push(names.split(" ")[0]);
  for (const n of names.split(" ")) byName.set(n, language);
}

// classHighlighter는 호출하거나 정의한 함수와 내장 이름에 클래스를 붙이지 않는다. 이것이 없으면 줄 대부분에 색이 없다.
export const highlighters = [classHighlighter, tagHighlighter([
  { tag: [t.function(t.variableName), t.function(t.propertyName)], class: "tok-function" },
  { tag: t.standard(t.variableName), class: "tok-builtin" },
  { tag: t.attributeName, class: "tok-decorator" },
])];

export const codeLanguage = (info) => byName.get(info.trim().split(/\s/)[0]?.toLowerCase() ?? "") ?? null;

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
