// Bundles into ../app/resources/web. KaTeX fonts are inlined (woff2 only) so pages need no file access.
import { build } from "esbuild";

const out = "../app/resources/web";
const common = { bundle: true, minify: true, target: "safari18", legalComments: "eof", logLevel: "warning" };

await build({ ...common, entryPoints: ["src/reader.js"], outfile: `${out}/reader.js`, format: "iife" });
await build({ ...common, entryPoints: ["src/editor.js"], outfile: `${out}/editor.js`, format: "iife" });
await build({
  ...common,
  entryPoints: ["src/style.css"],
  outfile: `${out}/note.css`,
  loader: { ".woff2": "dataurl", ".woff": "empty", ".ttf": "empty" },
});
