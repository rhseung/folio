// Bundles into ../app/resources/web. KaTeX fonts are inlined (woff2 only) so pages need no file access.
import { build } from "esbuild";
import { readFile } from "node:fs/promises";

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

// The iPad's TeX build (#41). Siglum starts its worker as a classic script, so it is its own iife file. Two changes
// to the worker, each failing the build unless it matches exactly, so a new Siglum version can't drop them quietly:
// without --halt-on-error TeX goes on past the first error and the log has every one, as Tectonic's has on the Mac;
// and a missing font's error is matched as -file-line-error writes it (`/doc.tex:5: Font …`) and with the size that
// ends the line, so kotex's Korean fonts (uwmj*.tfm) are fetched instead of failing the build.
const texWorker = {
  name: "tex-worker",
  setup(b) {
    b.onLoad({ filter: /@siglum[\/\\]engine[\/\\]src[\/\\]worker\.js$/ }, async ({ path }) => {
      let source = await readFile(path, "utf8");
      const replace = (from, to, count) => {
        const found = source.split(from).length - 1;
        if (found !== count) throw new Error(`tex-worker: expected ${count} of ${from}, found ${found}`);
        source = source.replaceAll(from, to);
      };
      replace("'--halt-on-error', ", "", 4);
      replace(
        String.raw`/! Font [^=]+=([a-z0-9-]+) at .* not loadable: Metric \(TFM\) file/g`,
        String.raw`/(?:^|: |! )Font [^=\s]+=([a-z0-9-]+) at [0-9.]+pt not loadable/gm`,
        1,
      );
      return { contents: source, loader: "js" };
    });
  },
};
// Changes to the page, matched exactly like the worker's. Each one is why a second build of a Korean document failed
// where the first had built: kotex's packages come in on the first build's retries, not from the pre-scan.
const pagePatches = {
  "ctan.js": [
    // The page's own package cache (IndexedDB) gave kotex's fonts back short ("pdfTeX error (vf): unexpected EOF"),
    // and kept a "not found" for good. The app keeps every archive in Caches, so the page unpacks it again instead.
    ["    async loadPackageFromCache(packageName) {\n", "    async loadPackageFromCache(packageName) {\n        return null;\n"],
    ["if (!tlYear) cacheWrites.push(fileSystem.writeBinary(targetPath, ", "if (false) cacheWrites.push(fileSystem.writeBinary(targetPath, "],
    // Siglum's file table has few fonts; for the rest the app knows the package (`/api/package-of`, from TeX Live's own).
    ["        return index[fileName] || null;\n", "        return index[fileName] || (await folioPackageOf(this.proxyUrl, fileName));\n"],
    // Names that come to one package (kotex's fonts, all in uhc) share one fetch and one unpacking.
    ["    async fetchPackage(packageName, options = {}) {", `    fetchPackage(packageName, options = {}) {
        const key = packageName + "@" + (options.tlYear || "");
        this.folioFetches ??= new Map();
        if (!this.folioFetches.has(key)) this.folioFetches.set(key, this.fetchPackageOnce(packageName, options).finally(() => this.folioFetches.delete(key)));
        return this.folioFetches.get(key);
    }
    async fetchPackageOnce(packageName, options = {}) {`],
  ],
  // A format dumped from the preamble comes with only the packages the pre-scan found, not those fetched on retry.
  "compiler.js": [["const canUseFormat = projectFiles.length === 0 && !mainFile.includes('/');", "const canUseFormat = false;"]],
};
// One xz archive at a time: xzwasm unpacking archives in parallel detaches its buffers and some come back short.
const xzStart = "            const XzStream = await loadXzwasm();";
const xzEnd = "                chunks[i] = null; // Allow GC of chunk after copying\n            }\n";
const xzQueue = `
const folioPackages = new Map();
function folioPackageOf(proxyUrl, fileName) {
  if (!folioPackages.has(fileName)) {
    folioPackages.set(fileName, fetch(proxyUrl + "/api/package-of/" + encodeURIComponent(fileName))
      .then((answer) => (answer.ok ? answer.text() : null)).then((name) => name || null).catch(() => null));
  }
  return folioPackages.get(fileName);
}
let xzQueue = Promise.resolve();
function xzInTurn(xzData) {
  const turn = xzQueue.then(() => xzUnpack(xzData));
  xzQueue = turn.catch(() => {});
  return turn;
}
async function xzUnpack(xzData) {
`;
const texPage = {
  name: "tex-page",
  setup(b) {
    b.onLoad({ filter: /@siglum[\/\\]engine[\/\\]src[\/\\](ctan|compiler)\.js$/ }, async ({ path }) => {
      let source = await readFile(path, "utf8");
      const once = (from) => {
        const found = source.split(from).length - 1;
        if (found !== 1) throw new Error(`tex-page: expected 1 of ${from}, found ${found}`);
      };
      const name = path.split(/[\/\\]/).pop();
      for (const [from, to] of pagePatches[name]) {
        once(from);
        source = source.replace(from, to);
      }
      if (name === "ctan.js") {
        once(xzStart);
        once(xzEnd);
        const start = source.indexOf(xzStart);
        const end = source.indexOf(xzEnd) + xzEnd.length;
        const unpack = source.slice(start, end).replace("xzData = null; // Allow GC of original buffer", "").replace(/ *this\.onLog\(`Decompressed[^\n]*\n/, "");
        if (unpack.includes("this.")) throw new Error("tex-page: the xz block uses the fetcher, it can't run on its own");
        source = source.slice(0, start) + "            const tarData = await xzInTurn(xzData);\n            xzData = null;\n" + source.slice(end);
        source += xzQueue + unpack + "            return tarData;\n}\n";
      }
      return { contents: source, loader: "js" };
    });
  },
};
const tex = { ...common, format: "iife", define: { global: "globalThis", "import.meta.url": '""' }, alias: { "blake3-wasm/browser.js": "./src/blake3-disabled.js" } };
await build({ ...tex, entryPoints: ["node_modules/@siglum/engine/src/worker.js"], outfile: `${out}/tex-worker.js`, plugins: [texWorker] });
await build({ ...tex, entryPoints: ["src/tex-engine.js"], outfile: `${out}/tex-engine.js`, plugins: [texPage] });
