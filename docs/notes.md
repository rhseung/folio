# 노트

노트의 문법, 링크, 보기, 그 검사를 고칠 때 읽는다. 쓰는 사람용 형식 안내는 `NoteWritingGuide`(`folio note format`)가 원본이다.

## 문법과 렌더링

- 파서는 `FolioMarkdown`(`swift-markdown` 기반)이다. 확장 문법과 콜아웃 종류는 `docs/axes.md`의 "노트 문법"에 있다.
- 수식 문법은 노트마다 정하고(`math` frontmatter), 블록 하나만 다르게 쓸 때는 코드 펜스로 고른다(`MathFence`: `math`·`tex`·`latex`는 TeX, `asciimath`·`am`은 AsciiMath. `$$…$$`와 `$…$`은 노트 문법). 렌더러는 그 블록에 `data-math`를 단다. 편집 보기의 자동 완성, 스니펫, 말풍선, 기호 팔레트도 캐럿이 있는 펜스의 문법을 따른다(`SourcePlace`의 `fence`, `CompletionCatalog.at`). Claude 패널의 답은 `tex`·`latex` 펜스를 코드로 둔다(`HTMLRenderer.render(answer:)`).
- 어느 줄이 제목인지는 `NoteOutline` 하나가 정한다(본문 최상위 제목만. 코드, 수식, frontmatter, 콜아웃 안의 `#`은 제외). 옆 목차, 한 줄에 홀로 쓴 `[TOC]`(미리보기와 PDF에서 목차 카드), 제목 링크와 그 자동 완성이 함께 쓴다.
- 임베드와 블록 참조는 링크가 가리키는 부분(제목 아래, 블록)을 잘라 그리고, 고리와 깊이를 막는다. 노트는 앱이 찾아 준다(`NoteEmbeds`).
- 편집 보기의 입력 규칙(`sources/markdown/editing/`: 짝 기호, 목록 이어 쓰기와 번호, 스니펫, 수식 인자 이동, 자동 완성 질의, 표 편집, 굵게·기울임 `SourceEditing.toggle`)은 순수 함수로 두어 Mac과 iPad가 함께 쓴다. 굵게(⌘B)와 기울임(⌘I)은 서식 메뉴의 명령이고 키는 단축키 등록표에서 읽는다. iPad의 편집 메뉴와 ⌘B도 글에 속성을 입히지 않고 같은 마크다운 표시를 쓴다.
- 편집 보기(`app/platform/notes/editing/`, TextKit 2)는 원문에 글꼴과 색만 입힌다. 그림, 수식, 콜아웃, 임베드, 코드의 상자는 미리보기(`note-preview.swift`)만 그린다.
- 웹 번들(`sources/web`)은 미리보기와 Claude 패널의 페이지(KaTeX, 코드 하이라이팅, mermaid, 노트 CSS, 그림 크게 보기)와 편집 보기가 JavaScriptCore로 부르는 코드 하이라이팅이다. 편집 보기의 수식 말풍선과 자동 완성 미리보기도 같은 KaTeX와 노트 CSS로 숨은 페이지에서 그린다(`NoteMath`). 색은 `theme.swift`의 값을, 크기와 간격은 `app/design/tokens/note-look.swift`의 값을 `NoteStyle`이 CSS 변수로 넘기므로 CSS에 색과 크기를 적지 않는다. `sources/web/src/`를 고치면 `mise run build-web`을 돌린다.

## 노트 링크

