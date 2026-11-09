import katex from "katex";
import { toTeX } from "./tex.js";

const textCommand = /\\(text|textrm|textbf|textit|texttt|textsf|mbox)\s*\{([^{}]*)\}/g;

// TeX reads `%` as a comment and `#` and `&` as markup even inside `\text{…}`, so the formula fails; a note that writes
// them there means the characters, as the edit view shows them. AsciiMath copies quoted text (`"# paths"`) into
// `\text{…}` as it is, so this runs after either syntax.
const textAsWritten = (tex) => tex.replace(textCommand, (_, command, body) => `\\${command}{${body.replace(/(?<!\\)[%#&]/g, "\\$&")}}`);

/** KaTeX HTML; a formula that fails shows its source marked as an error instead of breaking the page. */
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
