// Run by the app in JavaScriptCore, with no page: AsciiMath to TeX for SwiftMath, code colors for the note views, and
// the code languages the edit view offers.
import { highlightCode } from "@lezer/highlight";
import { codeLanguage, highlighters, languageNames } from "./code.js";

export const languages = () => languageNames;

export { toTeX } from "./tex.js";

// Flat [from, to, class, ...] in UTF-16 units, which NSRange counts in too.
export function highlight(code, info) {
  const language = codeLanguage(info);
  if (!language) return [];
  const out = [];
  let pos = 0;
  highlightCode(code, language.parser.parse(code), highlighters,
    (text, cls) => { if (cls) out.push(pos, pos + text.length, cls); pos += text.length; },
    () => { pos += 1; });
  return out;
}