- 노트 링크는 노트 ID로 건다: `[[note:<ID>|제목]]`, `[[note:<ID>#제목|표시]]`, `[[note:<ID>#^블록|표시]]`. 앱 링크 `folio://note/<ID>`로 열고 이름이 바뀌어도 깨지지 않는다.
- 손으로 쓴 `[[제목]]`은 과목 안에서 제목으로 찾고 ID 꼴로 바꾸지 않는다. 링크를 열 때와 미리보기가 그 노트를 그리거나 깨진 링크로 그릴 때 모두 `[NoteFile].linked` 하나로 찾는다.
- 블록 ID는 원문의 `^id`라 같은 노트 안에서 옮긴 블록은 따라가고, 다른 노트로 옮기면 찾지 못한다.
- 표 안에서도 `[[…]]`의 `|`는 칸을 나누지 않는다(Obsidian과 같다). Obsidian이 표에 쓰는 `[[대상\|이름]]`도 같은 링크로 읽는다.
- 링크 자동 완성은 고른 항목을 ID 꼴로 넣고 이름을 `|` 뒤에 붙인다: 노트 `[[note:<ID>|제목]]`, 자료 `[[material:<ID>#page=N|파일 이름]]`, 그 밖은 앱 링크 종류 이름 그대로(`[[exam:<ID>|중간고사]]`). 이미 쓴 `|이름`은 그대로 둔다. ID가 없는 블록을 고르면 대상 노트 끝 줄에 `^id`를 붙인다. 다른 노트면 `note write`(읽은 글과 다르면 거절)로, 쓰고 있는 노트면 편집 보기에서 쓴다.
- 복사한 주소를 괄호에 넣은 `[[folio://<종류>/<ID>…|이름]]`도 `[[<종류>:<ID>…]]`와 같은 링크로 읽고, 원문은 바꾸지 않는다. 이름이 없는 앱 링크는 미리보기에서 대상의 이름을 보인다(`Workspace.label(of:)`).
- `folio://` 주소를 노트에 붙이면 자동 완성과 같은 꼴로 들어간다. `<종류>:<ID>` 꼴이 없는 장소와 과목 페이지는 `[[folio://…|이름]]`으로 들어간다. 쓰고 있는 링크 안(`[[…`, `](…`), 코드, 수식에서는 붙인 그대로 둔다.
- 맨 주소는 미리보기에서도 링크가 되고, 끝의 문장부호(`.,;:!?`)는 주소에 넣지 않는다. 제목 앵커(`#제목`)만 문장부호로 끝날 수 있어 남긴다(`AppLink.trimmed`).

## 노트 이름과 옮기기

- 회차 노트의 이름 규칙은 `CourseFile.noteTitle(for:kind:calendar:)` 하나다(`docs/sessions.md`).
- 노트를 옮기거나 이름을 바꿀 때(`note mv`) 과목의 다른 노트(어느 폴더든)가 같은 이름이면 ` 2`를 붙인다. 제목 링크가 제목만으로 노트를 찾기 때문이다. course.json 경로, 첫 제목, 제목 링크와 ID 링크의 이름, 노트 안의 상대 경로(그림)가 따라 바뀌고, `cleanup undo`가 함께 되돌린다.
- `.tex` 노트는 Folio가 빌드한 PDF(`builtHash`가 맞는 `Study/<제목>.pdf`)도 같은 묶음으로 새 이름을 따라간다. 새 이름의 PDF가 이미 있으면 덮어쓰지 않고, Folio가 만들지 않은 같은 이름의 PDF는 옮기지 않는다.
- 노트를 둘 수 있는 폴더 이름은 `StandardLayout.noteFolderProblem` 하나가 정한다.
- 앱에서 옮기거나 이름을 바꾼 뒤에는 노트 페이지 머리에 "방금 옮긴 것 되돌리기"가 나온다(`MoveUndo`, `UndoMoveButton`).

## 그림과 위젯

