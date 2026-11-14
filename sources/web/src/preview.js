const post = (message) => window.webkit?.messageHandlers?.folioPreview?.postMessage(message);

export function preview({ typeset, redraw }) {
  let shown = [];
  let options = {};
  // 블록을 다시 만들어도 접힌 상태가 남도록, 콜아웃을 요소가 아니라 제목과 앞에 같은 제목이 몇 개 있는지로 찾는다.
  const folds = new Map();
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

  // `toggle` 이벤트는 버블링되지 않으므로 capture 단계에서 받는다.
  document.addEventListener("toggle", (event) => {
    const el = event.target;
    if (el instanceof HTMLDetailsElement && el.classList.contains("callout")) folds.set(calloutKey(el), el.open);
  }, true);

  // 할 일의 체크 표시는 앱이 원문에 쓴다. 페이지는 체크가 반영된 노트를 다시 받은 뒤에 체크를 보인다.
  document.addEventListener("click", (event) => {
    const box = event.target.closest?.("input[type=checkbox][data-line]");
    if (!box) return;
    event.preventDefault();
    if (options.editable) post({ type: "task", line: Number(box.dataset.line) });
  }, true);

  // 앱은 페이지의 메뉴에 자기 항목(링크를 탭에서 열기, 포인터 아래 제목이나 블록의 링크 복사)을 넣는데, 메뉴는 어느
  // 요소에서 열렸는지 알려 주지 않는다. 그래서 페이지가 직접 알린다.
  document.addEventListener("contextmenu", (event) => {
    const at = (selector) => event.target.closest?.(selector);
    const own = !at(".embed, .ref-popover");
    post({
      type: "menu",
      href: at("a[href]")?.getAttribute("href") ?? null,
      heading: own ? at("h1, h2, h3, h4, h5, h6")?.textContent ?? null : null,
      block: at("[id^='^']")?.id.slice(1) ?? null,
    });
  }, true);

  // 터치 화면에서 길게 누르면 손가락 아래 낱말이 선택되고 편집 메뉴가 열린다. 앱은 이 메뉴에도 포인터 메뉴와 같은 제목과
  // 블록 링크를 넣는데, 편집 메뉴는 한 점이 아니라 선택 영역을 기준으로 열린다. 그래서 페이지는 선택이 시작하는 곳이
  // 바뀔 때마다 그 위치를 알린다.
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

  // 렌더러는 블록 참조가 가리키는 블록을 링크 바로 다음의 template에 넣는다. 카드 안의 링크를 누를 수 있도록, 포인터가
  // 카드 위로 옮겨 가도 카드를 닫지 않는다.
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

  // scroll 이벤트는 한 프레임에 여러 번 오므로, 맨 위 블록의 줄은 바뀌었을 때만 한 프레임에 많아야 한 번 알린다.
  let reported = null, reporting = false;
  const report = () => {
    if (reporting) return;
    reporting = true;
    requestAnimationFrame(() => {
      reporting = false;
      // 맨 위로 옮긴 블록(jump, 편집기 따라가기)은 페이지 위 끝에서 여백만큼 아래에서 시작한다.
      const y = scrollY + margin() + 1;
      let line = null;
      for (const block of shown) {
        if (block.line == null || !block.nodes.length) continue;
        if (top(block.nodes[0]) > y) break;
        line = block.line;
      }
      if (line === reported) return;
      reported = line;
      post({ type: "top", line: line ?? 0 });
    });
  };
  addEventListener("scroll", report, { passive: true });

  return {
    // 편집기에서 입력할 때 페이지의 나머지 부분과 실행 중인 위젯 페이지를 건드리지 않도록, HTML이 바뀐 블록만 다시 만든다.
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
      // 바뀌지 않은 양 끝 사이에서도 HTML이 남아 있는 블록은 제자리에 둔다. 요소를 옮기면 위젯의 frame이 다시 로드된다.
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
      // 블록 위쪽을 고치면 블록의 HTML은 그대로여도 줄 번호는 바뀌므로, 모든 블록의 줄을 다시 적는다.
      shown.forEach((block, i) => {
        block.line = blocks[i].line;
        for (const node of block.nodes) {
          if (block.line == null) delete node.dataset.line;
          else node.dataset.line = block.line;
        }
      });
      report();
    },

    jump(line) {
      const block = shown.find((b) => b.line === line && b.nodes.length);
      if (block) scrollTo(0, Math.max(0, top(block.nodes[0]) - margin()));
    },

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

    reset() {
      hideCard();
      for (const block of shown) for (const node of block.nodes) node.remove();
      shown = [];
      options = {};
      folds.clear();
      heights.clear();
      reported = null;
      scrollTo(0, 0);
    },

    size(key, height) {
      heights.set(key, height);
      for (const frame of document.querySelectorAll("iframe.cb-widget")) {
        if (frame.dataset.key === key) frame.style.height = `${height}px`;
      }
    },

    theme(css) {
      const style = document.getElementById("folio-theme");
      if (style && style.textContent !== css) {
        style.textContent = css;
        redraw();
      }
    },
  };
}
