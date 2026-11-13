/// How a Folio note is written, for an agent writing one: `folio note format` prints it, the panel reads it through
/// that tool, and `folio skill` carries it. Kept dense: it goes into Claude's context each time it is read.
/// The dark colors are those of the hand-made figures that worked in both appearances, set beside the note tokens they
/// stand for; a picture shown as an image can't read the page's variables, so it carries the hex values itself.
public enum NoteWritingGuide {
    public static let text = #"""
        # Folio 노트 형식

        노트는 마크다운이다. 명령 이름은 MCP 도구에서 공백이 `_`가 된다(`note figure add` → `note_figure_add`).

        ## 수식, 콜아웃, 목차
        - 수식은 `$…$`, `$$…$$`. 문법은 노트의 `math`(기본 TeX). 블록 하나만 다르면 ```` ```asciimath ```` 펜스.
        - 콜아웃: `> [!종류] 제목` 다음 줄부터 `> 본문`. `[!종류]-`는 접힌 채, `[!종류]+`는 펼친 채 접을 수 있다.
          종류: definition theorem lemma corollary proof example counterexample remark note tip warning important question solution summary abstract info danger. definition·theorem·lemma·corollary·example·counterexample은 번호가 붙는다(제목에 `1.2`를 쓰면 그 번호).
        - 한 줄에 홀로 쓴 `[TOC]`는 목차.

        ## 링크
        - 노트 `[[note:<ID>|이름]]`, 제목 `[[note:<ID>#제목|이름]]`, 블록 `[[note:<ID>#^블록|이름]]`(블록 ID는 문단 끝의 ` ^id`). `![[…]]`는 그 부분을 끼워 보인다.
        - 자료의 쪽 `[[material:<ID>#page=N|파일 이름]]`. 그 밖은 종류 이름 그대로: `[[exam:<ID>|중간고사]]`, `session`, `unit`, `assignment`.
        - ID는 `note list`, `material list` 같은 목록의 `--json`에서 읽는다.

        ## 도식
        ```` ```mermaid ```` 펜스는 앱이 노트 색으로 그린다. 색과 테마를 적지 않는다. mermaid로 안 되는 그림만 SVG로 그린다.

        ## 그림(SVG)
        - `note figure add <과목> <이름>.svg --svg <파일>`이 `Notes/assets`에 쓴다. 노트에는 `![설명](assets/<이름>.svg)`(하위 폴더의 노트는 `../assets/`). 고칠 때는 `note figure show`의 `hash`를 `note figure write --expect`에.
        - 노트는 그림을 이미지로 보인다. 스크립트, 바깥 파일·글꼴·이미지, 페이지의 CSS 변수는 쓸 수 없다. 이미지는 `data:` 주소로 넣는다.
        - `viewBox`를 두고 `width`/`height`는 빼거나 `viewBox`와 같게 둔다. 노트 열 폭(390~720pt)에 맞춰 줄어드니, 좁아도 읽히게 글자는 13px 이상, `font-family: -apple-system, system-ui, sans-serif`.
        - 바탕은 투명하게 둔다(노트 카드가 비친다). 면이 필요할 때만 칠한다.
        - 색은 클래스로 묶고 `<style>`에 다크 규칙을 꼭 둔다. 없으면 다크 모드에서 선과 글자가 사라진다:
          ```
          <style>.ink{fill:#222}.stroke{stroke:#222}.soft{fill:#f7f5f1}.blue{fill:#2f6fd6}
          @media (prefers-color-scheme: dark){.ink{fill:#E6E2DB}.stroke{stroke:#E6E2DB}.soft{fill:#2A2825}.blue{fill:#7C9BFF}}</style>
          ```
        - 라이트 → 다크(가까운 노트 색 토큰): 글자·선 #222 → #E6E2DB(`--text`), 면 #f7f5f1 → #2A2825(`--fill`), 보조 선·흐린 글자 #9a9a9a → #A29D95(`--text-3`), 파랑 #2f6fd6 → #7C9BFF(`--c-definition`), 주황 #d9822b → #E7A04A(`--c-warning`), 빨강 #d1453b → #F07A5A(`--c-danger`), 초록 #2e9d6a → #5CC48F(`--c-example`).

        ## 위젯
        - `note widget add <과목> --html <파일>`이 `.folio/widgets/<ID>.html`을 쓰고 ID를 돌려준다. 노트에는
          ```` ```cb-widget ```` 펜스 안에 `{"id": "<ID>", "height": 320}`. 고칠 때는 `note widget show`의 `hash`를 `note widget write --expect`에.
        - HTML 파일 하나가 격리된 frame에서 돈다. 인라인 `<script>`와 `<style>`만 되고, 네트워크·CDN·바깥 파일, 링크와 페이지 이동, 저장(상태는 다시 열면 처음부터)은 안 된다. 이미지는 `data:`/`blob:`.
        - 노트 색이 CSS 변수로 미리 들어 있고 라이트·다크를 따라간다: `--text --text-2 --text-3 --line --line-soft --fill --code-fill --card --accent --accent-ink`, `--c-definition --c-theorem --c-example --c-warning --c-danger --c-neutral`. 색은 이 변수로만 쓴다. 바탕은 투명, `body`는 여백 0, 14px 시스템 글꼴.
        - 높이는 내용을 따라 자라고 위젯 안은 스크롤되지 않는다. `height`는 처음 높이다. `100vh`처럼 frame을 따르는 높이를 쓰면 `height`가 그대로 남는다. 폭은 노트 열(390~720pt)이니 고정 폭 대신 폭에 맞추고, 넓은 것은 가로 스크롤.

        ## 그려 보기
        쓰기 전에 `note figure render <과목> --text <SVG>`, `note widget render <과목> --text <HTML>`로 라이트·다크, 폭 480·900에서 그린 그림을 본다(이미 쓴 것은 이름이나 ID로). 겹친 글자, 잘린 부분, 다크에서 사라진 색, 위젯의 콘솔 오류를 고친 뒤 쓴다.
        """#
}