- 그림은 `Notes/assets/<이름>.svg`, 위젯은 `.folio/widgets/<ID>.html`이다. 고쳐 쓸 때는 `show --json`의 해시와 디스크가 같을 때만 쓴다(`--expect`).
- 그림과 위젯, mermaid 도식은 같은 그림 스타일(`FolioDomain`의 `FigureStyle`)을 쓴다. 모양은 LaTeX 교과서의 그림이다. 색(라이트·다크), 선 굵기, stealth 화살촉, 글꼴 역할이 이 표 하나에 있고, 노트 형식 안내(`NoteWritingGuide`)도 클래스 이름과 선 굵기를 여기서 읽는다. 이 스타일은 새로 쓰는 그림과 위젯에만 들어가고, 그 전에 쓴 파일은 바꾸지 않는다.
- 그림은 이미지로 보여서 페이지 CSS를 읽지 못한다. 그래서 그림은 이름 있는 클래스(`.ink`, `.p-blue`, 선은 `.s-ink`)로만 칠하고, 쓸 때 `NoteFigureFinish`가 그림 엔진(`sources/web/src/figure.js`)을 JavaScriptCore로 돌려 마무리한다.
    - 스타일 표의 `<style id="folio-figure">`(다크 규칙 포함)와 쓴 화살촉(`url(#m-ink)`)의 `<marker>`를 `<defs id="folio-figure-defs">`에 넣는다.
    - `<text>`의 `$…$`를 MathJax SVG 출력(`fontCache: none`, mhchem)으로 LaTeX 글자 path로 바꾼다. 같은 글자는 `<defs>`에 한 번 두고 `<use>`로 가리킨다. 바꾼 라벨은 `<g data-source="원래 text">`에 들어가고, `note figure show`와 고쳐 쓰기는 이것을 걷어 쓴 사람이 쓴 모양으로 되돌린다. 그래서 같은 그림을 두 번 마무리해도 결과가 같다.
    - 라벨 겹침을 검사한다. 라벨끼리, 라벨과 선(선 굵기 절반 + 1.5px), 칠한 면의 경계, 그림 밖을 본다. 회전한 라벨은 그 좌표계에서 보고, 뒤에 그린 불투명한 도형이 가린 선 조각과 `s-grid` 격자는 뺀다. 낱말 폭은 CoreText의 시스템 글꼴로 잰다.
    - 선에 `data-through="점 id …"`가 있으면 그 id를 단 circle이나 ellipse의 중심이 선에서 1.5px 안에 있는지 본다. 광선이 초점을, 접선이 접점을 지나는 그림은 눈대중한 좌표가 몇 px만 어긋나도 틀리므로, 그리는 쪽이 지날 점을 적고 엔진이 잰다. 없는 id도 알린다.
- 쓰기 전 검사(XML, 스크립트, 바깥 참조, 클래스 밖의 색, 긴 글, 큰 화살촉)는 `NoteFigure.problems`, 위젯의 바깥 주소는 `NoteWidget.problems`다. 쓸 때 넣은 `<style>`과 `<defs>`는 검사하지 않는다.
- 위젯 frame에는 위젯 스크립트보다 먼저 `NoteWidgetKit`이 그림 스타일의 CSS 변수(`--ink`, `--p-blue` …), shadcn/ui 모양의 기본 컨트롤 스타일(`:where()`라서 위젯의 스타일이 이긴다), KaTeX(mhchem 포함)와 `$…$` 자동 조판을 넣는다(`sources/web/src/widget.js`, `widget.css`).
    - 그림과 같은 stealth 촉(`m-ink`, `m-p-blue` …)도 넣는다. 스타일 표의 `FigureStyle.widgetMarkers`가 클래스 대신 CSS 변수로 칠한 `<marker>`이고, 위젯이 `url(#m-ink)`로 가리킨다. 촉을 담은 크기 0인 `<svg id="folio-figure-markers">`는 body를 다 읽은 뒤 html의 마지막 자식으로 넣는다. html에 `insertAdjacentHTML`을 쓰면 빈 head와 두 번째 body가 생기므로 template에서 읽어 붙인다. 위젯의 `querySelector('svg')`가 위젯 자신의 그림을 찾고 `body.innerHTML`을 바꿔도 촉이 남게 하려는 것이다.
    - 위젯이 직접 그린 `<marker>` 중 fill이 없거나(SVG 기본값인 검정) 고정 색으로 칠한 것은 `NoteWidget.markerProblems`가 찾고 `note widget render`가 알린다. 스크립트 문자열 안의 촉도 보려고 글로 찾으므로 쓰기를 막지는 않는다. 이미 쓴 위젯 파일은 고치지 않는다.
- mermaid 도식은 `mermaid.js`가 beautiful-mermaid의 색 변수를 그림 팔레트로 다시 정의하고 채운 화살촉을 stealth 촉으로, `$…$`를 같은 폭의 자리 글자로 배치한 뒤 LaTeX path로, 코드를 `\texttt` path로 바꾼다. 테마 옵션으로 바꿀 수 없는 라이브러리 상수는 `sources/web/patches/beautiful-mermaid.mjs`가 묶을 때 고친다. 고칠 글이 정확히 한 번 나오지 않거나 판이 다르면 `build-web`이 실패하므로, beautiful-mermaid 판을 올리면 이 파일을 다시 맞춘다. 색이 CSS 변수라서 다크로 바뀌어도 다시 그리지 않는다.
- 그림 엔진과 위젯 kit은 앱과 CLI가 함께 쓰므로 `build-web`이 `sources/actions/notes/`에 묶고 `FolioActions`의 리소스로 둔다.
- 그려 보기(`render`)는 쓸 때와 같이 마무리한 그림을 그리고 그 검사 결과를 알린다. 색은 앱 테스트 `NoteThemeCopyTests`가 앱의 `NoteWidgets.themeCSS`에서 만든 사본(`sources/cli/render/generated`)이다. `theme.swift`나 `themeCSS`를 바꾸면 `TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app`으로 다시 만든다.

