// The iPad's TeX build (#41): Siglum's BusyTeX, TeX Live in WebAssembly, run in a hidden web view whose scheme
// handler serves the engine from the app and fetches missing TeX Live packages (TexWebEngine in the app).
import { SiglumCompiler } from "@siglum/engine";

const here = (path) => new URL(path, location.href).href;
// The engine's own log of what it fetched and why, for a build that fails without saying so in TeX's log.
let trace = [];

// A new compiler for every build. One kept between builds hands its second build the packages it fetched from its
// own memory, and pdfTeX then reads kotex's fonts short ("pdfTeX error (vf): unexpected EOF"). A new one loads the
// engine's bundles from the page's storage and the packages from the app's caches, as a first build does.
async function made() {
  const progress = window.webkit?.messageHandlers?.texProgress;
  const compiler = new SiglumCompiler({
    wasmUrl: here("rt/wasm/busytex.wasm"),
    jsUrl: here("rt/wasm/busytex.js"),
    bundlesUrl: here("rt/bundles"),
    xzwasmUrl: here("rt/xzwasm.js"),
    workerUrl: here("tex-worker.js"),
    ctanProxyUrl: here("p").replace(/\/$/, ""),
    // A document cache would answer a build of the same source with the last PDF, without the files beside it.
    enableDocCache: false,
    onProgress: (stage) => progress?.postMessage(String(stage)),
    onLog: (line) => trace.push(String(line)),
  });
  await compiler.init();
  return compiler;
}

const bytes = (base64) => Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));

function base64(data) {
  let text = "";
  for (let i = 0; i < data.length; i += 0x8000) text += String.fromCharCode(...data.subarray(i, i + 0x8000));
  return btoa(text);
}

// files: paths relative to the document's folder, with their contents in base64.
async function compile({ engine, mainFile, source, files }) {
  trace = [];
  const additionalFiles = Object.fromEntries(Object.entries(files || {}).map(([path, data]) => [path, bytes(data)]));
  const c = await made();
  let result;
  try {
    result = await c.compile(source, { engine, mainFile, additionalFiles });
  } finally {
    c.unload();
  }
  const pdf = result.pdf ? base64(new Uint8Array(result.pdf)) : null;
  return { success: !!result.success && !!pdf, pdf, log: result.log || "", error: result.error ? String(result.error) : null, trace: trace.slice(-300) };
}

window.folioTex = { compile };
