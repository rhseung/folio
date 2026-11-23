// Claude가 읽을 때마다 맥락에 들어가므로 짧게 쓴다. 그림의 클래스와 선 굵기는 FigureStyle에서 읽는다.
public enum NoteWritingGuide {
    // 콜아웃 종류는 설정에 따라 달라지므로 FolioMarkdown의 표를 읽는 쪽이 넘긴다.
    public static func text(callouts: [String], numbered: [String]) -> String {
        let variables = FigureStyle.inks.map { "`--\($0.name)`" }.joined(separator: " ")
        return #"""
            # Folio 노트 형식

            노트는 마크다운이다. 명령 이름은 MCP 도구에서 공백이 `_`가 된다(`note figure add` → `note_figure_add`).

            ## 수식, 콜아웃, 목차
            - 수식은 `$…$`, `$$…$$`. 문법은 노트의 `math`(기본 TeX). 블록 하나만 다르면 ```` ```asciimath ```` 펜스.
            - 콜아웃: `> [!종류] 제목` 다음 줄부터 `> 본문`. `[!종류]-`는 접힌 채, `[!종류]+`는 펼친 채 접을 수 있다.
              종류: \#(callouts.joined(separator: " ")). \#(numbered.joined(separator: "·"))은 번호가 붙는다(제목에 `1.2`를 쓰면 그 번호).
            - 한 줄에 홀로 쓴 `[TOC]`는 목차.

            ## 링크
            - 노트 `[[note:<ID>|이름]]`, 제목 `[[note:<ID>#제목|이름]]`, 블록 `[[note:<ID>#^블록|이름]]`(블록 ID는 문단 끝의 ` ^id`). `![[…]]`는 그 부분을 끼워 보인다.
            - 자료의 쪽 `[[material:<ID>#page=N|파일 이름]]`. 그 밖은 종류 이름 그대로: `[[exam:<ID>|중간고사]]`, `session`, `unit`, `assignment`.
            - ID는 `note list`, `material list` 같은 목록의 `--json`에서 읽는다.

            ## 도식
            - ```` ```mermaid ```` 펜스는 앱이 그림과 같은 색, 글꼴, 화살촉으로 그린다. 테마를 적지 않는다. 강조색은 `classDef`와 `linkStyle`에 `blue red green orange magenta cyan`으로만 쓴다. mermaid로 안 되는 그림만 SVG로 그린다.
            - 라벨은 짧게 둔다. 노드와 선 라벨의 `$…$`는 LaTeX로 그리고 `<br/>`은 줄을 나눈다. 마름모는 가운데만 넓어서 긴 줄은 꼭짓점 쪽 변에 닿는다. 긴 수식이나 판정 조건은 마름모에 넣지 않고 SVG 그림으로 그린다.
            - `note write`, `note edit`, `note add`는 새로 쓰거나 바뀐 도식을 앱처럼 그려 보고, 그림과 같은 기준(라벨끼리, 라벨과 선·노드 테두리, 그림 밖)으로 검사한다. 걸리면 몇 번째 도식의 어느 라벨인지 알리고 노트를 쓰지 않는다.

            ## 그림(SVG)
            - `note figure add <과목> <이름>.svg --svg <파일>`이 `Notes/assets`에 쓴다. 노트에는 `![설명](assets/<이름>.svg)`(하위 폴더의 노트는 `../assets/`). 고칠 때는 `note figure show`의 `text`를 고치고 `hash`를 `note figure write --expect`에.
            \#(figureRules)

            ## 위젯
            - `note widget add <과목> --html <파일>`이 `.folio/widgets/<ID>.html`을 쓰고 ID를 돌려준다. 노트에는
              ```` ```cb-widget ```` 펜스 안에 `{"id": "<ID>", "height": 320}`. 고칠 때는 `note widget show`의 `hash`를 `note widget write --expect`에.
            - `<title>`에 위젯 이름을 쓴다(`<title>증가 경로 단계</title>`). 애셋 서랍과 `note widget list`가 이 이름으로 보이고, 없으면 "위젯"으로만 보인다.
            - HTML 파일 하나가 격리된 frame에서 돈다. 인라인 `<script>`와 `<style>`만 되고, 네트워크·CDN·바깥 파일, 링크와 페이지 이동, 저장(상태는 다시 열면 처음부터)은 안 된다. 이미지는 `data:`/`blob:`.
            - 색은 미리 들어 있는 CSS 변수로만 쓴다. 라이트·다크를 따라간다. 노트 색 `--text --text-2 --text-3 --line --line-soft --fill --code-fill --card --accent --accent-ink`, `--c-definition --c-theorem --c-example --c-warning --c-danger --c-neutral`, 그림 색 \#(variables). 바탕은 투명, `body`는 여백 0, 14px 시스템 글꼴.
            - 컨트롤은 맨 `<button>`, `<input>`, `<select>`를 쓰면 회색 얇은 테두리 스타일이 들어 있다. `button.primary`, `button.ghost`, 켠 상태는 `aria-pressed="true"`, 탭은 `<div class="tabs">` 안의 버튼과 `aria-selected`, 배지 `.badge`(`.good`, `.bad`), 그림 판 `.board`. 안쪽 그림(그래프, 행렬, 좌표)은 위의 그림 스타일을 `var(--p-blue)`처럼 쓴다.
            - 화살표는 촉을 직접 그리지 않고 `marker-end="url(#m-ink)"`처럼 선과 같은 색의 `m-이름`을 쓴다. 그림과 같은 촉이 frame에 들어 있고 라이트·다크를 따라간다. 직접 그린 `<marker>`는 색을 주지 않으면 검정이 되고, 그려 보기가 이것을 알린다.
            - KaTeX가 들어 있다. 글과 SVG `<text>`의 `$…$`는 저절로 수식이 되고, 스크립트는 `katex.renderToString`이나 `folioTypeset(요소)`를 부른다. 버튼과 배지의 수식도 `$…$`로 쓰고 유니코드 위·아래 첨자로 흉내 내지 않는다.
            - 대상을 직접 누르거나 끌게 한다(정점을 눌러 고르기, 점을 끌어 벡터 바꾸기). 한 부분을 고르는 컨트롤은 그 부분 옆에, 결과는 누른 자리 가까이에 둔다. 지금 고른 것은 늘 보인다. 모든 조작이 터치로 되고 누를 곳은 44pt 이상이다. 만든 뒤 쓰는 순서대로 눌러 보고 손이 멀리 오가는 곳을 고친다.
            - 높이는 내용을 따라 자라고 위젯 안은 스크롤되지 않는다. `height`는 처음 높이다. `100vh`처럼 frame을 따르는 높이를 쓰면 `height`가 그대로 남는다. 폭은 노트 열(390~720pt)이니 고정 폭 대신 폭에 맞추고, 넓은 것은 가로 스크롤.

            ## 그려 보기
            쓰기 전에 `note figure render <과목> --text <SVG>`, `note widget render <과목> --text <HTML>`로 라이트·다크, 폭 480·900에서 그린 그림을 본다(이미 쓴 것은 이름이나 ID로). 겹친 글자, 잘린 부분, 다크에서 사라진 색, 위젯의 콘솔 오류를 고친 뒤 쓴다.
            """#
    }

    // 그림 하나의 SVG 규칙이다. 노트 그림과 문제집 그림(`ProblemArt`)이 같은 스타일과 검사를 쓴다.
    public static let figureRules: String = {
        let inks = FigureStyle.inks.map { "`\($0.name)`" }.joined(separator: " ")
        let strokes = FigureStyle.strokes.map { "\($0.role) \(FigureStyle.g($0.width))" }.joined(separator: ", ")
        return #"""
            - 모양은 LaTeX 교과서의 그림이다. 선과 글자는 검정, 강조만 원색, 바탕은 투명하다. 노트는 그림을 이미지로 보여서 스크립트, 바깥 파일·글꼴·이미지를 쓸 수 없다. 이미지는 `data:` 주소로 넣는다.
            - 색은 클래스로만 칠한다. 면과 글자는 `class="이름"`, 선은 `class="s-이름"`: \#(inks). `muted`는 보조 선과 흐린 글자, `grid`는 격자, `paper`는 라벨 뒤를 가리는 종이색이다. hex·rgb·색 이름, 직접 쓴 다크 규칙은 쓰지 않는다. 라이트·다크 값은 쓸 때 들어간다.
            - 선 굵기(`stroke-width`): \#(strokes). 선에는 `fill="none"`.
            - 화살표는 촉을 그리지 않고 `marker-end="url(#m-ink)"`처럼 선과 같은 색의 `m-이름`을 쓴다. 촉은 선 굵기를 따라 커지고 점선이어도 실선이다.
            - 그림의 글은 라벨만 둔다(\#(FigureStyle.labelLimit)자까지): 정점과 집합 이름, 축, 짧은 수식, (a)(b). 설명, 범례 문장, 단계 설명, 증명은 노트 본문에 쓰고, 색의 뜻은 라벨 색으로 알린다.
            - 그림에는 한국어를 쓰지 않는다. 라벨은 기호와 짧은 영어다. 인문사회 과목(과목코드 \#(FigureStyle.koreanCodes.sorted().joined(separator: " ")))의 그림만 한국어를 받는다. 두 글자 이상의 낱말이 \#(FigureStyle.proseWords)개 이상 든 라벨은 문장으로 보고 거절한다.
            - 코드(`t1 = y + z`, `make_pkt(ACK)`)는 `class="mono"`로 쓴다. 쓸 때 mermaid 도식의 코드와 같은 고정폭 LaTeX 글자(`\texttt`)가 된다. `$\texttt{…}$`로 돌려 쓰지 않는다.
            - 수식, 화학식, 미지수는 `<text>` 안에 `$…$`로 쓴다(`$v_1$`, `$\ce{H2O}$`, 벡터는 `$\mathbf{F}$`). 쓸 때 LaTeX 글자 모양이 된다. 낱말은 그대로 두면 산세리프다. 수식이 든 라벨은 `<tspan>` 없이 `<text>` 하나로 쓴다.
            - 글자는 14px, `class="sm"` 12px, `class="lg"` 17px, `class="bd"` 굵게. 글꼴과 크기를 따로 적지 않는다. 색과 크기 클래스는 `<g>`에 달면 그 안의 글자가 물려받는다.
            - 여러 칸 그림(테두리 있는 rect를 나란히 둔 그림)은 칸마다 내용을 가운데에 두고, 라벨과 도형이 칸의 테두리를 넘지 않게 한다. 칸 사이를 잇는 화살표만 칸을 넘는다.
            - 그래프의 변은 정점 원의 경계나 중심에서 끝난다. 중심에서 끝내면 정점을 변보다 뒤에 그려 가린다.
            - 물리 그림: 힘과 속도는 색 화살표, 분해한 성분은 같은 색 점선, 고정된 면은 빗금, 치수는 양쪽 화살표와 `muted` 점선 보조선, 광선은 가운데 촉(`marker-mid`).
            - 좌표는 눈대중하지 않고 공식으로 계산한다(렌즈의 상, 접점, 교점). 정해진 점을 지나야 하는 선은 그 점의 좌표를 꺾이는 점으로 그대로 쓰고, 점을 `<circle id="F2" …>`로 두고 선에 `data-through="F2"`를 단다. 쓸 때 선이 그 점을 1.5px 안으로 지나는지 본다. 쓴 뒤에는 `note figure render`로 그려 본다.
            - `viewBox`를 두고 `width`/`height`는 뺀다. 쓸 때 `viewBox`의 크기를 넣으므로 작은 그림은 작게 보이고, 노트 열(390~720pt)보다 넓은 그림은 열 폭에 맞춰 줄어든다.
            - 쓸 때 라벨끼리, 라벨과 선(선 굵기 절반 + 1.5px 간격), 칠한 면의 경계, 그림 밖으로 나간 라벨, 칸 테두리를 넘은 내용, 정점 가까이에서 닿지 않고 끝난 변을 검사한다. `s-grid` 격자와 불투명한 도형이 가린 선은 보지 않으니, 선 위 라벨은 아래에 `class="paper"` 상자를 깐다.
            - 예전 그림을 고칠 때는 그 배치를 지키지 않는다. 노트 본문의 맥락에서 무엇을 보여야 하는지 다시 정하고 처음부터 그린다.
            """#
    }()
}