## 노트 보기 회귀 검사

노트 보기(편집 보기와 미리보기)는 `mise run test-app`의 회귀 검사가 지킨다(#265).

- `NoteScreenTests`: `all-markdown.md`(모든 문법)와 화면보다 긴 노트를 라이트·다크, 폭 900과 480으로 그려 기준 이미지와 비교한다.
- `NoteLayoutTests`: 블록이 열 안에 있는지, 연 직후와 스크롤한 뒤 끝까지 그려지는지, 노트 끝 아래로 스크롤되는지 픽셀로 본다.
- `NoteClickGridTests`: 격자의 모든 점이 노트(또는 그 자리의 위젯, 가로 스크롤 블록)에 닿는지, 편집 보기에서는 클릭한 자리에 캐럿이 놓이는지 본다.
- `NoteHangulTests`: 조합 중인 글자가 SwiftUI 갱신과 저장을 견디고 파일에 들어가는지 본다. iPad 편집 보기는 `NoteHangulPadTests`(`mise run test-ipad`)가 본다.
- 검사는 보기를 `NoteBench`(`tests/unit/app/support/note-bench.swift`)로만 다룬다. 그린 픽셀, 히트한 뷰, 캐럿 위치, 스크롤 범위만 보고 TextKit이나 웹 페이지의 내부는 보지 않는다. 편집 보기의 구현을 바꿀 때는 이 파일과 기준 이미지만 바꾸고, 배치, 클릭, 한글 검사는 그대로 통과해야 한다.
- 미리보기의 동작(블록 단위 갱신, 할 일 체크, 콜아웃 접기 유지, 편집 보기 따라가기, 위젯 iframe의 격리와 높이, 임베드와 블록 참조 카드, 깨진 링크, 그림 크게 보기)은 `NotePreviewTests`, `NoteWidgetTests`, `NoteEmbedPreviewTests`가, 편집 보기의 블록 참조 카드는 `NoteReferenceCardTests`가 본다.
- 기준 이미지(`tests/unit/app/references/notes`)는 CI 러너가 그린 것만 커밋한다. 글꼴 렌더가 macOS마다 달라서 비교는 같은 그림을 그린다고 확인한 macOS(`machine.txt`, 한 줄에 하나)에서만 하고 다른 Mac에서는 건너뛴다. CI 러너 풀에는 여러 macOS 빌드가 섞여 있어서 목록에 여럿을 둔다. CI는 `FOLIO_NOTE_SCREENS_STRICT`를 켜서 러너의 macOS가 목록에 없으면 실패한다. `mise run note-screens`는 들인 그림이 기준 이미지와 모두 같으면 그 실행의 macOS를 목록에 더하고, 하나라도 다르면 목록을 그 macOS 하나로 바꾼다. 기준 이미지를 바꾸는 PR은 본문에 이전과 이후 이미지를 붙인다.
- `test-app`은 없거나 달라진 이미지를 새 이미지와 차이 이미지(`-diff.png`)로 `FOLIO_NOTE_SCREENS`(기본 `.build/note-screens`)에 남기고, CI는 실패할 때 `note-screens` 아티팩트로 올린다. 의도한 변화인지 확인한 뒤 `mise run note-screens -- <CI 실행 ID>`로 들인다. 로컬에서 그린 이미지는 기준으로 쓰지 않는다. PR에 붙일 그림으로 펼친 판(`NoteRender.sheet`)은 `FOLIO_NOTE_SCREENS/sheets`에 남고, CI는 `note-sheets` 아티팩트로 올린다.
- 새 노트 보기 검사는 `mise.toml`의 `notes` 목록에 넣기 전까지 `FOLIO_TEST_PART=rest`에서 돈다.
- `TEST_RUNNER_FOLIO_NOTE_RENDER=<폴더>`를 주고 `NoteSourceTests`를 돌리면 `all-markdown.md`의 편집 보기 PNG가 남는다.
