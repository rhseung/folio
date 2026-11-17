// 페이지가 파일에 접근하지 않고도 글꼴을 쓰도록 KaTeX 글꼴은 woff2만 data URL로 넣는다.
import { build } from "esbuild";
import { readFile } from "node:fs/promises";
import * as mermaidPatch from "./patches/beautiful-mermaid.mjs";

const out = "../../app/resources/web";
// 그림 엔진과 위젯 kit은 앱과 CLI가 함께 쓰므로 FolioActions의 리소스로 둔다.
const actions = "../../sources/actions/notes";
const common = { bundle: true, minify: true, target: "safari18", legalComments: "eof", logLevel: "warning" };
const fonts = { ".woff2": "dataurl", ".woff": "empty", ".ttf": "empty" };

const patched = {
  name: "beautiful-mermaid-patch",
  setup(b) {
    b.onLoad({ filter: /beautiful-mermaid[\\/]dist[\\/]index\.js$/ }, async (args) => {
      const pkg = JSON.parse(await readFile(new URL("./node_modules/beautiful-mermaid/package.json", import.meta.url), "utf8"));
      if (pkg.version !== mermaidPatch.version) throw new Error(`beautiful-mermaid ${pkg.version}: patches/beautiful-mermaid.mjs는 ${mermaidPatch.version}용이다`);
      let text = await readFile(args.path, "utf8");
      for (const [find, replace] of mermaidPatch.edits) {
        const at = text.indexOf(find);
        if (at < 0 || text.indexOf(find, at + 1) >= 0) throw new Error(`beautiful-mermaid 패치를 한 곳에 넣을 수 없다: ${find.slice(0, 60)}`);
        text = text.slice(0, at) + replace + text.slice(at + find.length);
      }
      return { contents: text, loader: "js" };
    });
  },
};

await build({ ...common, entryPoints: ["src/reader.js"], outfile: `${out}/reader.js`, format: "iife", plugins: [patched] });
await build({ ...common, entryPoints: ["src/native.js"], outfile: `${out}/native.js`, format: "iife", globalName: "folioNative" });
await build({ ...common, entryPoints: ["src/style.css"], outfile: `${out}/note.css`, loader: fonts });
await build({ ...common, entryPoints: ["src/figure.js"], outfile: `${actions}/figure/figure.js`, format: "iife", globalName: "folioFigure" });

const widgetCSS = await build({ ...common, entryPoints: ["src/widget.css"], write: false, outfile: "widget.css", loader: fonts });
await build({
  ...common, entryPoints: ["src/widget.js"], outfile: `${actions}/widget/widget-kit.js`, format: "iife",
  define: { WIDGET_CSS: JSON.stringify(widgetCSS.outputFiles[0].text) },
});
