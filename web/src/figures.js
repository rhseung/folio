// The note preview's picture viewer: a picture or diagram pressed in the preview opens over the note, fitted to the
// window, to zoom and move around. A picture inside a link opens the link instead.

const pictures = "img, figure.mermaid";
const icons = {
  close: "M4 4l8 8M12 4l-8 8",
  previous: "M10 3L5 8l5 5",
  next: "M6 3l5 5-5 5",
  "zoom-out": "M3 8h10",
  "zoom-in": "M3 8h10M8 3v10",
};
const icon = (name) =>
  `<svg viewBox="0 0 16 16" width="1em" height="1em" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icons[name]}"/></svg>`;

// Only the note preview's own pictures: the Claude panel's page shares this script, and a block reference's card is
// gone once the pointer leaves it.
const openable = (el) =>
  document.body.classList.contains("preview") && el.isConnected && !el.closest("a[href], .ref-popover, .figure-viewer")
  && (el.tagName === "IMG" ? !(el.complete && el.naturalWidth === 0) : !!el.querySelector("svg"));

// SVG as an <img> or inline (mermaid) is drawn again at every size, so it may fill the window; a bitmap stops at its
// own size until zoomed.
const isVector = (el) => el.tagName !== "IMG" || /\.svgz?([?#]|$)|^data:image\/svg/i.test(el.currentSrc || el.src);

function naturalSize(el) {
  if (el.tagName === "IMG" && el.naturalWidth > 0) return { w: el.naturalWidth, h: el.naturalHeight };
  const svg = el.tagName === "IMG" ? null : el.querySelector("svg");
  const box = svg?.viewBox?.baseVal;
  if (box?.width > 0 && box.height > 0) {
    const w = parseFloat(svg.getAttribute("width")), h = parseFloat(svg.getAttribute("height"));
    return w > 0 && h > 0 && !String(svg.getAttribute("width")).includes("%") ? { w, h } : { w: box.width, h: box.height };
  }
  const r = (svg ?? el).getBoundingClientRect();
  return { w: Math.max(1, r.width), h: Math.max(1, r.height) };
}

export function figures() {
  const bound = new WeakSet();
  let viewer = null, sheet = null, source = null;
  // The sheet's top left in the window and its scale against the picture's own size.
  let x = 0, y = 0, s = 1, fit = 1, size = { w: 1, h: 1 };
  const pointers = new Map();
  let drag = null, lastTap = null, gesture = null;

  const label = (name) => document.body.dataset[`label${name.replace(/(^|-)(\w)/g, (_, __, c) => c.toUpperCase())}`] ?? "";
  const all = () => [...document.querySelectorAll(pictures)].filter(openable);

  // A listener on each picture rather than one on the page: iPad WebKit sends no click up from an element that isn't
  // clickable itself.
  function bind(root) {
    if (!(root instanceof Element)) return;
    for (const el of root.matches(pictures) ? [root] : root.querySelectorAll(pictures)) {
      if (bound.has(el)) continue;
      bound.add(el);
      el.addEventListener("click", (event) => {
        if (!openable(el) || event.defaultPrevented) return;
        event.preventDefault();
        open(el);
      });
    }
  }
  bind(document.body);
  new MutationObserver((records) => {
    for (const record of records) record.addedNodes.forEach(bind);
    // The note changed under it (another note opened, the picture's block edited away).
    if (source && !source.isConnected) close();
  }).observe(document.body, { childList: true, subtree: true });

  function button(name, text) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = `figure-pill figure-${name}`;
    if (text == null) {
      b.innerHTML = icon(name);
      b.setAttribute("aria-label", label(name));
      b.title = label(name);
    } else {
      b.textContent = text;
    }
    return b;
  }

  function build() {
    viewer = document.createElement("div");
    viewer.className = "figure-viewer";
    viewer.setAttribute("role", "dialog");
    viewer.setAttribute("aria-modal", "true");
    sheet = document.createElement("div");
    sheet.className = "figure-sheet";
    const top = document.createElement("div");
    top.className = "figure-bar figure-top";
    const count = document.createElement("span");
    count.className = "figure-pill figure-count";
    count.setAttribute("aria-live", "polite");
    const closeButton = button("close");
    top.append(count, closeButton);
    const bottom = document.createElement("div");
    bottom.className = "figure-bar figure-bottom";
    const out = button("zoom-out"), fitButton = button("fit", label("fit")), actual = button("actual", "100%"), zoomIn = button("zoom-in");
    bottom.append(out, fitButton, actual, zoomIn);
    const previous = button("previous"), next = button("next");
    previous.classList.add("figure-nav");
    next.classList.add("figure-nav");
    viewer.append(sheet, top, previous, next, bottom);

    closeButton.addEventListener("click", close);
    out.addEventListener("click", () => zoomAt(0.8, ...center()));
    zoomIn.addEventListener("click", () => zoomAt(1.25, ...center()));
    fitButton.addEventListener("click", fitAll);
    actual.addEventListener("click", () => zoomAt(1 / s, ...center()));
    previous.addEventListener("click", () => step(-1));
    next.addEventListener("click", () => step(1));

    viewer.addEventListener("wheel", (event) => {
      event.preventDefault();
      // A trackpad pinch comes as a wheel with ctrl held, unless WebKit sends it as a gesture below.
      if (event.ctrlKey && gesture) return;
      zoomAt(Math.exp(-event.deltaY * (event.ctrlKey ? 0.01 : 0.002)), event.clientX, event.clientY);
    }, { passive: false });
    // Safari's own pinch events; a touch pinch is read from the pointers instead, so it isn't zoomed twice.
    viewer.addEventListener("gesturestart", (event) => { event.preventDefault(); gesture = pointers.size < 2 ? 1 : null; });
    viewer.addEventListener("gesturechange", (event) => {
      event.preventDefault();
      if (gesture == null || pointers.size >= 2) return;
      zoomAt(event.scale / gesture, event.clientX, event.clientY);
      gesture = event.scale;
    });
    viewer.addEventListener("gestureend", (event) => { event.preventDefault(); gesture = null; });

    viewer.addEventListener("pointerdown", down);
    viewer.addEventListener("pointermove", move);
    viewer.addEventListener("pointerup", up);
    viewer.addEventListener("pointercancel", up);
  }

  const parts = () => ({
    count: viewer.querySelector(".figure-count"), actual: viewer.querySelector(".figure-actual"),
    navs: viewer.querySelectorAll(".figure-nav"), top: viewer.querySelector(".figure-top"), bottom: viewer.querySelector(".figure-bottom"),
    nav: viewer.querySelector(".figure-nav"),
  });

  function show(el) {
    source = el;
    size = naturalSize(el);
    let copy;
    if (el.tagName === "IMG") {
      copy = new Image();
      copy.src = el.currentSrc || el.src;
      copy.alt = el.alt;
    } else {
      copy = el.querySelector("svg").cloneNode(true);
      if (!copy.getAttribute("viewBox")) copy.setAttribute("viewBox", `0 0 ${size.w} ${size.h}`);
      copy.setAttribute("width", "100%");
      copy.setAttribute("height", "100%");
    }
    copy.draggable = false;
    sheet.replaceChildren(copy);
    const list = all(), { count, navs } = parts();
    count.textContent = `${list.indexOf(el) + 1} / ${list.length}`;
    count.hidden = list.length < 2;
    for (const nav of navs) nav.hidden = list.length < 2;
    fitAll();
  }

  function open(el) {
    if (!viewer) build();
    if (!viewer.isConnected) document.body.append(viewer);
    show(el);
    viewer.querySelector(".figure-close").focus({ preventScroll: true });
  }

  function close() {
    viewer?.remove();
    source = null;
    pointers.clear();
    drag = lastTap = gesture = null;
  }

  function step(by) {
    const list = all();
    if (list.length < 2) return;
    show(list[(list.indexOf(source) + by + list.length) % list.length]);
  }

  // The room the picture fits in: the window less the bars above and below, and the side buttons when there are some.
  function room() {
    const { top, bottom, nav } = parts();
    const edge = parseFloat(getComputedStyle(top).top) || 0;
    const sides = nav.hidden ? edge : nav.offsetWidth + 2 * edge;
    const above = top.offsetHeight + 2 * edge, below = bottom.offsetHeight + 2 * edge;
    return { left: sides, top: above, w: Math.max(1, innerWidth - 2 * sides), h: Math.max(1, innerHeight - above - below) };
  }

  function fitAll() {
    const r = room();
    fit = Math.min(r.w / size.w, r.h / size.h, isVector(source) ? 4 : 1);
    s = fit;
    x = r.left + (r.w - size.w * s) / 2;
    y = r.top + (r.h - size.h * s) / 2;
    apply();
  }

  const center = () => [innerWidth / 2, innerHeight / 2];

  function zoomAt(factor, cx, cy) {
    const next = Math.min(Math.max(s * factor, fit / 2), Math.max(8, fit));
    x = cx - (cx - x) * next / s;
    y = cy - (cy - y) * next / s;
    s = next;
    apply();
  }

  // Drawn at its size, not scaled: a scaled layer is a bitmap blown up, and SVG would blur.
  function apply() {
    const w = size.w * s, h = size.h * s;
    // The sheet always covers the window's middle, so it can't be lost off an edge.
    x = Math.min(Math.max(x, innerWidth / 2 - w), innerWidth / 2);
    y = Math.min(Math.max(y, innerHeight / 2 - h), innerHeight / 2);
    sheet.style.width = `${w}px`;
    sheet.style.height = `${h}px`;
    sheet.style.transform = `translate(${x}px, ${y}px)`;
    parts().actual.textContent = `${Math.round(s * 100)}%`;
  }

  const atFit = () => Math.abs(s - fit) < 0.005;

  function toggle(cx, cy) {
    if (!atFit()) return fitAll();
    zoomAt((Math.abs(fit - 1) < 0.005 ? 2 : 1) / s, cx, cy);
  }

  function down(event) {
    if (event.target.closest("button, .figure-count")) return;
    try { viewer.setPointerCapture(event.pointerId); } catch {}
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (pointers.size === 1) drag = { x: event.clientX, y: event.clientY, moved: false, fit: atFit(), onSheet: sheet.contains(event.target) };
    else if (drag) drag.moved = true;
    viewer.classList.add("dragging");
  }

  function move(event) {
    const last = pointers.get(event.pointerId);
    if (!last) return;
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()];
      const before = Math.hypot(a.x - b.x, a.y - b.y);
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      const [c, d] = [...pointers.values()];
      const now = { x: (c.x + d.x) / 2, y: (c.y + d.y) / 2 };
      x += now.x - mid.x;
      y += now.y - mid.y;
      if (before > 0) zoomAt(Math.hypot(c.x - d.x, c.y - d.y) / before, now.x, now.y);
      else apply();
      return;
    }
    x += event.clientX - last.x;
    y += event.clientY - last.y;
    pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    if (drag && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 4) drag.moved = true;
    apply();
  }

  function up(event) {
    if (!pointers.delete(event.pointerId)) return;
    if (pointers.size) return;
    viewer.classList.remove("dragging");
    const start = drag;
    drag = null;
    if (!start) return;
    const dx = event.clientX - start.x, dy = event.clientY - start.y;
    if (start.moved) {
      // A sideways swipe of the fitted picture goes to the next one; any other drag of it springs back.
      if (start.fit && event.type === "pointerup" && Math.abs(dx) > 60 && Math.abs(dx) > 2 * Math.abs(dy) && all().length > 1) step(dx < 0 ? 1 : -1);
      else if (start.fit) fitAll();
      return;
    }
    if (!start.onSheet) return close();
    const now = performance.now();
    if (lastTap && now - lastTap.time < 350 && Math.hypot(event.clientX - lastTap.x, event.clientY - lastTap.y) < 24) {
      lastTap = null;
      toggle(event.clientX, event.clientY);
    } else {
      lastTap = { time: now, x: event.clientX, y: event.clientY };
    }
  }

  document.addEventListener("keydown", (event) => {
    if (!viewer?.isConnected) return;
    const command = event.metaKey || event.ctrlKey;
    let handled = true;
    if (event.key === "Escape") close();
    else if (event.key === "ArrowLeft" && !command) step(-1);
    else if (event.key === "ArrowRight" && !command) step(1);
    else if (command && (event.key === "=" || event.key === "+")) zoomAt(1.25, ...center());
    else if (command && event.key === "-") zoomAt(0.8, ...center());
    else if (command && event.key === "0") fitAll();
    else handled = false;
    if (handled) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  addEventListener("resize", () => {
    if (!viewer?.isConnected) return;
    if (atFit()) fitAll();
    else apply();
  });

  // A diagram takes its colors as values and is drawn again for a new appearance (reader.js); the copy follows it.
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    requestAnimationFrame(() => {
      if (source?.tagName !== "FIGURE") return;
      const [sx, sy, ss] = [x, y, s];
      show(source);
      [x, y, s] = [sx, sy, ss];
      apply();
    });
  });

  return { close };
}
