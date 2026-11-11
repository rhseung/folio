// blake3-wasm's browser build loads its wasm by a path the bundle can't follow; Siglum's hashes fall back to DJB2.
throw new Error("BLAKE3 disabled");
export function hash() {}
