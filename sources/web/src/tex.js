import AsciiMathParser from "asciimath2tex";

const ascii = new AsciiMathParser();

// 막대가 들어 있지만 막대가 아닌 토큰이다. asciimath2tex가 읽는 순서대로 긴 것부터 둔다.
const barTokens = ["|><|", "|><", "><|", "|->", "|--", "|==", "|__", "__|", "_|_", ":|:", "|~", "~|", "\\|", "||"];
const openers = ["(:", "{:", "<<", "(", "[", "{"];
const closers = [":)", ":}", ">>", ")", "]", "}"];

// asciimath2tex는 짝 없는 `|`를 다음 항 뒤에 오는 아무 막대와 짝짓는다. 그래서 `|X| >= |I| + |J|`에서는
// `X| >= |I`가 `\left|`로 감싸졌고, `|F|: G`의 `|:`는 콜론까지 포함한 괄호로 읽혔다. 여기서는 같은 괄호 안에서
// 앞서 연 막대를 다음 막대가 닫게 하고, 파서가 다르게 짝짓지 못하도록 `|:`와 `:|`로 바꿔 쓴다. 막대 수가 홀수인
// 괄호(`{x | x > 0}`, `a|b`)는 어느 막대가 남는지 추측할 수밖에 없으므로 파서에 맡긴다.
function pairBars(source) {
  const levels = [[]];
  const pairs = [];
  const settle = (bars) => {
    if (bars.length % 2 === 0) for (let i = 0; i < bars.length; i += 2) pairs.push([bars[i], bars[i + 1]]);
  };
  for (let i = 0; i < source.length; ) {
    const rest = source.slice(i);
    if (source[i] === '"') {
      const end = source.indexOf('"', i + 1);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    const text = /^(text|mbox)\s*\(/.exec(rest);
    if (text) {
      let depth = 0, j = i + text[0].length - 1;
      for (; j < source.length; j++) if (source[j] === "(") depth++; else if (source[j] === ")" && --depth === 0) break;
      i = j + 1;
      continue;
    }
    const bars = levels[levels.length - 1];
    if (source[i] === "|" && bars.length % 2 === 1 && !rest.startsWith("||")) {
      bars.push(i++);
      continue;
    }
    const token = barTokens.find((t) => rest.startsWith(t));
    if (token) { i += token.length; continue; }
    const open = rest.startsWith("|:") ? "|:" : openers.find((t) => rest.startsWith(t));
    if (open) { levels.push([]); i += open.length; continue; }
    const close = rest.startsWith(":|") ? ":|" : closers.find((t) => rest.startsWith(t));
    if (close) {
      if (levels.length > 1) settle(levels.pop());
      i += close.length;
      continue;
    }
    if (source[i] === "|") bars.push(i);
    i++;
  }
  while (levels.length) settle(levels.pop());
  if (!pairs.length) return source;
  const marks = new Map(pairs.flatMap(([a, b]) => [[a, " |:"], [b, ":| "]]));
  return source.split("").map((c, i) => marks.get(i) ?? c).join("");
}

export const toTeX = (source, syntax) => (syntax === "asciimath" ? ascii.parse(pairBars(source)) : source);
