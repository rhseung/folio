// JavaScriptCore에는 window, self, global이 모두 없다. beautiful-mermaid가 쓰는 elkjs는 이 셋 중 하나를 전역 객체로
// 잡고 그 위의 Error와 Math를 쓰는데, 셋이 다 없으면 빈 객체를 잡아 배치가 실패한다. elkjs를 읽기 전에 들어와야 하므로
// figure.js가 이 파일을 가장 먼저 import한다.
globalThis.global ??= globalThis;
globalThis.console ??= { log() {}, warn() {}, error() {}, err() {} };
// elkjs의 가짜 worker는 답을 setTimeout으로 넘긴다. beautiful-mermaid는 배치를 동기로 받고 그 답은 쓰지 않지만, setTimeout이
// 없으면 처음 배치에서 오류가 나고 그 뒤로 elkjs가 반쯤 만든 채 남는다.
globalThis.setTimeout ??= (fn, ms, ...args) => {
  Promise.resolve().then(() => fn(...args));
  return 0;
};
globalThis.clearTimeout ??= () => {};
// beautiful-mermaid가 쓰는 entities는 읽을 때 base64 표를 atob로 푼다. 앱의 JSContext에는 atob가 없다.
globalThis.atob ??= (text) => {
  const digits = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const clean = text.replace(/[^A-Za-z0-9+/]/g, "");
  let out = "";
  for (let i = 0, bits = 0, value = 0; i < clean.length; i++) {
    value = (value << 6) | digits.indexOf(clean[i]);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out += String.fromCharCode((value >> bits) & 255);
    }
  }
  return out;
};
