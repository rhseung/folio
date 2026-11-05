import katex from "katex";
import AsciiMathParser from "asciimath2tex";

const ascii = new AsciiMathParser();

const textCommand = /\\(text|textrm|textbf|textit|texttt|textsf|mbox)\s*\{([^{}]*)\}/g;

// TeX reads `%` as a comment and `#` and `&` as markup even inside `\text{…}`, so the formula fails; a note that writes
// them there means the characters, as the edit view shows them.
const textAsWritten = (tex) => tex.replace(textCommand, (_, command, body) => `\\${command}{${body.replace(/(?<!\\)[%#&]/g, "\\$&")}}`);

/** TeX for a formula written in the note's math syntax (`asciimath` or `latex`). */
export function toTeX(source, syntax) {
  return syntax === "asciimath" ? ascii.parse(source) : textAsWritten(source);
}

/** KaTeX HTML; a formula that fails shows its source marked as an error instead of breaking the page. */
export function renderMath(source, display, syntax) {
  try {
    return katex.renderToString(toTeX(source, syntax), { displayMode: display, throwOnError: true, output: "htmlAndMathml", strict: "ignore" });
  } catch (error) {
    const span = document.createElement("span");
    span.className = "math-error";
    span.title = String(error.message ?? error);
    span.textContent = source;
    return span.outerHTML;
  }
}
