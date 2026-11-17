// 노트 그림과 mermaid 도식의 `$…$`를 LaTeX 글자 모양(path)으로 바꾼다. KaTeX는 HTML만 내놓아 SVG 안에 넣을 수 없고,
// 노트 그림은 이미지로 보여서 바깥 글꼴을 불러오지 못한다. 그래서 글자를 path로 내놓는 MathJax의 SVG 출력을 쓴다.
// 페이지 없이 JavaScriptCore에서도 돌도록 DOM 대신 liteAdaptor를 쓴다.
// MathJax는 CommonJS라서 esbuild가 처음 require할 때 실행한다. 노트 페이지는 수식이 든 도식이 있을 때만 MathJax의
// 글꼴 표를 메모리에 올리도록 setup 안에서 require한다.
const packages = ["base", "ams", "newcommand", "noundefined", "boldsymbol", "mhchem", "textmacros", "color", "cancel", "gensymb", "braket"];

let doc = null, adaptor = null;
const cache = new Map();

function setup() {
  const { mathjax } = require("mathjax-full/js/mathjax.js");
  const { TeX } = require("mathjax-full/js/input/tex.js");
  const { SVG } = require("mathjax-full/js/output/svg.js");
  const { liteAdaptor } = require("mathjax-full/js/adaptors/liteAdaptor.js");
  const { RegisterHTMLHandler } = require("mathjax-full/js/handlers/html.js");
  require("mathjax-full/js/input/tex/base/BaseConfiguration.js");
  require("mathjax-full/js/input/tex/ams/AmsConfiguration.js");
  require("mathjax-full/js/input/tex/newcommand/NewcommandConfiguration.js");
  require("mathjax-full/js/input/tex/noundefined/NoUndefinedConfiguration.js");
  require("mathjax-full/js/input/tex/boldsymbol/BoldsymbolConfiguration.js");
  require("mathjax-full/js/input/tex/mhchem/MhchemConfiguration.js");
  require("mathjax-full/js/input/tex/textmacros/TextMacrosConfiguration.js");
  require("mathjax-full/js/input/tex/color/ColorConfiguration.js");
  require("mathjax-full/js/input/tex/cancel/CancelConfiguration.js");
  require("mathjax-full/js/input/tex/gensymb/GensymbConfiguration.js");
  require("mathjax-full/js/input/tex/braket/BraketConfiguration.js");
  adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  // 틀린 TeX를 빨간 글자로 그려 넣지 않고 오류로 돌려준다. 쓰는 쪽이 고쳐야 하기 때문이다.
  const input = new TeX({ packages, formatError: (_, error) => { throw error; } });
  // fontCache none: 글자마다 path를 그 자리에 둔다. 같은 글자를 `<defs>`로 모으는 일은 그림 전체를 보고 한다.
  doc = mathjax.document("", { InputJax: input, OutputJax: new SVG({ fontCache: "none" }) });
}

// `box`는 MathJax의 viewBox(1em = 1000)이고, `body`는 그 안의 요소들이다. 색은 바깥에서 class로 준다.
export function texToSVG(tex) {
  if (cache.has(tex)) return cache.get(tex);
  if (!doc) setup();
  const node = doc.convert(tex, { display: false });
  const svg = adaptor.firstChild(node);
  const box = adaptor.getAttribute(svg, "viewBox").split(/\s+/).map(Number);
  // MathML 노드 이름은 그리는 데 쓰지 않고 그림 파일만 키운다.
  const body = adaptor.innerHTML(svg).replace(/ stroke="currentColor" fill="currentColor"| data-(?:mml-node|mjx-[\w-]+)="[^"]*"/g, "");
  const out = { box, body };
  cache.set(tex, out);
  return out;
}

// 그림 하나에 같은 글자가 여러 번 나오면 path를 `<defs>`에 한 번 두고 `<use>`로 가리킨다. id는 글자 코드와 모양의
// 해시라서, 여러 그림이 한 페이지에 들어가도 같은 id는 같은 글자다.
export function shareGlyphs(markup, glyphs) {
  return markup.replace(/<path data-c="(\w+)" d="([^"]+)"><\/path>/g, (_, code, d) => {
    const id = `mj-${code}-${hash(d)}`;
    glyphs.set(id, `<path id="${id}" d="${d}"/>`);
    return `<use href="#${id}"/>`;
  });
}

function hash(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(36);
}
