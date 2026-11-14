import katex from "katex";
import { toTeX } from "./tex.js";

const textCommand = /\\(text|textrm|textbf|textit|texttt|textsf|mbox)\s*\{([^{}]*)\}/g;

// TeX는 `\text{}` 안에서도 `%`를 주석으로, `#`과 `&`를 마크업으로 읽어서 수식이 실패한다. 노트가 그 자리에 쓴 것은
// 편집 보기가 보여 주는 대로 문자 그대로를 뜻한다. AsciiMath도 따옴표 안의 글(`"# paths"`)을 그대로 `\text{}`에
// 옮기므로, 이 변환은 두 문법 모두 TeX로 바꾼 뒤에 한다.
const textAsWritten = (tex) => tex.replace(textCommand, (_, command, body) => `\\${command}{${body.replace(/(?<!\\)[%#&]/g, "\\$&")}}`);

export function renderMath(source, display, syntax) {
  try {
    return katex.renderToString(textAsWritten(toTeX(source, syntax)), { displayMode: display, throwOnError: true, output: "htmlAndMathml", strict: "ignore" });
  } catch (error) {
    const span = document.createElement("span");
    span.className = "math-error";
    span.title = String(error.message ?? error);
    span.textContent = source;
    return span.outerHTML;
  }
}
