// Bundles into ../app/resources/web. KaTeX fonts are inlined (woff2 only) so pages need no file access.
import { build } from "esbuild";
import { copyFile } from "node:fs/promises";

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
// The native note views set `\mathbb` letters in this font (NoteMath), so they look as they do in KaTeX and LaTeX.
await copyFile("node_modules/katex/dist/fonts/KaTeX_AMS-Regular.ttf", `${out}/KaTeX_AMS-Regular.ttf`);
