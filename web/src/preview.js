// The note preview: the app sends the note as top-level blocks, each with the source lines it was written on.

const post = (message) => window.webkit?.messageHandlers?.folioPreview?.postMessage(message);

export function preview({ typeset, redraw }) {
  // What the page shows, block by block: the HTML it was made from and the elements that came of it.
  let shown = [];
  let options = {};
  // Folded or opened callouts by their title and how many before it have that title, so a fold survives the
  // block being made again.
  const folds = new Map();
  // Each widget frame's height as its page last said, by the frame's key: a frame made again starts at it.
  const heights = new Map();

  const calloutKey = (details) => {
    const title = details.querySelector(":scope > summary")?.textContent ?? "";
    let n = 0;
    for (const other of document.querySelectorAll("details.callout")) {
      if (other === details) break;
      if ((other.querySelector(":scope > summary")?.textContent ?? "") === title) n++;
    }
    return `${title}#${n}`;
  };

  // `toggle` doesn't bubble, so it's caught on the way down.
  document.addEventListener("toggle", (event) => {
    const el = event.target;
    if (el instanceof HTMLDetailsElement && el.classList.contains("callout")) folds.set(calloutKey(el), el.open);
  }, true);

  // A task's box is ticked in the source; the page shows it once the note comes back with it.
  document.addEventListener("click", (event) => {
    const box = event.target.closest?.("input[type=checkbox][data-line]");
    if (!box) return;
    event.preventDefault();
    if (options.editable) post({ type: "task", line: Number(box.dataset.line) });
  }, true);

  // The app adds its own items to the page's menu (open a link in a tab, copy a link to the heading or block under
  // the pointer), and the menu doesn't say what it was opened on.
  document.addEventListener("contextmenu", (event) => {
    const at = (selector) => event.target.closest?.(selector);
    // A heading drawn from another note (an embed, a reference's preview) is not one of this note's.
    const own = !at(".embed, .ref-popover");
    post({
      type: "menu",
      href: at("a[href]")?.getAttribute("href") ?? null,
      heading: own ? at("h1, h2, h3, h4, h5, h6")?.textContent ?? null : null,
      block: at("[id^='^']")?.id.slice(1) ?? null,
    });
  }, true);

  // A long press on a touch screen selects the words under the finger and opens the edit menu, which the app gives
  // the same heading and block links as the pointer's menu: the edit menu is asked for the selection, not a point,
  // so the page says where the selection starts whenever that changes.
  let selected = null;
  document.addEventListener("selectionchange", () => {
    const node = document.getSelection()?.anchorNode;
    const el = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
    const at = (selector) => el?.closest?.(selector);
    const own = el && !at(".embed, .ref-popover");
    const heading = own ? at("h1, h2, h3, h4, h5, h6")?.textContent ?? null : null;
    const block = el ? at("[id^='^']")?.id.slice(1) ?? null : null;
    const key = JSON.stringify([heading, block]);
    if (key === selected) return;
    selected = key;
    post({ type: "selection", heading, block });
  });

  // A block reference shows the block it names while the pointer rests on it. The renderer puts the block in a
  // template right after the link; the card stays while the pointer moves onto it, so its links can be clicked.
  let card = null, cardFor = null, showing = 0, hiding = 0;
  const hideCard = () => {
    clearTimeout(showing);
    clearTimeout(hiding);
    card?.remove();
    card = cardFor = null;
  };
  const showCard = (link, template) => {
    hideCard();
    const box = document.createElement("div");
    box.className = "ref-popover";
    if (template.dataset.math) box.dataset.math = template.dataset.math;
    box.append(template.content.cloneNode(true));
    typeset(box);
    document.body.append(box);
    const r = link.getBoundingClientRect();
    const gap = 8;
    const left = Math.max(gap, Math.min(r.left, innerWidth - box.offsetWidth - gap));
    let y = r.bottom + gap / 2;
    if (y + box.offsetHeight > innerHeight - gap && r.top - box.offsetHeight - gap / 2 > gap) y = r.top - box.offsetHeight - gap / 2;
    box.style.left = `${left + scrollX}px`;
    box.style.top = `${y + scrollY}px`;
    card = box;
    cardFor = link;
  };
  document.addEventListener("mouseover", (event) => {
    const link = event.target.closest?.("a.wikilink");
    if (card && (card.contains(event.target) || link === cardFor)) return clearTimeout(hiding);
    clearTimeout(showing);
    const template = link?.nextElementSibling?.matches("template.ref-preview") ? link.nextElementSibling : null;
    if (template) showing = setTimeout(() => showCard(link, template), 300);
    if (card) {
      clearTimeout(hiding);
      hiding = setTimeout(hideCard, 200);
    }
  });
  document.documentElement.addEventListener("mouseleave", () => {
    clearTimeout(showing);
    if (card) hiding = setTimeout(hideCard, 200);
  });

  function make(html) {
    const box = document.createElement("div");
    box.innerHTML = html;
    for (const frame of box.querySelectorAll("iframe.cb-widget[data-key]")) {
      frame.style.height = `${heights.get(frame.dataset.key) ?? Number(frame.dataset.height)}px`;
    }
    typeset(box);
    return [...box.children];
  }

  function prepare(nodes) {
    for (const node of nodes) {
      for (const box of node.querySelectorAll("input[type=checkbox][data-line]")) box.disabled = !options.editable;
      for (const details of node.matches("details.callout") ? [node] : node.querySelectorAll("details.callout")) {
        const open = folds.get(calloutKey(details));
        if (open !== undefined) details.open = open;
      }
    }
  }

  const margin = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--margin")) || 0;
  const top = (node) => node.getBoundingClientRect().top + scrollY;

  return {
    // Only blocks whose HTML changed are made again, so typing in the editor leaves the rest of the page (and a
    // widget's running page) alone.
    show(blocks, next) {
      const restart = next.math !== options.math || next.base !== options.base;
      const editable = next.editable !== options.editable;
      options = next;
      document.body.dataset.math = next.math;
      const base = document.querySelector("base");
      if (base && next.base) base.href = next.base;
      if (restart) {
        for (const block of shown) for (const node of block.nodes) node.remove();
        shown = [];
      }
      let head = 0;
      while (head < shown.length && head < blocks.length && shown[head].html === blocks[head].html) head++;
      let tail = 0;
      while (tail < shown.length - head && tail < blocks.length - head
        && shown[shown.length - 1 - tail].html === blocks[blocks.length - 1 - tail].html) tail++;
      const first = (list, from) => list.slice(from).find((b) => b.nodes.length)?.nodes[0];
      const after = first(shown, shown.length - tail) ?? null;
      // Between the unchanged ends, a block whose HTML is still there stays where it is: moving an element would
      // reload a widget's frame. The rest are made anew in place.
      const old = shown.slice(head, shown.length - tail);
      const middle = [], made = [];
      let p = 0;
      for (const block of blocks.slice(head, blocks.length - tail)) {
        let j = p;
        while (j < old.length && old[j].html !== block.html) j++;
        if (j < old.length) {
          for (const gone of old.slice(p, j)) for (const node of gone.nodes) node.remove();
          middle.push(old[j]);
          p = j + 1;
        } else {
          const anchor = first(old, p) ?? after;
          const fresh = { html: block.html, nodes: make(block.html) };
          for (const node of fresh.nodes) document.body.insertBefore(node, anchor);
          made.push(fresh);
          middle.push(fresh);
        }
      }
      for (const gone of old.slice(p)) for (const node of gone.nodes) node.remove();
      prepare(made.flatMap((b) => b.nodes));
      shown = [...shown.slice(0, head), ...middle, ...shown.slice(shown.length - tail)];
      if (editable) prepare(shown.flatMap((b) => b.nodes));
      if (cardFor && !cardFor.isConnected) hideCard();
      // Lines move with every edit above a block, which leaves its HTML as it was.
      shown.forEach((block, i) => {
        block.line = blocks[i].line;
        for (const node of block.nodes) {
          if (block.line == null) delete node.dataset.line;
          else node.dataset.line = block.line;
        }
      });
    },

    // Puts the block holding the editor's top line where the editor has it: `frac` of the way through the line.
    follow(line, frac) {
      const blocks = shown.filter((b) => b.line != null && b.nodes.length);
      let i = -1;
      for (let j = 0; j < blocks.length && blocks[j].line <= line; j++) i = j;
      if (i < 0) return scrollTo(0, 0);
      const ya = top(blocks[i].nodes[0]);
      const next = blocks[i + 1];
      const yb = next ? top(next.nodes[0]) : ya + 40;
      const from = blocks[i].line, to = next ? next.line : from + 1;
      const y = ya + (yb - ya) * Math.min(1, (line - from + frac) / Math.max(1, to - from));
      scrollTo(0, Math.max(0, y - margin()));
    },

    // The page is handed to another note: nothing of this one stays.
    reset() {
      hideCard();
      for (const block of shown) for (const node of block.nodes) node.remove();
      shown = [];
      options = {};
      folds.clear();
      heights.clear();
      scrollTo(0, 0);
    },

    // A widget's frame takes its page's height, as the app works it out from what the page reports.
    size(key, height) {
      heights.set(key, height);
      for (const frame of document.querySelectorAll("iframe.cb-widget")) {
        if (frame.dataset.key === key) frame.style.height = `${height}px`;
      }
    },

    // The variables the page's colors come from, swapped when the course's accent changes.
    theme(css) {
      const style = document.getElementById("folio-theme");
      if (style && style.textContent !== css) {
        style.textContent = css;
        redraw();
      }
    },
  };
}
