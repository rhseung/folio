// 페이지가 파일에 접근하지 않고도 글꼴을 쓰도록 KaTeX 글꼴은 woff2만 data URL로 넣는다.
import { build } from "esbuild";

const out = "../app/resources/web";
const common = { bundle: true, minify: true, target: "safari18", legalComments: "eof", logLevel: "warning" };

await build({ ...common, entryPoints: ["src/reader.js"], outfile: `${out}/reader.js`, format: "iife" });
await build({ ...common, entryPoints: ["src/native.js"], outfile: `${out}/native.js`, format: "iife", globalName: "folioNative" });
await build({
  ...common,
  entryPoints: ["src/style.css"],
  outfile: `${out}/note.css`,
  loader: { ".woff2": "dataurl", ".woff": "empty", ".ttf": "empty" },
});
