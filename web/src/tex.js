// Both note views read a formula through this one function, the edit view in JavaScriptCore (native.js) and the preview
// in its page (math.js), so they never disagree on what a `$…$` says. What each typesetter can't take is fixed after it:
// SwiftMath's gaps in `TeXGaps`, KaTeX's in math.js.
import AsciiMathParser from "asciimath2tex";

const ascii = new AsciiMathParser();

// Tokens with a bar in them that aren't a bar, longest first, as asciimath2tex reads them.
const barTokens = ["|><|", "|><", "><|", "|->", "|--", "|==", "|__", "__|", "_|_", ":|:", "|~", "~|", "\\|", "||"];
const openers = ["(:", "{:", "<<", "(", "[", "{"];
const closers = [":)", ":}", ">>", ")", "]", "}"];

// asciimath2tex pairs a bare `|` with whatever bar comes after the next term, so `|X| >= |I| + |J|` came out with
// `\left|` around `X| >= |I` and `|:` in `|F|: G` read as a bracket that ate the colon. A bar here closes the bar
// opened before it in the same brackets, written out as `|: … :|` so the parser can't pair it otherwise. A bracket
// with an odd number of bars (`{x | x > 0}`, `a|b`) is left for the parser: which bar is the odd one is a guess.
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

/** TeX for a formula written in the note's math syntax (`asciimath` or `latex`). */
export const toTeX = (source, syntax) => (syntax === "asciimath" ? ascii.parse(pairBars(source)) : source);
