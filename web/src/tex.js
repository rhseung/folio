// Both note views read a formula through this one function, the edit view in JavaScriptCore (native.js) and the preview
// in its page (math.js), so they never disagree on what a `$…$` says. What each typesetter can't take is fixed after it:
// SwiftMath's gaps in `TeXGaps`, KaTeX's in math.js.
import AsciiMathParser from "asciimath2tex";

const ascii = new AsciiMathParser();

/** TeX for a formula written in the note's math syntax (`asciimath` or `latex`). */
export const toTeX = (source, syntax) => (syntax === "asciimath" ? ascii.parse(source) : source);
