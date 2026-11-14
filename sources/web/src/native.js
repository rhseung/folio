// 앱은 이 파일을 페이지 없이 JavaScriptCore에서 실행한다. 그래서 수식은 여기서 그리지 않고, 편집 보기도 미리보기의
// KaTeX로 페이지에서 그린다(NoteMath).
import { highlightCode } from "@lezer/highlight";
import { codeLanguage, highlighters, languageNames } from "./code.js";

export const languages = () => languageNames;

// [from, to, class, ...]를 이어 붙인 배열을 돌려준다. 위치는 NSRange와 같은 UTF-16 단위로 센다.
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
