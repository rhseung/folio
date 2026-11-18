// beautiful-mermaid가 테마 옵션으로 바꾸게 두지 않은 상수를 노트 그림 스타일(#533)에 맞춘다. 묶을 때 build.mjs가
// dist/index.js에 바꿔 넣는다. 찾는 글이 정확히 한 번 나오지 않으면 묶기가 실패하므로, 판을 올리면 여기를 다시 맞춘다.
export const version = "1.1.3";

export const edits = [
  // 라이브러리의 폭 표는 Inter 기준이다. SF는 대문자와 기호가 넓어서 브라우저에서 잰 폭이 평균 1.13배, 최대 1.19배였다.
  [
    "function measureTextWidth(text, fontSize, fontWeight) {\n",
    "function measureTextWidth(text, fontSize, fontWeight) {\n  return 1.15 * measureTextWidthInter(text, fontSize, fontWeight);\n}\nfunction measureTextWidthInter(text, fontSize, fontWeight) {\n",
  ],
  // 코드는 LaTeX 타자기체(한 글자 0.525em)를 수식 배율 1.21로 그린다.
  ["return text.length * fontSize * 0.6;", "return text.length * fontSize * 0.525 * 1.21;"],
  ["  nodeLabel: 13,\n  /** Edge label text */\n  edgeLabel: 11,", "  nodeLabel: 14,\n  /** Edge label text */\n  edgeLabel: 12,"],
  ["var FONT_WEIGHTS = {\n  nodeLabel: 500,", "var FONT_WEIGHTS = {\n  nodeLabel: 400,"],
  ["  outerBox: 1,\n", "  outerBox: 1.1,\n"],
  ["  connector: 1\n", "  connector: 1.2\n"],
  // 이웃한 두 참여자 사이 메시지의 라벨이 화살표보다 길면 라벨이 화살촉과 생명선에 닿는다. 라벨 폭과 양쪽 여백만큼 벌린다.
  [
    "  let currentX = SEQ.padding + actorWidths[0] / 2;\n",
    "  let currentX = SEQ.padding + actorWidths[0] / 2;\n"
      + "  const order = new Map(diagram.actors.map((a, i) => [a.id, i]));\n"
      + "  const labelGap = diagram.actors.map(() => 0);\n"
      + "  for (const m of diagram.messages ?? []) {\n"
      + "    const i = order.get(m.from), j = order.get(m.to);\n"
      + "    if (i === void 0 || j === void 0 || Math.abs(i - j) !== 1 || !m.label) continue;\n"
      + "    const k = Math.max(i, j);\n"
      + "    labelGap[k] = Math.max(labelGap[k], estimateTextWidth(m.label, FONT_SIZES.edgeLabel, FONT_WEIGHTS.edgeLabel) + 32);\n"
      + "  }\n",
  ],
  [
    "const minGap = Math.max(SEQ.actorGap, (actorWidths[i - 1] + actorWidths[i]) / 2 + 40);",
    "const minGap = Math.max(SEQ.actorGap, (actorWidths[i - 1] + actorWidths[i]) / 2 + 40, labelGap[i]);",
  ],
  ["  memberFontSize: 11,", "  memberFontSize: 12,"],
  ["  memberSize: 11,", "  memberSize: 12,"],
  ["  attrFontSize: 11,", "  attrFontSize: 12,"],
  ["  attrSize: 11,", "  attrSize: 12,"],
  // mermaid.js가 수식 자리 글자의 폭을 라이브러리와 같은 어림으로 잰다.
  ["export {\n", "export {\n  measureTextWidth,\n"],
];
