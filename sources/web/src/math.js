import katex from "katex";
import { toTeX } from "./tex.js";

const textCommand = /\\(text|textrm|textbf|textit|texttt|textsf|mbox)\s*\{([^{}]*)\}/g;

// TeX는 `\text{}` 안에서도 `%`를 주석으로, `#`과 `&`를 마크업으로 읽어서 수식이 실패한다. 노트가 그 자리에 쓴 것은
// 편집 보기가 보여 주는 대로 문자 그대로를 뜻한다. AsciiMath도 따옴표 안의 글(`"# paths"`)을 그대로 `\text{}`에
// 옮기므로, 이 변환은 두 문법 모두 TeX로 바꾼 뒤에 한다.
const textAsWritten = (tex) => tex.replace(textCommand, (_, command, body) => `\\${command}{${body.replace(/(?<!\\)[%#&]/g, "\\$&")}}`);

// KaTeX는 식 번호를 `position: absolute; right: 0`으로 놓아 폭 계산에서 뺀다. 그래서 식이 칸보다 넓거나 상자가 식에 맞춰
// 좁아지면(편집 보기의 말풍선) 번호가 식 끝 위에 겹친다. 번호를 뺀 나머지를 `.katex-body` 하나로 묶어 두면 note.css가 식과
// 번호를 나란한 두 칸에 놓을 수 있다.
function setTagApart(html) {
  if (!html.includes("katex-tag")) return html;
  const box = document.createElement("template");
  box.innerHTML = html;
  for (const line of box.content.querySelectorAll(".katex-display > .katex > .katex-html")) {
    const tag = line.querySelector(":scope > .katex-tag");
    if (!tag) continue;
    const body = document.createElement("span");
    body.className = "katex-body";
    body.append(...[...line.childNodes].filter((node) => node !== tag));
    line.prepend(body);
    line.classList.add("tagged");
  }
  return box.innerHTML;
}

export function renderMath(source, display, syntax) {
  try {
    const html = katex.renderToString(textAsWritten(toTeX(source, syntax)), { displayMode: display, throwOnError: true, output: "htmlAndMathml", strict: "ignore" });
    return display ? setTagApart(html) : html;
  } catch (error) {
    const span = document.createElement("span");
    span.className = "math-error";
    span.title = String(error.message ?? error);
    span.textContent = source;
    return span.outerHTML;
  }
}
