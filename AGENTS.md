# Folio

과목을 중심으로 강의 자료, 노트, 손필기, 복습, 퀴즈, 과제, 성적을 관리하는 Apple 기기용 네이티브 앱입니다. 무엇을 만들지와 남은 일은 GitHub 이슈와 [Project](https://github.com/users/rhseung/projects/10)에 있습니다. 이 파일에는 어떻게 만들지에 대한 규칙을 적습니다. 작업을 시작하기 전에 해당 이슈와 그 상위 이슈를 먼저 읽습니다.

## 소통 규칙

- 사용자와는 한국어로 대화한다. 영어로 답하지 않는다.
- 코드의 식별자, 주석, 커밋 메시지는 영어로 쓴다.
- PR 본문은 한국어로 쓴다. 사용자가 읽고 무엇이 바뀌었는지 이해해야 하기 때문이다. 기능은 이슈 번호만 쓰지 않고 이름과 함께 쓴다("툴바 탭(#304)"). PR 제목은 스쿼시 커밋 제목이 되므로 커밋 규칙대로 영어로 쓴다. 스쿼시 커밋의 본문은 PR 본문이라 한국어가 된다.
- 앱의 UI 문자열은 한국어로 쓰고 String Catalog(`Localizable.xcstrings`)에 키로 둔다. 아래 "문자열 키" 절을 따른다.
- 이슈와 다르게 구현해야 할 이유가 생기면 구현하기 전에 사용자에게 묻는다. 이슈에 없는 기능을 임의로 추가하지 않는다. 사용자와 새로 정한 동작은 그 이슈 본문에 적는다.

## 기술 기준

- 최소 지원 버전은 macOS 26, iPadOS 26이다.
- Swift 6 언어 모드를 쓰고 strict concurrency 검사를 켠다.
- UI는 SwiftUI로 만든다. AppKit과 UIKit은 SwiftUI로 할 수 없는 부분에만 쓴다. 예를 들어 PencilKit 캔버스와 PDFKit 뷰가 여기에 해당한다.
- 직접 구현보다 잘 관리되는 라이브러리를 먼저 쓴다. 표준 라이브러리와 Apple 프레임워크로 되지 않는 일이면, 직접 짜기 전에 널리 쓰이고 유지되는 Swift 패키지가 있는지 찾는다. 라이브러리가 데이터 원칙을 어기는 경우(예: 노트 frontmatter의 원문을 보존하지 못하는 YAML 파서)에만 직접 구현하고, 그 이유를 코드 주석에 남긴다.
- 외부 의존성은 Swift Package Manager로만 추가한다. 새 의존성은 넣은 뒤 사용자에게 무엇을 왜 넣었는지 알리고, 커밋 메시지에도 남긴다. 예외는 수식 변환과 코드 하이라이팅, 노트 미리보기와 Claude 패널에 쓰는 웹 번들(`web/`)로, npm 패키지를 정확한 버전으로 고정하고 `mise run build-web`으로 `app/resources/web/`에 묶는다. 묶은 결과는 커밋해서 앱 빌드에 node가 필요 없게 한다. 또 하나의 예외는 `.tex`를 빌드하는 TeX 엔진 Tectonic이다. iPadOS는 앱이 다른 프로그램을 띄우지 못하게 하므로, Mac과 iPad 모두 Tectonic을 정적 라이브러리(`FolioTectonic.xcframework`)로 앱 안에 넣는다. 라이브러리는 커밋하지 않는다. `tectonic.yml` 워크플로가 `tectonic/`(브리지 crate와 Tectonic 패치)와 `scripts/tectonic-build.sh`에서 빌드해 프리릴리스 자산으로 올리고, `mise run tectonic`이 `tectonic/pin.json`의 sha256으로 확인해 받는다. Tectonic 자체를 고친 부분(iOS에서 CoreText로 글꼴 찾기, 한 프로세스에서 빌드를 거듭할 때 중단된 xdvipdfmx가 남긴 전역 상태 되돌리기)은 `tectonic/patches/`의 패치로 두고 빌드할 때 적용한다. TeX 패키지와 서식은 데이터라 앱이 Tectonic의 번들 서버에서 받아 Caches에 둔다.

## 프로젝트 구조

플랫폼과 무관한 로직은 Swift 패키지로 분리해서 `swift test`로 Xcode 없이 테스트할 수 있게 합니다.

```text
folio/
  AGENTS.md
  docs/
    DESIGN.md         # 디자인 시스템: 원칙, 토큰과 구성 요소의 쓰임, 패턴
  packages/
    folio-core/       # 모델, 저장소, 파일 추적, 성적과 GPA 계산, 복습 스케줄러. UI 코드 없음
    folio-markdown/   # 마크다운 파서와 확장 문법(콜아웃, 위키링크, 블록 참조, 각주, `[TOC]`, cb-table, cb-widget), 편집 보기의 입력 보조와 표 편집 변환(`editing/`)
    folio-ai/         # Claude 연동 계층. 프로바이더 추상화, 맥락 구성, 작업별 요청과 응답 스키마
  app/                # 멀티플랫폼 앱 타깃(macOS, iPadOS)
  app-tests/          # 화면 모델 테스트와 노트 보기 회귀 검사(`mise run test-app`), iPad 테스트는 ipad/(`mise run test-ipad`)
  web/                # 노트 미리보기와 Claude 패널의 페이지(KaTeX 수식, 코드 하이라이팅, mermaid 그림, 노트 CSS, 미리보기의 그림 크게 보기), 편집 보기가 JavaScriptCore로 부르는 코드 하이라이팅. 편집 보기의 수식 말풍선과 자동 완성 미리보기도 미리보기와 같은 KaTeX와 노트 CSS로, 숨은 페이지에서 그린다(`NoteMath`). 번들은 app/resources/web
  tectonic/           # TeX 엔진 Tectonic을 앱에 넣는 정적 라이브러리의 원본: 브리지 crate(bridge/), Tectonic 패치(patches/), 앱이 받는 판(pin.json)
```

- `FolioCore`는 SwiftUI를 import하지 않는다.
- 계산 로직(환산 점수, GPA, 복습 간격, 우선순위)은 순수 함수로 만들고 단위 테스트를 붙인다.
- Claude 호출은 `FolioAI`의 프로토콜 뒤에 둔다. 테스트에서는 가짜 프로바이더를 쓴다.

### 레이어

의존은 아래 방향으로만 흐른다. 거꾸로 import하지 않는다. 모듈 경계로 나눴으므로 어기면 컴파일이 실패한다.

```text
App (SwiftUI), FolioCLI  ->  FolioActions  ->  FolioAI, FolioStorage  ->  FolioDomain
App (SwiftUI), FolioCLI  ->  FolioIndex  ->  FolioStorage   (검색 색인)
App (SwiftUI)  ->  FolioLMS  ->  FolioDomain   (GIST LMS 읽기)
FolioStorage, FolioActions, App  ->  FolioMarkdown   (노트 frontmatter와 렌더링)
FolioActions  ..>  FolioMacros   (@Action 매크로. 컴파일 때만 쓰고 앱에 링크되지 않는다)
FolioGen  ->  FolioActions   (생성한 CLI 명령을 folio-cli/generated에 쓴다)
```

| 모듈 | 위치 | 맡는 일 | 하지 않는 일 |
| --- | --- | --- | --- |
| `FolioDomain` | `packages/folio-core` | 엔티티, 값 타입, 표준 구조 규칙, 성적·GPA·복습 계산. 디스크에서 읽은 내용은 `FolderTree` 같은 값으로 받는다 | 파일 입출력(`FileManager`, `NSFileCoordinator`), UI, 네트워크 |
| `FolioStorage` | `packages/folio-core` | GIST 폴더 읽기와 쓰기, JSON 스키마 버전과 마이그레이션, 원자적 쓰기, 기기별 로그, 파일 추적 | 규칙 판단. 판단은 Domain에 맡긴다 |
| `FolioMarkdown` | `packages/folio-markdown` | 마크다운 파서와 확장 문법(한 줄에 홀로 쓴 `[TOC]`는 미리보기와 PDF에서 목차 카드), frontmatter, HTML 렌더러. 수식 문법은 노트마다 정하고(`math` frontmatter), 블록 하나만 다르게 쓸 때는 코드 펜스로 고른다(`MathFence`: `math`·`tex`·`latex`는 TeX, `asciimath`·`am`은 AsciiMath. `$$…$$`와 `$…$`은 노트 문법). 렌더러는 그 블록에 `data-math`를 달고, 편집 보기의 자동 완성·스니펫·말풍선·기호 팔레트도 캐럿이 있는 펜스의 문법을 따른다(`SourcePlace`의 `fence`, `CompletionCatalog.at`). Claude 패널의 답은 `tex`·`latex` 펜스를 코드로 둔다(`HTMLRenderer.render(answer:)`). `swift-markdown` 기반. 어느 줄이 제목인지는 `NoteOutline` 하나가 정하고(본문 최상위 제목만. 코드, 수식, frontmatter, 콜아웃 안의 `#`은 제외) 옆 목차, `[TOC]`, 제목 링크(`#제목`)와 그 자동 완성이 함께 쓴다. 임베드와 블록 참조는 링크가 가리키는 부분(제목 아래, 블록)을 잘라 그리고, 고리와 깊이를 막는다. 노트는 앱이 찾아 준다(`NoteEmbeds`). 편집 보기의 입력 규칙(`editing/`: 짝 기호, 목록 이어 쓰기와 번호, 스니펫, 수식 인자 이동, 자동 완성 질의)도 여기 순수 함수로 두어 Mac과 iPad가 함께 쓴다 | 다른 Folio 모듈에 의존 |
| `FolioAI` | `packages/folio-ai` | Claude API 호출(Swift SDK가 없어 문서화된 HTTP 형식 그대로), 작업별 모델과 effort 표, 맥락 구성, 구조화된 응답 스키마, 사용량과 비용 | 파일 쓰기. 결과는 제안으로만 돌려준다 |
| `FolioActions` | `packages/folio-core` | 데이터를 바꾸는 모든 동작. Domain의 변환과 Storage의 쓰기, 폴더 생성, 로그를 한 액션으로 묶는다. 액션 목록의 단일 출처 | UI, 출력 형식. 앱과 CLI가 같은 구현을 부른다 |
| `FolioIndex` | `packages/folio-core` | 기기별 로컬 SQLite 검색 색인(GRDB, FTS5 trigram). 바뀐 과목만 다시 읽고 PDF 본문을 뽑아 둔다. 캐시 폴더에 두며 지워도 다시 만든다 | GIST 폴더에 쓰기. 순위와 발췌는 Domain의 `SearchIndex`에 맡긴다 |
| `FolioLMS` | `packages/folio-core` | GIST LMS(Coursemos) 읽기. 학생에게는 웹 서비스 토큰이 없어 웹 세션으로 대시보드, 과제, 자료, 공지 페이지를 읽고(`LMSPages`, SwiftSoup), 세션이 끝나면 iCloud 키체인에 둔 로그인으로 한 번 다시 로그인한다(`LMSClient`, `LMSCredentialStore`). 거절되면 다시 시도하지 않는다. 요청 사이 0.5초를 둔다 | 파일 쓰기와 제안 판단. 읽은 값(`LMSSnapshot`)과 제안 규칙(`LMSInbox`)은 Domain, 받기는 `lms accept` 액션이다 |
| `FolioCLI` | `packages/folio-core` | 터미널 도구 `folio`의 명령 라이브러리. 실행 파일은 진입점만 있는 `FolioCommand`다(실행 타깃의 테스트 빌드에는 카탈로그 심볼이 생기지 않아서다). 모든 액션을 `<대상> <동작>` 명령으로 열고, 사람용 출력과 `--json` 출력을 만든다. 노트 그림과 위젯의 그려 보기(`render/`의 `PageRender`)는 macOS에서 화면 밖 `WKWebView`로 그린다. 앱의 노트 색은 링크할 수 없어 생성한 사본(`NoteTheme`)을 쓴다 | 액션 로직. 명령은 인자를 해석해 `FolioActions`를 부르고 결과를 그리기만 한다 |
| `FolioMacros` | `packages/folio-core` | `@Action`과 필드 표시(`@Arg`, `@New`, `@Off`, `@Hidden`, `@CLIName`, `@FromFile`, `@Folder`). 선언에서 입력 형식, init, 코딩, `spec`을 만들고 실수(맨 `UUID`, 없는 `{필드}`, 확인 문구 없는 삭제)를 컴파일 오류로 막는다 | 실행 코드. 앱과 CLI에 링크되지 않는다 |
| `FolioGen` | `packages/folio-core` | `@Action` 액션의 `spec`에서 `folio-cli/generated/commands.swift`를 만든다. 결과는 커밋한다. 손 명령(`cli: .manual(reason:)`)은 건너뛴다 | FolioCLI에 의존. 생성 파일이 깨져도 다시 만들 수 있게 한다 |
| `FolioFixtures` | `packages/folio-core` | 테스트와 개발 실행에 쓰는 가짜 GIST 폴더. 파일을 코드에 두고 쓸 때 디스크에 펼친다. 공개 저장소에 과목 파일 폴더를 두지 않기 위해서다. 화면 확인용 상황(`Scenario`)은 표준 폴더에 고정된 시각 기준으로 액션을 돌려 만든다 | CLI에 링크되지 않는다. 앱에서는 `#if DEBUG`의 `Workspace.scenario`(미리보기와 화면 밖 렌더)만 쓴다 |
| App | `app/` | 화면. `app/`(진입점과 탐색), `design/`(디자인 토큰과 공용 구성 요소), `features/<화면>/`, `platform/`(PencilKit, PDFKit, WKWebView 연결, `file-view/`의 파일 보기(형식별 렌더러), `note-preview.swift`의 노트 미리보기와 `note-text/`의 TextKit 2 편집 보기. 편집 보기는 원문에 글꼴과 색만 입히고, 그림·수식·콜아웃·임베드와 코드의 상자는 미리보기만 그린다), `resources/` | 파일 시스템 직접 접근과 `course.json` 값의 직접 변경. 반드시 `FolioActions`를 거친다 |

- 앱에 새 데이터 조작을 넣을 때는 `FolioActions`에 `@Action`으로 액션을 선언하고, 같은 변경에서 테스트를 함께 넣는다. 액션에 CLI 명령이 없으면 테스트가 실패한다.
    - 필드의 형식이 입력을 정한다. 가리키는 항목은 `Exam.ID`처럼 종류의 ID로 쓰고(경로로 가리키는 노트는 `Note.Path`), `set`의 필드는 `Patch<T>`(빠지면 그대로, `T?`면 `none`/`null`로 지운다. 액션이 지금 값 위에 준 칸만 덮으므로 CLI가 지금 값을 읽어 빈 칸을 채우지 않는다. 시트처럼 값 전체를 가진 화면은 모든 칸을 `.set`으로 보내거나 `Patch.changed(이전, 새 값)`으로 바뀐 칸만 보낸다), 새 항목의 ID는 `@New`, 위치 인자는 `@Arg`로 쓴다. `///` 주석이 도움말이다.
    - CLI 입력의 모양도 선언에 적는다. 위치 인자의 순서는 필드 순서이고, 과목 인자 뒤의 항목 인자는 `<과목>/<항목>` 하나로 받는다(목록이면 둘째부터 항목만). 과목을 `Course.ID?`로 두면 빼서 모든 과목에 한다. 다른 옵션 이름은 `@CLIName("unit")`, 파일에서 읽는 값(문자열은 글, 그 밖은 JSON, `-`는 표준 입력. 목록을 파일마다 받으면 `perItem: true`)은 `@FromFile`, 실행한 곳 기준의 폴더 경로는 `@Folder`, 끄는 플래그는 `@Off("undo")`, `05_Matchings.pdf:3-12`나 `6:B0`처럼 한 단어를 읽어 값을 만드는 입력은 `@Parsed("<값 이름>", "<쓰는 꼴>")`(그 형식이 FolioCLI의 `CLIText`를 따르고 이름도 거기서 찾는다)로 쓴다. 빠지면 지금 것으로 채울 값(지금 학기)은 옵셔널로 두고 액션이 채운다. 계획 항목과 카드처럼 다른 항목 안에서 찾는 ID는 그 항목 필드가 있으면 그 안에서 찾는다. `made`가 `moves.jsonl` 묶음이면 `undoable: true`로 되돌리는 법을 보인다.
    - 확인 문구와 완료 문구는 `{필드}` 자리표시자로 쓰고, ID는 실행하기 전에 이름으로 바뀐다. `.removes`와 `.moves`는 `confirm:`이 있어야 컴파일된다.
    - 선언한 뒤 `mise run gen-cli`로 CLI 명령을 다시 만든다. 생성기가 다루지 못하는 입력(한 옵션을 두 필드로 나누기, 플래그 여럿이 값 하나가 되기, 액션 여러 번 돌리기, 해시 비교)만 손으로 쓰고 `cli: .manual(reason: "...")`에 이유를 적는다. 이유가 없으면 `actions --check`가 실패한다. 손 명령도 같은 액션 하나를 `perform(spec:)`으로 부른다.
    - 규칙은 액션이 아니라 `FolioDomain`의 모델(`course-rules.swift`의 `Document.model`)에 둔다. 모든 저장이 그 규칙으로 검사한다.
    - 화면은 규칙을 다시 적지 않는다. 버튼을 켜고 끌 때는 `workspace.can(액션)`, 막힌 이유는 `refusal`, 확인 문구는 `confirmation`으로 묻는다. 앱이 보여 주는 문서로 미리 실행해 본다.
    - `confirm:`이 있는 액션은 `workspace.ask(액션)`으로 실행하고 결과를 모델의 `pending`에 둔다. 뷰는 `.confirming($model.pending)`으로 묻고, 막힌 액션이면 묻지 않고 이유를 보여 준다. 확인 문구를 화면에서 따로 쓰지 않는다.
    - 여러 항목을 한 번에 바꾸는 버튼은 액션을 반복해 부르지 않고 목록을 받는 액션 하나로 실행한다. 그래야 한 번 묻고, 하나가 막히면 아무것도 쓰기 전에 멈춘다.
- 새 관심사가 생기면 위 표에 모듈을 추가하고 방향을 정한 뒤 만든다.

### 구조 축

`@Action`처럼 한 번 선언하고 여러 곳이 같은 선언을 읽는 구조를 축이라 부른다. 새 기능은 맞는 축 위에 얹고, 같은 일을 화면마다 따로 구현하지 않는다.

- 축은 첫 소비자 두세 개와 함께 만든다. 소비자 없이 미리 만들지 않는다.
- 값의 모양과 규칙은 `FolioDomain`에 두고, 앱은 그 값을 그리기만 한다.

| 축 | 하나로 모으는 것 | 상태 |
| --- | --- | --- |
| 액션 `@Action` | 데이터를 바꾸는 모든 동작. 앱, CLI, MCP가 같은 선언을 쓰고, CLI 명령은 선언에서 생성한다(손 명령은 이유를 적는다) | 있음 |
| 표준 구조 `standard-layout.swift` | 폴더와 파일 이름 | 있음 |
| 앱 링크 `AppLink` | 앱 안의 모든 대상을 가리키는 `folio://<종류>/<ID>[#page=N\|#^블록\|#제목\|#t=12:30]` 주소(`t`는 녹음의 재생 위치). 과목의 페이지는 `folio://course/<ID>/<페이지>`, 설정 탭은 `folio://settings/<탭>`이다(`general`, `record`, `class`, `notes`, `review`, `notifications`, `claude`, `lms`, `backup`, `about`. 합쳐진 옛 탭 이름 `profile`, `letters`, `recording`도 읽어 학적, 수업 탭으로 연다). 종류마다 담는 곳(`home`), 받는 앵커(`anchors`), 페이지 경로(`hasPages`)는 `AppLink.Kind` 한 곳에 있고 주소 해석, CLI 검사, `Workspace.entry`가 그 값을 읽는다. 종류별 `switch`에는 `default:`를 두지 않아 새 종류는 모든 곳이 다룰 때까지 컴파일되지 않는다. 앱은 `\.openLink`(여는 위치는 여기·옆 칸·새 탭·새 창)로만 열고, 칸마다 `Navigator`가 뒤로·앞으로 기록을 둔다. 새 탭은 macOS 창 탭이 아니라 창이 툴바 줄에 직접 그리는 탭이다(`WindowTabs`, 탭 목록과 고른 탭은 값 `TabStrip`). 회차, 과제, 시험, 카드, 문제집 링크는 그 목록 페이지를 열고 그 항목으로 스크롤해 표시한다(`\.linkFocus`, `.linkTarget`). 자료의 쪽은 주소에 실려 기록의 지금 걸음을 고친다. 사이드바, 검색, 노트와 파일의 링크, Claude 패널의 답, 바깥에서 온 `folio://`(앞에 있는 창의 새 탭에서 열고 그 탭을 고르며 앱을 앞으로 가져온다), `folio open`이 쓴다. 같은 scheme의 두 주소는 `AppLink`가 아니다. 손으로 쓴 `[[제목]]`이 되는 `folio://note/<제목>`은 그 노트가 있는 과목에서 `[NoteFile].linked`로 찾고(`AppLink.noteTitle`), `folio://action/…`은 Claude 패널의 버튼이라 종류 이름으로 쓸 수 없다(`AppLink.actionHost`) | 있음 |
| 화면 계약 `ScreenView` | 모든 화면이 주소 하나를 그리고 전체·칸·좁은 폭(1440·720·390)에서 넘치거나 잘리지 않는다. 주소에서 화면을 고르는 곳은 `Screen(entry)` 하나이고, `ScreenFitTests`가 세 폭을 검사한다 | 있음 |
| 칸 배치 `PaneLayout` | 탭 하나의 칸들(주소, 비율, 초점, 누른 순서)과 접기 규칙. 칸마다 기록(`Navigator`)과 위치 표시가 따로 있고(`TabPanes`), 툴바의 위치 표시와 뒤로·앞으로는 초점 칸을 따른다. 창 폭이 모자라면 초점 칸이 든 이어진 칸들만 펼치고 나머지는 양 끝의 묶음(띠 하나)으로 접는다. 폭이 줄면 펼친 칸의 양 끝 중 더 오래 안 누른 쪽이 묶음으로 가고, 묶음에서 고른 칸까지 펼친 칸들이 가장 짧게 밀려 가며, 손으로 접은 칸만 제자리 빗금 띠로 남는다(`PaneLayout.fold`, `PaneRow`). "옆 칸에서 열기"(`LinkPlacement.beside`)가 칸을 연다. 툴바 탭이 줄어드는 순서는 `TabFit`이 정한다. Claude는 칸마다가 아니라 탭에 하나이고(`WindowClaude`), 맥락에 칸 목록을 초점 칸부터 넣는다(`ContextBuilder.panes`). 칸이 둘 이상이고 노트와 녹음이 한 회차의 것인 탭(`PaneLayout.session(in:)`)은 바뀔 때마다 그 회차의 배치로 이 기기에 남고(`PaneMemory`, `SessionLayoutSaver`), 칸이 하나인 탭이 그 회차의 노트나 녹음을 열거나 수업 시작이 나눠 보기 탭을 열면 남긴 배치로 돌아온다(`PaneMemory.restoring`). 노트 보기 방식은 칸에 함께 남는다(`PaneNotes`). PDF 칸은 폭이 바뀌어도 보던 자리를 지킨다(`SteadyPDFView`). 칸 수에는 한도가 없다. 몇 칸을 펼칠지는 기기가 아니라 그 순간의 칸 줄 폭과 누른 순서만으로 정하고(`PaneLayout.fold`, 칸 최소 폭 360pt), 폭이 줄면 칸을 빼거나 새 탭으로 떼지 않고 묶음으로 접기만 한다. 자리가 없을 때 옆 칸에서 열면 새 칸이 초점으로 펼쳐지고 반대쪽 끝 칸이 묶음으로 간다. 다른 기기에서 남긴 배치와 이름 붙인 배치도 칸을 줄이지 않고 연다 | 있음(#62). 탭 메뉴의 "배치 ▸"가 기본 배치(`PanePreset.builtIn`)와 `settings.json`의 내 배치(`Settings.panePresets`)를 고르고 지금 배치를 저장하며, 수업 시작은 설정에서 고른 배치로 연다(`Settings.classStartPreset`) |
| 제안 | Claude가 내놓는 분류, 추출, 일정을 승인 화면으로 받는 공통 구조 | #90 |
| 파일 보기 렌더러 | 형식 판단과 형식별 보기. `FolioDomain`의 `MaterialFormat`이 확장자로 형식을 정하고(`material show`도 같은 값을 쓴다) `renderer`가 보기를 고른다. `app/platform/file-view/`의 `FileView` 하나가 그 보기를 그린다: PDF는 PDFKit(`PDFPane`), 마크다운은 노트 미리보기, `.tex`·코드·텍스트는 편집기(자료와 노트) 또는 읽기 전용 소스, 이미지와 오디오는 네이티브 보기, 나머지는 같은 칸 안의 Quick Look, 그것도 못 보이면 "열 수 없음"과 다른 앱으로 열기. 자료는 `folio://material` 링크로 자료 탭에서 열고(과제, 문제집, 시험, 단원, 검색이 모두 이 길), 복습의 원본과 학기의 `_Admin` 파일도 `FileView`로 보인다. 화면이 파일을 따로 열지 않는다 | 있음 |
| 단축키 | 명령마다 한 번 등록하고 메뉴, 설정, 팔레트가 읽는 표와 키 녹음 검사 | #116 |
| 자동 완성 메뉴 `CompletionMenu` | 편집 보기의 모든 자동 완성(`/` 블록, 콜아웃 종류, 코드 언어, TeX 명령과 환경, AsciiMath 기호, 스니펫, 링크, 수식에서 `\`만 쳐서 여는 기호 전체 목록). 수식 기호의 분류와 목록은 `FolioMarkdown`의 `MathSymbols`가 정하고 f(x) 기호 팔레트와 함께 쓴다. 무엇을 완성할지는 `FolioMarkdown`의 `Completion`이 원문에서 읽고, 메뉴는 캐럿 옆에 하나만 뜬다. 늦게 오는 후보(링크)는 `more`로 더한다. 링크 후보는 `NoteLinkCompletion`이 FolioIndex 검색 색인과 파일에서 찾고, 보일 것과 순서는 `FolioDomain`의 `LinkCandidates`가 정한다. 한글 조합 중에는 메뉴, 짝 기호, 목록 이어 쓰기가 끼어들지 않는다. `/` 블록마다 바로 넣는 법(`##`, `mk ⇥`)을 오른쪽에 보이고, 입력 안내 시트(⌘/)는 같은 표(`/` 블록, 설정 스니펫, 콜아웃 종류, 짝 기호, 표 단축키)를 `FolioMarkdown`의 `InputGuide`로 읽어 상황별로 보인다 | 있음(Mac). iPad 메뉴는 #31 |
| 항목 메뉴 `ItemCommand` | 항목 종류마다 하나인 메뉴. 무슨 행이 어느 무리(`MenuGroup`: 열기, 시작, 상태, 편집, 정리, 공유, 삭제)로 서는지는 `FolioDomain`이 데이터와 시각, 연 자리(`MenuHost`)로 정하고(`CourseFile.commands(for:at:host:)`), 앱의 `ItemMenu`가 세 띠로 나눠 그린다. 오른쪽 클릭, ⋯, 검색 결과가 같은 메뉴를 쓰고, 화면의 단추는 같은 행을 `ItemButton`으로 그린다. "편집…"의 시트와 "삭제…"의 확인, 파일 추가는 창이 띄운다(`\.itemSheets`). 종류마다 명령은 `<종류>MenuCommand`이고(CLI의 명령 타입과 이름이 겹치지 않게), 노트·자료·단원·녹음·과목 화면은 페이지 끝의 `⋯`(`PageMenuButton`)로 같은 메뉴를 연다. 노트와 자료의 이름 바꾸기는 그 시트의 이름 칸이다 | 있음(#403: 회차, 시험, 계획 항목, 과제, 단원, 노트, 자료, 과목, 학기, 성적 항목, 점수, 카드, 문제집, 문제, 녹음, 사람, 코드, 졸업 요건 분류, 검색 결과) |
| 라이브 시계 `LiveClock` | 화면이 그리는 지금 시각. 분이 바뀔 때, 앱이 앞으로 오거나 Mac이 깨어날 때 갱신한다. 분 단위로 바뀌는 뷰는 `TimelineView` 대신 `workspace.liveNow`나 `LiveTime`으로 읽는다. 초를 세는 타이머만 `TimelineView`를 쓴다 | 있음 |
| 빠른 추가 인식기 `QuickAdd` | 빠른 추가 한 줄을 읽는 법. 낱말마다 인식기(`lexicon.swift`. 요일, 날짜, 시각, 반복(`매일`, `격주`, `3일마다`, `매주 월수`의 요일 묶음)은 `Recognizer`의 경우, 과목은 `readCourse`, 과제 번호는 `AssignmentKind.match`)가 읽고, 결합 규칙(`grammar.swift`의 `Rule`: [주][요일], [오전·오후][시각], [시각][분], [월][일], 홀로 선 [일])이 이웃을 묶고, 마감 뒤에 홀로 선 `까지`·`마감`은 `markEndings`가 마감에 붙이고, 여러 낱말로 쓴 반복(`한 달마다`, `2주에 한 번`)은 `joinRules`가 한 낱말로 묶고, 반복 낱말은 줄 어디에 있든 반복이며(`선대 매주 퀴즈 금`), 띄어 쓴 요일(`매주 월 수`, `격주 화, 목`, `월요일과 수요일마다`)은 바로 앞에 주 단위 반복이 있거나 `마다`로 끝날 때 `joinWeekdays`가 한 낱말로 묶고, 요일 묶음(`월수`)은 곁에 주 단위 반복이 있거나 `마다`가 붙을 때만 반복의 요일이고 아니면 제목이며(`bindWeekdays`), 해석(`resolve.swift`)이 줄의 구간 `spans`(마감, 과목, 과제 종류와 번호)와 저장할 값을 낸다. 제목은 어느 구간에도 들지 않은 글이다. 칸의 알약과 칸 아래 칩이 `spans`와 그 값만 읽는다. 새 종류(시험, 메모)는 인식기와 `Span.Field` 하나씩을 더한다. Apple의 날짜 인식기는 실제 시계로 읽으므로 표가 못 읽은 나머지에만 쓴다 | 있음 |

축을 새로 만들면 이 표에 적는다.

### 화면: 모델과 뷰

화면 하나는 `app/features/<기능>/`의 `<화면>-view.swift`와 `<화면>-model.swift`로 나눈다. 본보기는 `features/catalog/`다.

- **모델** `<화면>Model`: `@MainActor @Observable final class`이고 `init(workspace:, 대상 ID)`로 만든다. 검색어, 고른 항목, 지우려는 항목처럼 화면의 상태를 들고, 뷰가 바로 그릴 값(묶고, 거르고, 세고, 문구로 만든 값)과 동작(`add()`, `remove()`)을 내놓는다. 동작은 `workspace.run(액션)`을 부른다.
- **뷰**: 모델을 읽고 배치만 한다. `body`에서 묶기, 거르기, 세기를 하지 않고 `workspace`를 직접 부르지 않는다. 뷰는 `@State private var model`을 `init(workspace:)`에서 만들고, `@State`는 시트, 마우스 올림, 포커스 같은 화면 상태에만 쓴다.
- **Workspace**: 폴더 읽기, 파일 감시, 액션 실행, `can`/`refusal`/`confirmation`만 맡는다. 한 기능만 쓰는 함수는 그 기능의 모델에 둔다.
- `course.json` 밖의 파일을 읽는 목록(노트, 퀴즈 카드)은 `workspace.notesRevision`과 `quizRevision`이 바뀔 때 다시 읽는다. 두 값은 `Workspace`가 액션 결과의 `changes`(`touchesNotes`, `touchesQuizzes`)와 폴더 전체 다시 읽기로만 올린다. 화면이 직접 올리지 않으므로, 어느 화면이나 Claude 패널, CLI로 써도 열린 목록에 나타난다.
- 열린 편집기(노트, 텍스트 파일)도 `notesRevision`이 바뀌면 디스크를 마지막으로 읽거나 쓴 내용과 비교한다. 저장하지 않은 변경이 없으면 본문과 메타를 다시 읽고, 있으면 덮어쓰지 않고 충돌로 묻는다. 메타는 처음 연 `NoteFile`이 아니라 지금의 `course.json`에서 읽는다.
- 다른 화면이나 항목으로 옮길 때는 `@Environment(\.openLink)`에 `AppLink`를 넘긴다. 화면이 목적지를 직접 고르거나 링크 여는 법을 따로 구현하지 않는다. 그래야 모든 이동이 창의 기록 하나에 들어간다. 화면은 창이 지금 가리키는 곳을 `\.place`로 받아 따라가고, 자기 안에서 연 것(파일, 단원, 노트)은 다시 링크로 알린다(`CourseModel.place`).
- 파생 계산 중 데이터의 규칙(주차 묶기, 빠진 복습 노트 판단)은 `FolioDomain`에 두고 `swift test`로 검사한다. 화면에만 필요한 계산은 모델에 둔다.
- **화면 계약**: 화면은 앱 링크 하나를 그린다. 링크에서 화면을 고르는 곳은 `app/app/screen.swift`의 `Screen(entry)`와 `ScreenView` 하나다. 창의 본문 패널이 이것으로 그리고, 멀티뷰 칸(#62)과 iPhone(#134)도 이것으로 그린다. `Screen`은 링크 종류를 `default` 없이 가르므로 새 종류는 화면을 정해야 컴파일된다.
    - 화면은 `init(workspace:)`와 링크의 ID만 받는다. 링크가 가리키는 안쪽(과목의 구역, 연 파일·단원·노트, 사람)은 `\.place`로 읽는다. 다른 화면은 `\.openLink`로 열고, 여는 클로저를 인자로 받지 않는다.
    - 화면은 창 틀에 기대지 않는다. 툴바에 항목을 넣지 않고(도구는 `PageBar`, 보조 패널은 FAB), 창 크기가 아니라 자기 폭으로 배치를 고르며, 위치 표시에는 `.crumb`로 단계를 알리기만 한다. 그리는 것은 창(나중에는 칸)이다.
    - 화면은 받은 폭 안에 그린다. 전체 창(1440), 칸(720), 좁은 폭(390, iPhone) 어디서도 옆으로 넘치거나 행을 자르지 않고 접는다. 나란한 블록은 `Fold(wideFrom:)`로 넓을 때만 나란히 두고 좁으면 쌓는다. `FormRow`는 이름과 컨트롤이 한 줄에 들어가지 않으면 컨트롤을 이름 아래로 내리고, 다른 행은 `FoldingRow`로 같게 접는다.
    - 목록 열과 본문이 나란한 화면은 `ColumnSplit`으로 둔다. 본문이 `ColumnSplit.pageRoom`보다 좁아지거나 사용자가 손으로 접으면, 열은 본문 왼쪽 위의 열 버튼 뒤로 접히고, 버튼을 누르면 같은 열이 본문 위에 유리 판으로 뜬다(자리가 있으면 다시 붙는다). 칸이 하나든 여럿이든 같다. 항목이 늘어나는 목록(사람, 퀴즈 범위, 과목의 노트 목록)은 자리가 없고 본문에 보일 것이 없으면 목록이 본문이 된다(`.list(showingPage:)`). 고르기는 링크를 가진 것이면 `\.openLink`로 가서 창의 기록에 남는다(과목의 구역과 노트, 설정의 탭 `folio://settings/<탭>`, 사람). 주소가 그대로인 고르기(퀴즈 시작, 이미 고른 행)는 `ColumnPick`으로 떠 있는 열을 닫는다. 탭 없는 `folio://settings`(사이드바, ⌘,)는 `Workspace.entry(for:)`가 마지막으로 고른 탭으로 채우므로, 기록의 모든 칸이 탭을 가진다.
    - `ScreenFitTests`(`mise run test-app`)가 모든 화면을 세 폭으로 그려 넘치는지 본다. `ColumnSplit`의 본문은 평소 0까지 줄어들어 넘친 것을 자르는데, 검사는 `\.revealsOverflow`로 이를 풀어 넘친 본문이 창을 밀어내게 해서 본다. 바뀐 화면은 `FOLIO_RENDER_SIZES=1440x900,720,390 mise run render`로 그려 눈으로 본다.
- 모델 테스트는 `app-tests/<화면>-model-tests.swift`에 Swift Testing으로 쓰고, `fixtureWorkspace()`로 가짜 GIST 폴더를 연다.

### 문자열 키

화면과 CLI에 보이는 문구는 코드에 적지 않고 문자열 카탈로그에 키로 넣는다. 카탈로그는 문구를 내놓는 모듈마다 하나다(`app/resources`, `folio-domain`, `folio-actions`, `folio-cli`). 카탈로그에 직접 넣은 키(`extractionState: manual`)마다 Swift 심볼이 생기므로 키를 잘못 쓰면 컴파일이 실패한다.

```swift
// "sessions.add" = "회차 추가",  "sessions.count" = "회차 %lld개"
Button(.sessionsAdd) { ... }
Text(.sessionsCount(file.sessions.count))
PageHeader(title: String(localized: .sessionsAdd))   // String을 받는 API
```

- 키 이름은 `<기능>.<무엇>`이고 소문자, 점, 단어 안의 `-`만 쓴다. 여러 화면이 같은 뜻으로 쓰는 문구는 `common.*`에 둔다.
- 인자는 `Int`면 `%lld`, 그 밖은 코드에서 문자열로 바꿔 `%@`로 넘긴다. 연도는 자릿수 구분 기호가 붙지 않게 `String(year)`로 넘긴다. 인자가 여럿이면 `%1$@ %2$lld`처럼 쓴다. 문자 `%`는 인자가 있는 키에서만 `%%`로 쓴다.
- 파일에 쓰는 값이나 사용자 입력과 비교하는 값처럼 데이터이기도 한 문자열은 코드에 둔다.
- `@Action`의 `confirm:`과 `done:` 문구는 선언에 그대로 둔다. 매크로가 그 안의 `{필드}`를 컴파일할 때 검사하기 때문이다.

### 이름과 주석

- 파일과 폴더 이름은 소문자 케밥 케이스다(`today-view.swift`, `folio-core/sources/`). 타입 이름은 Swift 관례를 따른다.
- 주석은 코드가 말할 수 없는 것만 적는다. 무엇을 하는지는 코드가 말하므로, 왜 이 방식이어야 하는지, 특히 다르게 짜면 깨지는 이유를 적는다. 이름을 되풀이하는 설명형 문서 주석을 붙이지 않는다. 예외는 `@Action` 필드의 `///` 주석으로, CLI 도움말이 된다.

### 단일 출처(SSOT)

- 폴더와 파일 이름 규칙은 `FolioDomain`의 `standard-layout.swift`(`Term`, `SemesterFolder`, `CourseFolder`)에서만 정의한다. 다른 곳에서 `"Lectures"`, `".folio"` 같은 문자열을 다시 쓰지 않는다.
- 사용자가 바꿀 수 있는 값(하루 경계, 복습 간격, 알림 시점, 학점 규칙)은 코드 상수가 아니라 `settings.json`과 `transcript.json`에서 읽는다. 기본값은 Domain의 한 곳에서만 정의한다.
- 빌드와 테스트 명령은 `mise.toml`의 작업으로만 정의한다. 문서는 `mise run <작업>`을 가리킨다.
- Xcode 프로젝트는 `project.yml`에서 생성한다. `Folio.xcodeproj`는 커밋하지 않고 직접 고치지 않는다.
- 버전은 `FolioDomain`의 `FolioVersion.marketing`(`X.Y.Z`)에서만 정한다. 앱의 `MARKETING_VERSION`은 `mise run generate`가 여기서 읽어 `.build/version.xcconfig`에 쓰고, CLI(`folio --version`)와 MCP는 이 상수를 그대로 쓴다. 빌드 번호는 커밋 수(`git rev-list --count HEAD`)라 파일에 두지 않는다. `main`이 스쿼시 머지뿐이라 머지할 때마다 는다.
- 최소 지원 버전은 `project.yml`과 각 `packages/*/Package.swift`에 있다. 도구 제약으로 하나로 합칠 수 없으니 함께 고친다.

## 데이터 원칙

이 원칙들은 사용자의 실제 학업 자료를 다루기 때문에 반드시 지킵니다.

1. **파일이 원본이다.** 모든 상태는 GIST 폴더 안의 파일(`course.json`, `transcript.json`, 마크다운 노트, `.drawing`, 기기별 `.jsonl` 로그)에 저장한다. 앱 내부의 SQLite는 검색과 집계를 위한 캐시이며, 지워도 파일에서 다시 만들 수 있어야 한다.
2. **폴더 구조는 Folio가 정한다.** GIST 폴더는 아래 "폴더 구조와 이름 규칙"을 따른다. 과목 폴더의 하위 폴더는 `Syllabus`, `Lectures`, `Exercises`, `Textbooks`, `Inherited`, `Assignments/<과제>`, `Exams/<시험>`, `Study`, `Notes`, `Ink`, `Recordings`, `Archive`, `.folio`만 쓴다. 과제와 시험은 하나당 폴더 하나이고, 시험 폴더는 데이터 모델의 Exam과 1:1로 대응한다. 과제 폴더 안의 파일 이름은 바꾸지 않는다. 예전 학기의 다양한 폴더 이름을 허용하는 분기 코드를 만들지 않는다. 기존 폴더는 일회성 정리 도구로 표준 구조에 맞춘다.
3. **삭제와 이동은 사용자 승인 후에만 한다.** 파일 이동, 이름 변경, 삭제는 사용자가 확인 화면에서 승인한 경우에만 수행한다. 수행한 이동과 이름 변경은 `.folio/moves.jsonl`에 기록해 되돌릴 수 있게 한다. Claude가 제안한 분류와 위치도 제안으로만 저장한다.
4. **쓰기는 원자적으로 한다.** 파일 쓰기는 `NSFileCoordinator`를 거치고, 임시 파일에 쓴 뒤 교체하는 방식으로 한다. iCloud 충돌 사본은 `NSFileVersion`으로 감지한다.
5. **로그는 추가만 한다.** `.folio/logs/<기기 ID>.jsonl`은 각 기기가 자기 파일에만 줄을 추가한다. 기존 줄을 고치거나 지우지 않는다.
6. **스키마에 버전을 둔다.** 모든 JSON 파일 최상위에 `schemaVersion`을 두고, 버전이 바뀌면 마이그레이션 함수를 추가한다. 모르는 필드는 읽을 때 버리지 않고 그대로 보존한다.
7. **식별은 ID로 한다.** 파일, 노트, 엔티티는 UUID로 식별한다. 경로와 제목은 표시용이며 바뀔 수 있다.

### 폴더 구조와 이름 규칙

코드의 단일 출처는 `standard-layout.swift`다. 이 절은 그 규칙을 사람이 읽는 형태로 적는다. 과목 폴더는 출처로만 나뉜다. 받은 것(`Syllabus`, `Lectures`, `Exercises`, `Textbooks`, `Inherited`), 평가 기록(`Assignments/<과제>`, `Exams/<시험>`), 내가 만든 것(`Study`, `Notes`, `Ink`, `Recordings`, `Archive`)이다. 어느 시험이나 단원을 위한 파일인지는 폴더가 아니라 `course.json`의 연결(ID)로 표시한다.

```text
Me/GIST/
  .folio/
    transcript.json            # 학기 목록(인정학기와 그 출처 포함), 학점 규칙, 목표. 과목은 모두 과목 폴더에 있다
    catalog.json               # 강의 코드, 세부 분류, 평어, 교수 정보
    settings.json              # 하루 경계, 복습 간격, 사이드바 과목 순서 등 전역 설정
  2026-3/
    _Admin/                    # 학기 전체의 시험 시간표, 강의실 배정, 수강신청 서류, 성적증명서
    EC4207 그래프 이론/
      Syllabus/                # 강의계획서, OT 자료, 수업 운영 안내
      Lectures/                # 강의 슬라이드. 05_Matchings.pdf
      Exercises/               # 교수가 준 채점 없는 연습 문제만
      Textbooks/               # 교재, 참고서, 해설집
      Inherited/               # 선배와 이전 학기에서 받은 자료. 원래 이름 그대로
        관훈 선배 리포트/      # 출처별 하위 폴더는 있어도 되고 없어도 된다
      Assignments/
        HW03/                  # 과제 하나에 폴더 하나. 안의 파일은 원래 이름 유지
        Lab03/                 # 실험 보고서. 매뉴얼은 그 실험 회차의 강의 자료로 Lectures에 둔다
      Exams/
        Midterm/               # 이 시험의 기록만. 시험 안내, 좌석표, 받은 시험지와 해설, 채점된 답안
      Study/                   # 직접 만든 파일. 문제집, 모의고사, 요약 PDF와 .tex 원본, 노트를 내보낸 PDF
      Notes/                   # Folio 노트(마크다운 .md, LaTeX .tex)
        assets/                # 노트에 넣은 그림과 파일
      Ink/                     # PencilKit 필기 (.drawing)
      Recordings/              # 강의 녹음(.m4a)과 받아쓰기(.transcript.json). 11-03(화).m4a
      Archive/                 # 이전 필기 (노타빌리티 PDF, 예전 노트 폴더)
      .folio/
        course.json            # 과목 정보, 단원, 강의 회차, 평가 기준, 과제, 파일 연결
        quizzes/<단원 ID>.json
        chats/<대화 ID>.json
        widgets/<위젯 ID>.html
        moves.jsonl            # 앱이 수행한 이동과 이름 변경 기록
        logs/<기기 ID>.jsonl  # 복습, 퀴즈, 공부 시간 기록 (기기별 추가 전용)
  _Credited/
    영재고 AP/                 # 인정학기의 출처. 그 학기의 과목 폴더가 여기 들어간다
      GS1101 일반물리학 및 연습 I/
```

- GIST 폴더 최상위에는 학기 폴더, `_Credited`, `.folio`만 둔다. 학기 폴더는 `<연도>-<번호>`이고 번호 1은 봄, 2는 여름, 3은 가을, 4는 겨울학기다. 학기 폴더 안에는 `_Admin`과 과목 폴더만 둔다. 인정학기는 학기 폴더가 없고, 과목 폴더를 `_Credited/<출처>`에 둔다. 출처는 `transcript.json`의 학기에 적고(`semester source`), 출처가 없는 인정학기에는 과목을 만들 수 없다.
- 과목 폴더는 `<대표 과목코드> <과목명>`이다. 원본은 `course.json`이고, 과목 편집에서 바꾸면 앱이 폴더 이름을 맞춘다(저장 전 새 이름을 보여 주는 것이 승인이며 `moves.jsonl`에 남긴다). 과목 폴더 최상위에는 파일을 두지 않는다. 모든 과목은 과목 폴더와 `course.json`을 가진다. 과목을 만들 때는 `.folio`만 만들고, 하위 폴더는 처음 필요할 때 만든다.
- `Lectures`의 파일은 `<주차 두 자리>_<제목>`이고, 한 주에 여러 개면 `05-1_`, `05-2_`로 나눈다.
- `Assignments/<과제>`는 종류 접두어와 두 자리 번호다(`HW`, `Lab`, `Report`, `Project`, `SP`, `Reading`, 평가 항목에 맞춰 추가). 안의 파일 이름은 바꾸지 않는다. 제출본은 교수가 정한 형식을 따라야 하기 때문이다. 문제, 제출본, 해설 같은 역할은 `course.json`에 기록한다. 코드 과제는 프로젝트를 이 폴더에 그대로 두고, `.git`이 있는 폴더는 이름도 바꾸지 않는다.
- 시험별 폴더 `Exams/<시험>`은 Exam과 1:1이고, `Assignments/<과제>`처럼 그 시험의 기록만 둔다. 폴더는 처음 파일이 들어갈 때 만들고, 시험을 추가해도 빈 폴더를 만들지 않는다. 폴더 이름은 새 시험의 제목으로 정하고(`Exams/중간고사`) `course.json`에 남겨, 제목을 바꿔도 그대로 둔다. 예전 시험의 `Midterm`, `Final`, `Quiz1`도 그대로 쓴다.
- `Inherited`에는 선배와 이전 학기에서 받은 자료를 종류와 상관없이 원래 이름으로 둔다. 출처별 하위 폴더(`Inherited/관훈 선배 리포트/`)는 써도 되고, 낱개 파일은 `Inherited`에 바로 둔다. 족보 시험지(해설 포함)인지는 이름이 아니라 `course.json`의 자료 종류(`pastExam`)로 표시하고, 시험에 쓸 자료는 그 시험에 연결한다(`material link-exam`). `Exams/Past`는 없앴다.
- `Exercises`에는 교수가 준 채점 없는 연습 문제만 둔다.
- `Study`에는 직접 만든 파일을 둔다. 문제집, 모의고사, 요약 PDF와 `.tex` 원본, 노트를 빌드한 PDF(`Study/<제목>.pdf`)가 여기 온다. 어느 시험·단원용인지는 `material link-exam`, `material link-unit`으로 연결하고(앱에서는 자료 연결 편집기, 단원 페이지, 시험 카드), 시험 화면은 시험 폴더의 파일과 연결된 자료를 함께 센다. 어떤 자료가 회차, 단원, 시험에 딸리는지는 `CourseFile.routes(of:to:)` 하나가 정한다. 회차는 그 단원과 상위 단원의 자료를, 단원은 그 회차의 자료를 함께 본다. 단원으로 나눈 렉처는 자료 연결 없이도 그 쪽 구간(`lecturePages`)으로 단원과 그 회차에 딸리고, 화면은 이것을 직접 연결과 구분한다(`MaterialRoute.pages`. 떼려면 나누기를 고친다). Folio 마크다운 노트는 `Notes`에 둔다.
- 회차 노트는 수업 날짜와 그 수업에 연결된 단원(가장 깊은 단원)으로 이름을 짓는다(`Notes/11-05(목) Principles of reliable data transfer.md`, 복습 노트는 뒤에 ` 정리`). 단원이 없으면 날짜만 쓴다. 규칙은 `CourseFile.noteTitle(for:kind:calendar:)` 하나다. 이미 있는 노트는 단원이 바뀌어도, 예전 수업 주제로 지은 이름이어도 그대로 둔다. 그 전에 `10주차-2`로 만든 노트는 저절로 바뀌지 않고, `note retitle`로 한 번에 바꾼다.
- 회차는 `N주차-M`으로 부르지 않는다. 화면에 보이는 이름은 `CourseFile.title(of:calendar:)`(`11/3(화): 단원`, 단원이 없으면 날짜만) 하나이고, CLI가 회차를 가리키고 출력하는 이름은 `CourseFile.reference(of:calendar:)`(`EC4207/11-03`, 하루에 수업이 둘이면 `11-03 14:00`)다. 날짜(`11/3`, `2026-11-03`)와 단원 이름으로도 찾는다(`references`). 회차에는 주제가 없다. 무엇을 다뤘는지는 단원 연결이 말하고, 예전 `course.json`의 `topic`은 모르는 필드로 남겨 둔다. 회차의 종류(`Session.kind`)는 강의(기본), 휴강, 보강 셋이다. 파일에는 휴강인 회차에만 `cancelled`, 보강인 회차에만 `makeup`을 두므로 예전 파일의 회차는 모두 강의다. 휴강은 출석과 복습에 세지 않고, 보강은 강의처럼 출석, 복습, 수업 정리에 센다. 휴강으로 바꾸면 그 회차의 출결을 지운다. 시간표 밖의 끝 시각(`end`)은 종류와 따로다. 앱에서 시간표 밖 시각에 회차를 손으로 더하면 종류를 보강으로 미리 고르고, 편집은 종류를 저절로 바꾸지 않는다. 날짜는 공부일이 아니라 달력 날짜라 노트 파일 이름의 날짜와 같다. 학기의 주차(`Lectures`의 `05_`, "지금 9주차", 시험 주차, 회차 목록의 주차 묶음)는 회차 이름이 아니라 그대로 쓴다.
- 녹음 파일은 수업 날짜로 이름을 짓는다(`Recordings/11-03(화).m4a`, 같은 날 둘째는 ` 2`). 그 전의 `2주차-1.m4a`는 저절로 바뀌지 않고, `recording retitle`로 한 번에 바꾼다. 예전 이름(`10주차-2`)을 알아보는 규칙은 이 두 이름 바꾸기 도구에만 둔다.
- 노트 링크는 노트 ID로 건다: `[[note:<ID>|제목]]`, `[[note:<ID>#제목|표시]]`, `[[note:<ID>#^블록|표시]]`. 앱 링크 `folio://note/<ID>`로 열고 이름이 바뀌어도 깨지지 않는다. 손으로 쓴 `[[제목]]`은 과목 안에서 제목으로 찾고 ID 꼴로 바꾸지 않는다. 링크를 열 때와 미리보기가 그 노트를 그리거나 깨진 링크로 그릴 때 모두 `[NoteFile].linked` 하나로 찾는다. 블록 ID는 원문의 `^id`라 같은 노트 안에서 옮긴 블록은 따라가고, 다른 노트로 옮기면 찾지 못한다. 표 안에서도 `[[…]]`의 `|`는 칸을 나누지 않고(Obsidian과 같다), Obsidian이 표에 쓰는 `[[대상\|이름]]`도 같은 링크로 읽는다.
- 링크 자동 완성은 고른 항목을 ID 꼴로 넣고 이름을 `|` 뒤에 붙인다: 노트 `[[note:<ID>|제목]]`, 자료 `[[material:<ID>#page=N|파일 이름]]`, 그 밖은 앱 링크 종류 이름 그대로(`[[exam:<ID>|중간고사]]`). 이미 쓴 `|이름`은 그대로 둔다. ID가 없는 블록을 고르면 대상 노트 끝 줄에 `^id`를 붙이는데, 다른 노트면 `note write`(읽은 글과 다르면 거절)로, 쓰고 있는 노트면 편집 보기에서 쓴다.
- 복사한 주소를 괄호에 넣은 `[[folio://<종류>/<ID>…|이름]]`도 `[[<종류>:<ID>…]]`와 같은 링크로 읽고, 원문은 바꾸지 않는다. 이름이 없는 앱 링크는 미리보기에서 대상의 이름을 보인다(자료는 파일 이름과 쪽, `Workspace.label(of:)`). `folio://` 주소를 노트에 붙이면 자동 완성과 같은 꼴로 들어가고(`[[material:<ID>#page=N|파일 이름]]`), `<종류>:<ID>` 꼴이 없는 장소와 과목 페이지는 `[[folio://…|이름]]`으로 들어간다. 쓰고 있는 링크 안(`[[…`, `](…`), 코드, 수식에서는 붙인 그대로 둔다. 맨 주소는 미리보기에서도 링크가 되고, 끝의 문장부호(`.,;:!?`)는 주소에 넣지 않는다. 제목 앵커(`#제목`)만 문장부호로 끝날 수 있어 남긴다(`AppLink.trimmed`).
- 앱 밖의 파일은 복사해서 들여오고, 같은 이름이 있으면 ` 2`를 붙여 덮어쓰지 않는다.

## 실제 데이터 위치

- GIST 폴더: `~/Library/Mobile Documents/com~apple~CloudDocs/Me/GIST`
- 옵시디언 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain`. Folio는 이 볼트를 읽거나 쓰지 않고, `obsidian://` 링크로만 참조한다.
- 개발과 테스트 중에는 실제 GIST 폴더에 쓰지 않는다. 테스트는 `FolioFixtures`의 가짜 폴더를 임시 디렉터리에 써서 쓴다. 앱이나 CLI를 가짜 폴더로 돌릴 때는 `mise run fixture -- <폴더>`로 만든다.
- 실제 폴더를 대상으로 처음 실행하기 전에 사용자에게 알리고, 백업이 있는지 확인한다.

## 테스트 기준

- `FolioFixtures`에는 가짜 GIST 폴더를 두 벌 둔다. 파일 목록과 내용은 `packages/folio-core/sources/folio-fixtures`에 코드로 있다.
    - `Fixture.standard`: 표준 구조를 따르는 폴더. 앱의 일반 기능 테스트에 쓴다.
    - `Fixture.legacy`: 현재 실제 폴더처럼 정리되지 않은 폴더. 정리 도구 테스트에만 쓴다. 한국어 하위 폴더(`강의자료`, `노트`, `숙제`, `족보`), 과목마다 다른 영어 하위 폴더(`Lectures`, `Homeworks`, `Exam Review`, `Slow Problems`, `Books`), `족보 (소순범)` 같은 이름, 학기 폴더의 `학사` 폴더와 흩어진 학사 파일, 과목 폴더 최상위의 강의계획서, 교재, 시험 안내, 자리 배치표, `Manuals` 폴더, `.git`이 있는 코드 과제 폴더, 같은 이름의 `.tex`와 PDF, 학업 외 폴더(`과대표`, `GIST OTP`)를 포함한다. 예전 정리 규칙이 남긴 모양도 넣는다. `Exam Review`를 `Exercises`로 옮긴 기록(`.folio/moves.jsonl`)과 그 파일들, 직접 만든 파일과 빈 퀴즈 폴더가 있는 시험 폴더, 선배 레포트 폴더가 든 `Exams/Past`, `Notes/Exports`다.
- 정리 도구는 `legacy`를 정리한 결과가 표준 구조를 만족하는지, `moves.jsonl`로 되돌리면 원래 상태와 같아지는지 테스트한다.
- 성적 계산 테스트에는 지어낸 등급과 손으로 계산한 기대값을 쓴다. 저장소가 공개라서 실제 성적과 GPA는 테스트, 픽스처, 문서에 넣지 않는다.
- 계산 로직에는 손으로 계산한 예시와 함께, 무작위 입력에서도 지켜져야 하는 성질을 `PropertyBased`(`propertyCheck`)로 검사한다(예: `GradePropertyTests`). 예시가 정답을 고정하고, 성질 테스트는 예시가 놓친 경계를 찾는다. 실패하면 출력된 시드를 `.fixedSeed(...)`로 붙여 다시 돌린다.
- 그래프 이론의 "Quiz 최저 점수 1회 제외"와 선형대수학의 "결석 6회면 최대 B0, 9회 이상이면 F"를 성적 규칙 테스트 사례로 넣는다.
- 하루 경계 테스트는 새벽 4시 경계를 기준으로 경계 직전과 직후를 모두 검사한다.
- 노트 보기(편집 보기와 미리보기)는 `mise run test-app`의 회귀 검사가 지킨다(#265).
    - `NoteScreenTests`: `all-markdown.md`(모든 문법)와 화면보다 긴 노트(`fixtures/long-note.md`)를 라이트·다크, 폭 900과 480으로 그려 기준 이미지와 비교한다.
    - `NoteLayoutTests`: 블록이 열 안에 있는지, 연 직후와 스크롤한 뒤 화면이 끝까지 그려지는지, 노트 끝 아래로 스크롤되는지를 그린 픽셀로 본다.
    - `NoteClickGridTests`: 연 직후와 스크롤한 뒤 격자의 모든 점이 노트(또는 그 자리의 위젯, 가로 스크롤 블록)에 닿는지, 편집 보기에서는 클릭한 자리에 캐럿이 놓이는지 본다.
    - `NoteHangulTests`: 조합 중인 글자가 SwiftUI 갱신과 저장을 견디고, 조합이 끝난 글자가 노트 파일에 들어가는지 본다. iPad 편집 보기는 `app-tests/ipad`의 `NoteHangulPadTests`가 iPad 시뮬레이터에서 같은 입력을 본다(`mise run test-ipad`).
    - 검사는 보기를 `NoteBench`(`app-tests/note-bench.swift`)로만 다룬다. 그린 픽셀, 히트한 뷰, 캐럿 위치, 스크롤 범위만 보고 TextKit이나 웹 페이지의 내부는 보지 않는다. 미리보기는 `WKWebView`라서 스냅숏을 웹 프로세스에서 받는다. 편집 보기의 구현을 바꿀 때(#267처럼)는 이 파일과 기준 이미지만 바꾸고, 배치, 클릭, 한글 검사는 그대로 통과해야 한다.
    - 미리보기의 동작(블록 단위 갱신, 할 일 체크, 콜아웃 접기 유지, 편집 보기 따라가기, 위젯 iframe의 격리와 높이, 임베드와 블록 참조 카드, 깨진 링크, 그림 크게 보기)은 `NotePreviewTests`, `NoteWidgetTests`, `NoteEmbedPreviewTests`가 페이지에 스크립트를 돌려 본다. 편집 보기의 블록 참조 카드는 `NoteReferenceCardTests`가 본다.
- 노트 보기 기준 이미지(`app-tests/references/notes`)는 CI 러너가 그린 것만 커밋한다. 글꼴 렌더가 macOS마다 달라서 비교는 이미지를 그린 macOS(`machine.txt`)에서만 하고, 다른 Mac에서는 건너뛴다. CI는 `FOLIO_NOTE_SCREENS_STRICT`를 켜서 러너의 macOS가 바뀌면 건너뛰지 않고 실패한다. 기준 이미지를 바꾸는 PR은 본문에 이전과 이후 이미지를 붙인다.
- 테스트, 미리보기, 화면 밖 렌더는 이 Mac의 `Application Support/Folio`(녹음 복구, Whisper 모델)를 쓰지 않는다. 그 폴더는 앱의 `LocalFolders`로만 얻고 패키지는 쓰지 않으며(`mise run check-local-folders`가 `app`, `app-tests`, `packages`를 검사한다), 테스트와 미리보기에서 얻으려 하면 실행이 멈춘다. 화면 모델 테스트는 `fixtureWorkspace()`, 미리보기와 렌더는 `Workspace.scenario`가 임시 폴더를 준다. `FOLIO_GIST`로 가짜 폴더를 연 앱 실행(창 스냅숏 포함)은 녹음 폴더를 그 GIST 폴더마다 따로 임시 폴더에 둔다.

## 빌드와 실행

도구 버전과 환경 변수는 `mise.toml`이 정한다. Xcode 툴체인은 전역 `xcode-select`를 바꾸지 않고 `DEVELOPER_DIR`로 이 저장소에서만 쓴다. 명령은 항상 `mise run`으로 실행한다. 정의는 `mise.toml`에 있다.

- Xcode 프로젝트 생성: `mise run generate`. 그 뒤 `open Folio.xcodeproj`. 버전과 빌드 번호도 이때 정해지므로, 커밋한 뒤 Xcode에서 빌드하면 빌드 번호는 마지막 `generate` 때의 것이다
- 패키지 테스트: `mise run test` (모든 패키지, 디자인 토큰 검사, Application Support 경로 검사)
- 화면 모델 테스트와 노트 보기 회귀 검사: `mise run test-app`. macOS에서 앱을 호스트로 `app-tests/`를 돌린다. 테스트 중에는 앱이 기억해 둔 GIST 폴더를 열지 않고, 창을 띄우거나 포커스를 가져가지 않는다. `FOLIO_TEST_PART=notes`는 노트 보기 검사(`mise.toml`의 `notes` 목록)만, `rest`는 나머지만 돌린다. CI는 두 절반을 `build (test-app-notes)`와 `build (test-app-rest)`에서 나란히 돌리고, 룰셋이 요구하는 `build (test-app)`은 Linux 러너에서 두 절반을 기다려 둘 다 통과해야 통과한다. 새 노트 보기 검사는 목록에 넣기 전까지 `rest`에서 돈다
- 노트 보기 기준 이미지 다시 만들기: `test-app`은 없거나 달라진 이미지를 새 이미지와 차이 이미지(`-diff.png`)로 `FOLIO_NOTE_SCREENS`(기본 `.build/note-screens`)에 남기고, CI는 실패할 때 이것을 `note-screens` 아티팩트로 올린다. 차이 이미지로 의도한 변화인지 확인한 뒤 `mise run note-screens -- <CI 실행 ID>`로 기준 이미지에 들인다. 로컬에서 그린 이미지는 기준으로 쓰지 않는다. 테스트가 PR에 붙일 그림으로 펼친 판(`NoteRender.sheet`, 예: 수식 말풍선 모음)은 `FOLIO_NOTE_SCREENS/sheets`에 남고, CI는 테스트가 통과해도 `note-sheets` 아티팩트로 올린다
- iPad 테스트: `mise run test-ipad`. 첫 번째 iPad 시뮬레이터에서 `FolioPad` 스킴으로 앱을 호스트 삼아 `app-tests/ipad/`를 돌린다. 이 파일들은 `#if os(iOS)`로 감싸서 Mac의 `FolioTests`에서는 비어 있다
- 화면 밖 렌더: `mise run render`. `FolioFixtures`의 상황마다 모든 페이지(오늘, 학기, 과목의 각 탭과 다시 듣기, 성적, 졸업 요건, 사람, 코드, 설정의 각 탭)와 시트(입력 폼, 검색)를 라이트·다크 PNG로 `FOLIO_RENDER_DIR`(기본 `.build/renders`)의 `<상황>/`에 쓴다. 폭과 높이는 `FOLIO_RENDER_SIZES=1180,720,1440x900`(높이를 빼면 페이지 끝까지), 고르기는 `FOLIO_RENDER_SCREENS=today,course-`(이름 앞부분)와 `FOLIO_RENDER_SCENARIOS=busyDay`. 창이 뜨지 않고 실제 GIST 폴더와 시계를 쓰지 않는다. 리퀴드 글라스, 노트 보기와 `WKWebView`, 뷰 안에서 여는 시트, 창 틀은 그리지 못하니 `FOLIO_SNAPSHOT_DIR` 창 스냅숏(`docs/DESIGN.md` 마지막 절)으로 본다
- TeX 엔진: `mise run tectonic`. `packages/folio-core`를 빌드하는 모든 작업(`generate`, `test`, `cli`, `gen-cli`, `fixture`, `install-cli`)이 먼저 돌린다. `tectonic/pin.json`이 가리키는 `FolioTectonic.xcframework`를 받아 sha256을 확인하고 `packages/folio-core/vendor`에 푼다. `tectonic/bridge`, `tectonic/patches`, `scripts/tectonic-build.sh`, 도구 판을 정하는 `tectonic.yml`을 바꾸면 `tectonic.yml`이 그 내용의 해시로 이름 지은 프리릴리스(`tectonic-<판>-<해시>`)를 만들고 새 `pin.json`을 작업 요약에 적으므로, 그것을 커밋한다. 핀이 지금 입력과 다르면 `mise run tectonic`이 경고한다. 빌드는 Mac의 `tectonic -X compile -Z continue-on-errors --synctex`와 같고, 받은 패키지만으로 먼저 빌드해 보고 없는 파일이 있을 때만 온라인으로 다시 빌드한다. 캐시는 `Caches/Tectonic`이라 Mac에서는 Homebrew Tectonic과 같은 폴더를 쓴다
- 가짜 GIST 폴더: `mise run fixture -- <폴더> [standard|legacy|<상황>]`. 상황(`busyDay` 등)은 `Scenario`로 회차와 마감이 채워진 폴더다. 다른 `.pdf`는 열리지 않는 자리표시자지만, `busyDay`와 `manyExams`의 그래프 이론 렉처(`05_Matchings.pdf`)는 단원으로 나눈 24쪽 PDF(`SampleLecture`)다. 이미 있는 폴더에는 쓰지 않는다
- 웹 번들: `mise run build-web`. `web/src/`를 고친 뒤 실행한다. 노트 미리보기와 Claude 패널의 색은 `theme.swift`의 값을, 크기와 간격은 `app/design/note-look.swift`의 값을 `NoteStyle`이 CSS 변수로 넘기므로 CSS에 색과 크기를 적지 않는다
- 노트 보기 렌더: `TEST_RUNNER_FOLIO_NOTE_RENDER=<폴더>`를 주고 `NoteSourceTests`를 돌리면 `app-tests/fixtures/all-markdown.md`(모든 문법을 쓴 노트)를 편집 보기로 그린 PNG가 그 폴더에 남는다. 미리보기 그림은 `NoteScreenTests`가 `FOLIO_NOTE_SCREENS`에 남긴다
- macOS 빌드: `mise run build-mac`. 모든 `xcodebuild` 작업은 `~/Library`의 DerivedData 대신 체크아웃 안의 `.build/DerivedData`(`FOLIO_DERIVED_DATA`)에 빌드한다. 워크트리마다 몇 GB씩 남지 않고 워크트리를 지우면 함께 지워진다. 디버그 앱은 `.build/DerivedData/Build/Products/Debug/Folio.app`이다. `FolioMacros`는 로컬 패키지라 Xcode가 매크로 신뢰를 묻지 않는다. mise 작업의 `-skipMacroValidation`은 명령줄 빌드가 멈추지 않게 하는 안전장치다
- macOS 앱 설치: `mise run install-release [-- <ref>]`. `origin/main`(또는 준 커밋, 예를 들어 PR 브랜치를 합쳐 본 임시 커밋)을 임시 워크트리에 꺼내 Release로 빌드하고, `/Applications/Folio.app`과 `~/.local/bin/folio`를 바꾼 뒤 워크트리를 지운다. 커밋하지 않은 작업과 다른 세션의 워크트리는 들어가지 않는다. 실행 중인 `/Applications/Folio.app`만 끄고, 같은 번들 ID의 Debug 앱은 건드리지 않는다. 지금 체크아웃을 그대로 설치하는 `mise run install-mac`은 그 안에서 쓰는 단계다
- 버전 올리기: `mise run version-bump -- major|minor|patch`. 1.0 전에는 새 기능이 든 릴리스는 minor, 고침만 든 릴리스는 patch를 올리고, major는 1.0(사용자 데이터 형식과 기능 범위를 굳힐 때)에만 올린다. 올린 커밋은 PR로 머지한다
- 릴리스 노트: 원본은 PR 본문의 `## 패치 노트` 절이다(아래 "PR 전 점검", #415). `mise run release-notes [-- <since>]`가 지난 태그 뒤 머지된 PR의 본문을 `gh`로 읽어 그 절의 항목 줄을 모은 릴리스 본문을 보여 준다. 커밋 메시지가 아니라 PR 본문을 읽으므로 머지 뒤에 고친 본문도 들어간다. 저장소에는 버전별 노트 파일을 두지 않는다. 릴리스 본문은 `## 패치 노트` 제목, 형식 표시(`<!-- folio-patch-notes 1 -->`), 종류별 소제목(`### feat`, `### fix`, `### change` 순)으로 묶은 항목 줄, 머지된 PR 목록, 설치 안내 순이다. 앱은 이 본문을 GitHub Releases API에서 받아 `FolioDomain`의 `PatchNotes`로 읽으니, 줄의 형식을 바꾸면 스크립트의 `format`과 `PatchNotes.format`을 함께 올린다. 첫 릴리스(앞선 태그 없음)는 그때까지 머지된 모든 PR을 모은다
- 릴리스: `mise run release-tag`가 `origin/main`에 `v<버전>` 태그를 달고 푸시한다. 태그가 푸시되면 `release.yml`이 Release 앱을 빌드해 `Folio-<버전>.zip`을 붙인 GitHub Release 초안을 만들고, 본문에는 패치 노트 항목과 머지된 PR(제목과 한국어 요약)을 적는다. 초안을 게시해야 앱이 그 버전의 패치 노트를 본다. 초안은 사람이 확인하고 게시한다. 태그와 `FolioVersion`이 다르면 실패한다. 수동 실행(`workflow_dispatch`, `since` 입력)은 릴리스 없이 같은 결과를 아티팩트로만 올린다. Developer ID 서명, 공증, 자동 업데이트(#414)는 아직 없다
- iPad 빌드: `mise run build-ipad`
- 생성 CLI 명령: `mise run gen-cli`. `@Action` 선언을 고친 뒤 실행한다. `mise run test`가 커밋된 파일이 낡지 않았는지 본다
- 명령줄 도구: `mise run cli -- <명령>`. `~/.local/bin`에 설치는 `mise run install-cli`. GIST 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다. 모든 쓰기 명령은 `--dry-run`으로 먼저 본다. 명령 목록은 `folio help`, 자연어로 찾기는 `folio help <하고 싶은 일>`
- MCP: `folio mcp`가 모든 쓰기 액션과 읽기 명령을 표준 입출력 MCP 도구로 연다. 앱의 Claude 패널은 `--propose`로 붙여 쓰기를 제안으로만 받는다. 도구 정의는 질문마다 함께 가므로 `--propose`에는 과목 대화에 쓰는 도구만 연다(`MCPServer.panelGroups`가 목록). 나머지 액션과 읽기 명령에는 범용 도구 두 개로 닿는다. `action_search`는 `folio help <하고 싶은 일>`의 검색으로 명령과 입력 형식(JSON Schema)을 찾아 주고, `action_run`은 명령 이름과 JSON 입력으로 그 명령의 도구를 그대로 부른다. 그래서 `--propose`의 쓰기는 제안이 되고, 성적 잠금은 명령 자신이 지킨다. `--propose` 서버는 한 답(질문마다 새 프로세스)의 제안을 GIST 폴더의 임시 사본(`StagedFolder`, APFS 복제)에 차례로 실제로 실행해 쌓는다(`ProposalStage`). 다음 쓰기의 미리 실행과 읽기(`search` 빼고)가 그 사본에서 돌아서, `unit add` 뒤의 `unit pages add`, `note add` 뒤의 `note edit`이 제안 단계에서 통과하고, 읽은 결과의 그 항목에는 `proposed`가 붙는다. 사본 안에서는 `CoordinatedFile`이 사본 밖으로 가는 쓰기를 막는다. 폴더만으로는 실패하는 제안은 기대는 앞 제안의 번호(`ActionProposal.after`)를 지니고, 패널은 그 제안이 적용되기 전에는 따로 적용하지 않으며(`ChatMessage.waiting`), 모두 적용은 같은 사본 검사(`Workspace.stagedRefusal`)로 차례대로 확인한다. 터미널의 `folio mcp`에도 같은 두 도구가 있다. 도구 결과의 JSON은 한 줄로 줄이고 null, 빈 배열, 빈 객체를 뺀다. 셸 없는 클라이언트에는 `claude mcp add folio -- folio mcp`처럼 붙인다
- 자료 읽기(#85): `material read <자료> [--pages 9-12] [--titles] [--images]`가 PDF의 쪽 글과 쪽 그림, `recording transcript <회차> [--from 10:00 --to 20:00]`가 받아쓰기, `note images <노트> [--file <그림>]`이 노트의 그림을 읽는다. 패널과 터미널의 `folio mcp`가 함께 쓰고, 그림은 MCP image content로 준다(터미널에서는 `--out <폴더>`, GIST 폴더 밖). 한 번에 주는 양은 `FolioDomain`의 `ReadingLimit`이 정하고, 넘으면 잘라서 다음 범위를 알려 준다. 쪽 글의 규칙(그림 자리 문자 U+FFFC 빼기, 첫 네 줄 중 가장 큰 글자를 제목으로)은 `PageText` 하나이고, PDFKit 읽기와 그림 줄이기는 `FolioStorage`의 `PDFPages`다. 읽기라 액션이 아니고 아무것도 쓰지 않는다
- 에이전트 스킬: 원본은 `packages/folio-core/sources/folio-cli/commands/skill.swift`. 고친 뒤 `mise run cli -- skill > .claude/skills/folio/SKILL.md`로 사본을 맞춘다(테스트가 확인한다). 다른 에이전트에는 `folio skill --install <스킬 폴더>`
- 액션 커버리지: `mise run cli -- actions --check`. 모든 액션에 명령과 동등성 테스트가 있고, 손으로 짠 명령에 이유가 있고, 앱이 액션 밖에서 쓰지 않는지 본다. `mise run test`가 함께 돌린다
- 구조 검사: `check`
- 폴더 정리: `cleanup plan --out plan.json [--skip <경로>]`, 검토 뒤 `cleanup apply --plan plan.json --backup <iCloud 밖 폴더> [--include-flagged]`, 되돌리기는 `cleanup undo <batch ID>`. 계획은 `Exams/Past`를 `Inherited`로(낱개 파일은 족보로 표시), `Exam Review`와 `moves.jsonl`이 `Exam Review`에서 왔다고 기록한 `Exercises`의 파일을 `Study`로(시험 연결), `Notes/Exports`를 `Study`로 옮기고 빈 시험 폴더를 지운다. 출처가 불확실한 파일(그런 `Exercises`에 섞인 나머지, 이름에 정리·요약·대비·mock이 든 파일)은 검토 표시라 `--include-flagged` 없이는 옮기지 않는다. 되돌려도 `course.json`에 쓴 연결과 족보 표시는 남는다
- 노션 가져오기: `import notion <export.json>`. `export.json`은 Notion MCP로 읽은 내용을 `NotionExport` 형식으로 담은 파일이며, 실제 학업 데이터라 저장소에 넣지 않는다. 새 파일만 만들고 기존 파일은 덮어쓰지 않는다
- 노션 강의 정리와 점수: `import notes <덤프 폴더>`. 덤프 폴더는 과목마다 `<노션 페이지 ID>/index.json`, `notes/`, `assets/`를 가진다(`NotionCourseDump`). 노트 ID는 노션 페이지 ID라 다시 실행해도 중복되지 않고, 기존 항목은 덧붙이기만 한다
- 빠른 추가 한 줄로 과제: `add "<줄>" [--course <과목>] [--due <일시>|none] [--repeats <반복>|none]`. 반복은 `assignment add/set --repeats`와 같은 값을 받는다(`weekly`, `daily`, `2w`, `weekly:mon,wed`, `격주`, `3일마다`, `매주 월수`, `한 달마다`, `격주 화, 목`, `평일마다`). 앱의 빠른 추가와 같은 `QuickAdd.parse`로 이번 학기 과목, 제목, 마감, 반복, 폴더 이름을 읽어 보이고 `assignment add`를 실행한다. 옵션은 읽은 값을 덮어쓴다(마감을 지우면 반복도 지운다). 과목이나 제목을 읽지 못하면 무엇을 못 읽었는지 알리고 쓰지 않는다. 손으로 쓴 명령이지만 MCP에서는 쓰기 도구로 연다(`MCPServer.builds`)
- LMS(#132): 앱이 30분마다 모든 강의실의 과제, 자료, 공지를 읽어 제안함(`folio://proposals`)에 강의실 이름 그대로 묶어 모은다. 강의실을 과목에 잇지 않는다. 한 과목에 강의실이 둘일 수 있고 과목이 아닌 강의실(소방 교육)도 있어서, 항목을 받을 때마다 넣을 과목을 고른다(행의 "추가 ⌄", 강의실의 "모두 추가 ⌄"). 본 강의실과 숨긴 항목은 `settings.json`의 `lms`(`known`, `handled`)이고, 쓰기는 액션이다. 처음 보는 강의실은 `lms seen <강의실>… --items <항목>…`가 기록하며 그때 있던 자료와 공지를 숨겨, 그 뒤에 올라온 것과 마감이 남은 과제만 제안한다. `lms mark <항목>… [--off]`가 숨기거나 다시 제안하게 하고, `lms accept <과목> --items <items.json>`이 과제는 과제(`lmsId`로 중복을 막는다)로, 받은 파일은 `Lectures`로 가져오고 모두 숨긴다. 무엇을 제안할지는 `LMSInbox.build`가 정한다. 마감이 지났거나 제출한 과제, 어느 과목에든 이미 받은 과제, 숨긴 항목은 제안하지 않는다. 숨긴 항목(무시한 것, 처음 볼 때 넘긴 것, 과목에 넣은 과제)은 강의실 블록 끝의 접힌 "숨긴 항목"에 남아 "다시 제안"(`lms mark --off`)으로 되돌린다. 과목에 넣은 과제는 어느 과목에 있는지만 보인다. LMS 뷰어에서만 볼 수 있는 자료는 받지 않고 LMS에서 열기와 무시만 둔다. 읽기에는 앱의 키체인 로그인이 필요해 CLI에는 읽는 명령이 없다
- 자료 등록과 과제 폴더 반영: `material track [<과목>]`. 과목을 빼면 모든 과목의 파일을 추적 목록에 넣고, `Assignments/` 폴더 중 과제가 없는 것에 과제를 만든다
- 시험 일정: `import exams <exams.json>`. `exams.json`은 구글 캘린더 "시험" 캘린더에서 읽은 `CalendarExam` 목록이며 저장소에 넣지 않는다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면 바꾸지 않고 알린다
- 단원: `import units <units.json>...`. 과목마다 `{"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["11-03"], "children"}]}`. 제목으로 맞춰 없는 단원만 더하고 회차 연결은 더하기만 한다
- 예전 녹음 이름: `recording retitle [<과목>]`. 회차에 연결된 녹음 중 파일 이름이 `3주차-1.m4a`인 것만 수업 날짜(`11-03(화).m4a`)로 바꾸고 받아쓰기도 함께 옮긴다. 이동은 `moves.jsonl`의 한 묶음이고 `cleanup undo`가 파일과 `course.json`의 녹음 경로를 함께 되돌린다. 실제 GIST 폴더에는 사용자 승인 뒤에만 돌린다
- 렉처 진도: `session progress <과목>/<회차> <자료>:<시작>-<끝>...`. 적은 자료의 쪽을 한 번에 회차에 연결하고 나머지 연결은 그대로 둔다. 앱은 녹음을 멈출 때 수업 정리 시트에서 지난 수업이 끝난 다음 쪽부터 녹음 중 본 가장 뒤 쪽까지로 미리 채워 묻는다(`CourseFile.suggestedProgress`). 녹음이 끝나도 앱은 본 쪽을 회차에 저절로 연결하지 않는다. 그 시트가 회차 진도를 쓰는 유일한 곳이라, 저장하지 않고 닫으면 진도는 비고 본 쪽은 녹음(`recordings[].pages`)에만 남아 나중에 회차 메뉴로 다시 열 때 같은 값으로 채운다. `session link-viewed`는 CLI와 MCP용으로 남는다. 자료 연결 시트에서 렉처를 회차에 새로 연결해도 같은 규칙으로 시작 쪽을 채운다(`CourseFile.suggestedLink`). 렉처 PDF의 쪽 열에서 쪽을 골라 저장하거나 회차 구획의 범위를 고쳐도 같은 액션(`material link`의 `MaterialLinkSession`)으로 회차 진도를 쓴다. 새 범위의 저장 칸은 고른 방향의 끝에 뜬다(아래로 고르면 범위 아래, 위로 고르거나 한 쪽이면 위. `PageStripModel.draftBelow`). 구획의 범위를 고치는 칸과 구획 머리의 메뉴에서 "진도 지우기"를 누르면 같은 액션의 `--off`로 그 회차에서 자료 연결을 뗀다(확인은 묻지 않는다. 연결만 떼고 다시 고를 수 있어서다). 렉처 파일의 한 쪽은 한 회차의 진도라, 휴강하지 않은 두 회차의 범위가 겹치는 저장은 모델 규칙(`Session.progressOverlap`)이 막는다. 그래서 쪽 열은 회차마다 한 구획(`CourseFile.progressSections`)으로 나뉘고, 제안(`suggestedProgress`, `suggestedLink`)과 `session link-viewed`도 다른 회차가 가진 쪽을 빼고 채운다.
- 회차 편집과 수업 정리: `session wrap-up <과목>/<회차> [<자료>:<시작>-<끝>...] [--unlink <자료>...] [--unit <단원>...] [--attendance <출결>] [--date …] [--end …] [--link …] [--kind …] [--skips-review …] [--review-unfinished …]`. 진도, 단원, 출결, 일시, 종류, 링크, 복습을 한 번에 쓰고(`--unlink`는 자료 연결을 진도째 뗀다. 시트에서 처음에 체크돼 있던 연결된 자료의 행을 끄고 저장하면 이것이다. 처음부터 꺼져 있던 행은 끈 채로 저장해도 아무것도 쓰지 않는다, `Session.droppedLinks`), 끝났거나 녹음을 마친 휴강 아닌 수업이면 정리했다고 남긴다(`CourseFile.savingWrapsUp`). 수업 중에 저장하면 정리가 아니다. 주지 않은 것은 그대로 둔다. 앱의 회차 시트(`SessionSheet`)가 이 액션 하나로 저장하고, 녹음을 멈출 때, 오늘 화면의 "수업 정리" 카드(수업이 끝난 뒤 같은 과목의 다음 수업 전까지, 빠진 것이 있는 회차), 회차 메뉴의 "편집…"에서 같은 시트를 연다. 이번 학기 과목의 "수업" 페이지는 지난 공부일의 정리하지 않은 수업을 알림 카드로 모아 차례로 연다. 빠진 것과 그 기간의 규칙은 `CourseFile.wrapUpGaps`, `classesToWrapUp`, `unwrappedPastSessions`이다
- 시험 범위: `exam scope <과목>/<시험> --taught`. 그 시험 전에 지난 회차에 연결된 단원(과 상위 단원)을 범위에 더한다. 빼지는 않는다
- 졸업 요건과 학생 정보: `import requirements <requirements.json>`. 학사편람 분류 표: `import handbook <handbook.json> [--accept]`. 두 파일 모두 실제 학업 데이터라 저장소에 넣지 않는다
- 예전 회차 노트 이름: `note retitle [<과목>]`. 회차에 연결된 노트 중 이름이 `10주차-2`, `10주차-2 정리`인 것만 날짜와 단원 이름으로 바꾸고, 템플릿이 쓴 첫 제목과 과목 노트의 제목 링크(`[[10주차-2]]`), 모든 과목 노트에서 옛 이름을 보이던 ID 링크(`[[note:<ID>|10주차-2]]`)의 이름도 따라 바꾼다. 다른 이름을 붙인 ID 링크는 그대로 둔다. 이동은 `moves.jsonl`의 한 묶음이고 `cleanup undo`가 이름, 제목, 링크를 함께 되돌린다
- 노트 이름 바꾸기와 옮기기: `note mv <과목>/<노트> <새 이름>`. 새 이름은 `Notes` 기준이고 하위 폴더를 앞에 쓴다(`정리/증명`). 과목의 다른 노트(어느 폴더든)가 같은 이름이면 ` 2`를 붙인다. 제목 링크가 제목만으로 노트를 찾기 때문이다. `note retitle`처럼 course.json 경로, 첫 제목, 제목 링크와 ID 링크의 이름이 따라 바뀌고, 다른 폴더로 옮기면 노트 안의 상대 경로(그림)도 새 자리에 맞춘다. `cleanup undo`가 함께 되돌린다. `.tex` 노트는 Folio가 빌드한 PDF(`builtHash`가 맞는 `Study/<제목>.pdf`)도 같은 묶음으로 새 이름을 따라간다(자료 경로도). 새 이름의 PDF가 이미 있으면 덮어쓰지 않고 그대로 두고, Folio가 만들지 않은 같은 이름의 PDF는 옮기지 않는다. 앱은 노트 목록의 메뉴와 노트 화면의 위치 표시(노트 이름)에서 이름을 바꾸고(새 파일 이름을 보여 주는 시트가 승인), 메뉴의 "옮기기"로 `Notes`의 다른 폴더에 옮기거나(확인을 받는다) "새 폴더…"로 `Notes` 바로 안에 새 폴더를 만들어 옮긴다(옮길 경로와 만들 폴더를 보여 주는 시트가 승인). 노트를 둘 수 있는 폴더 이름(빈 이름, `/`, 숨은 폴더, `assets`, `Exports` 금지)은 `StandardLayout.noteFolderProblem` 하나가 정한다. 옮기거나 이름을 바꾼 뒤에는 노트 목록 위에 자료 화면과 같은 "방금 옮긴 것 되돌리기"가 나온다(같은 `MoveUndo`와 `UndoMoveButton`, `cleanup undo`)
- 폴더 없는 과목 옮기기: `transcript move`. 스키마 1의 `transcript.json`에 있던 과목을 같은 ID로 과목 폴더에 옮긴다. 인정학기 과목이 있으면 먼저 `semester source <학기> <출처>`로 출처를 정한다. `cleanup undo`로 되돌린다
- 학기별 학점과 GPA: `gpa`
- 노트 그림과 위젯: `note figure add <과목> <이름> --svg <파일>`이 `Notes/assets/<이름>.svg`를 새로 쓰고(같은 이름이 있으면 거절), `note figure write … --expect <해시>`가 `note figure show --json`의 해시와 디스크가 같을 때만 고쳐 쓴다. 위젯은 `note widget add|write`로 `.folio/widgets/<ID>.html`에 쓴다. 쓰기 전 검사(XML, 스크립트, 바깥 참조, 다크 규칙 `prefers-color-scheme: dark`, 위젯의 바깥 주소)는 `FolioDomain`의 `NoteFigure.problems`와 `NoteWidget.problems`다. `note figure render`와 `note widget render`는 라이트·다크, 폭 480과 900으로 그린 PNG(위젯은 콘솔 오류도)를 돌려주고, MCP에서는 이미지 내용으로 간다. 노트 형식 안내는 `NoteWritingGuide` 하나이고 `note format`과 `folio skill`이 보인다. 그려 보기의 색은 앱 테스트 `NoteThemeCopyTests`가 앱의 `NoteWidgets.themeCSS`에서 만든 사본이라, `theme.swift`나 `themeCSS`를 바꾸면 `TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app`으로 다시 만든다. 패널의 제안 카드는 그림을 노트에서처럼 지금 모양(라이트나 다크)으로 보인다
- 앱 링크: `link <종류> [<대상>] [--page N | --heading <제목> | --block <ID> | --time <m:ss> | --section <구역>]`이 `folio://` 주소를 쓰고, `open`이 같은 인자로 앱에서 연다. 노트, `.tex`의 `\href{…}`, 다른 앱에 붙여 쓴다

작업을 끝냈다고 보고하기 전에 관련 테스트와 빌드가 통과하는지 확인한다.

## 이슈와 작업 순서

할 일은 GitHub 이슈로, 순서와 상태는 [Project](https://github.com/users/rhseung/projects/10)로 관리한다. 별도의 명세 문서는 두지 않는다.

- 기능 하나는 이슈 하나다. 이슈 제목은 앱 기능 목록에서 부를 법한 기능 이름으로 짓는다. 세부 작업은 따로 이슈로 만들지 않고 본문 체크리스트로 둔다. 모델, 화면, CLI 같은 층별로 이슈를 나누지 않는다.
- 이슈마다 영역 라벨(`area/*`) 하나를 붙이고 그 영역의 상위 이슈(`epic` 라벨) 아래 하위 이슈로 둔다. 상위 이슈 본문에는 하위 기능 목록을 적는다. 상위 이슈의 진행 순서는 Project의 `Order` 필드로 둔다.
- 모든 이슈에 `Priority`(P0~P3), `Size`(XS~XL), `Status`(Backlog, Ready, In progress, Blocked, Done)를 정한다. Ready는 막는 이슈가 모두 닫힌 상태이고, 열린 이슈에 막힌 이슈는 Blocked로 둔다.
- 결정과 조사는 이슈로 두지 않는다. 이미 정한 내용과 남은 논의, 조사할 것은 그 결정이 영향을 주는 기능 이슈 본문의 `정한 것` / `정할 것` 절에 적는다. `정할 것`에 남은 부분은 사용자가 답할 때까지 구현하지 않는다. 사용자와 새로 정하면 `정할 것`에서 `정한 것`으로 옮긴다.
- 지금 하지 않기로 미룬 기능에는 `later` 라벨을 붙인다(`later`는 P3, Backlog). 기능의 일부만 미룰 때는 그 체크리스트 항목에 "(나중에)"를 붙인다.
- 사용자가 지정한 일을 먼저 한다. 그 밖의 다음 할 일은 Ready 중 상위 이슈의 `Order`가 앞선 것, 같은 상위 이슈 안에서는 `Priority`가 높은 것이다. P0는 순서와 상관없이 먼저 한다. `main`의 CI가 실패하면 P0로 보고 다른 일보다 먼저 고친다.
- 상태는 손으로 옮긴다(Project 자동화는 하위 이슈 추가만 켜 있다). 시작하면 In progress, PR 본문에 `Closes #번호`를 적고, 닫히면 Done으로 옮긴다. 닫힌 이슈에 막혀 있던 이슈는 남은 막힘이 없으면 Ready로 옮긴다. 일부만 끝냈으면 닫지 않고, 끝낸 항목을 체크하고 남은 일을 체크리스트에 적는다. 한 이슈가 테스트까지 끝나면 커밋하고 다음으로 넘어간다.
- PR은 `main` 룰셋의 승인 1개와 검사(test, build)를 모두 채워야 머지된다. 승인은 리뷰 봇이 하고(Dependabot PR도 리뷰 봇이 리뷰한다), 문서(`docs/`, 최상위 `*.md`, `.github/**/*.md`)만 바뀐 PR은 리뷰 없이 Actions가 한다(`review.yml`). 테스트 픽스처처럼 그 밖에 있는 `.md`는 리뷰를 받는다. CI(`ci.yml`)는 PR이 바꾼 파일이 닿지 않는 검사를 건너뛰고(건너뛴 검사도 룰셋에는 통과다. 어떤 파일이 어느 검사에 닿는지는 `changes` 작업에 있다), main push가 남긴 빌드 캐시(Xcode 작업은 DerivedData, `test`는 패키지의 `.build`)에서 시작한다. 체크아웃이 모든 파일의 시각을 새로 찍으므로 CI는 파일 시각을 내용(blob 해시)에서 정해, 캐시된 빌드가 바뀐 파일만 다시 컴파일하게 한다. 커밋하지 않는 프로젝트의 `Package.resolved`는 커밋한 `packages/*/Package.resolved`와 `project.yml`이 같은 캐시에서만 받아 패키지 해석을 건너뛰고, 다르거나 main push면 새로 해석한다. main push는 모든 검사를 돌린다. PR은 스쿼시로만 머지된다(룰셋이 다른 방식을 막는다). 커밋 제목은 PR 제목, 본문은 PR 본문이 되므로 PR 제목을 커밋 규칙대로 짓는다. PR을 열면 `gh pr merge --auto --squash`로 자동 머지를 걸어 둔다. 관리자 권한(`--admin`)으로 룰셋을 우회하지 않는다.
- 사용자가 이슈 없이 시킨 일은 바로 하고, 남은 범위나 새로 정한 동작은 해당 이슈에 적거나 새 이슈로 만든다.

### PR 전 점검

리뷰 봇이 여러 PR에서 거듭 지적한 실수다. PR을 열기 전에 바뀐 코드에 대해 하나씩 확인한다.

- 화면을 바꾼 PR은 눈으로 확인한 증거를 본문에 붙인다. 바뀐 화면을 `mise run render`(`FOLIO_RENDER_SCREENS`로 좁혀서)로 그린 PNG를 붙이고, 렌더가 그리지 못하는 것(리퀴드 글라스, 노트 보기와 `WKWebView`, 뷰 안에서 여는 시트, 창 틀)과 스크롤, 클릭 같은 동작은 `FOLIO_SNAPSHOT_DIR` 창 스냅숏(`docs/DESIGN.md` 마지막 절)이나 실행 화면으로 확인한다. 리뷰 봇은 코드만 읽으므로 화면의 고장은 이 확인으로만 잡힌다.
    - 그림은 본문에 바로 보이게 넣는다. 브랜치에 `pr-renders/<이슈>/`로 커밋하고 `<img src="https://raw.githubusercontent.com/rhseung/folio/<커밋>/pr-renders/…" width="…">`처럼 커밋 해시로 가리킨 뒤, 머지 전에 그 폴더를 브랜치에서 지운다. 디자인이 바뀌면 이전과 이후를 나란히 두고, 라이트·다크와 바뀐 폭을 함께 보인다. 그림마다 무엇을 보면 되는지 한 줄을 붙인다.
- 무엇을 보여 줄지, 언제 막을지, 날짜와 개수를 어떻게 셀지 같은 규칙을 뷰나 모델에 다시 적지 않았는지 본다. 규칙은 `FolioDomain`에 두고 `swift test`로 검사한다.
- `#if os(macOS)`나 `#if os(iOS)` 안에 넣은 기능에 다른 플랫폼 쪽(`#else`)이 있는지 본다. 없다면 그 플랫폼에 필요 없는 이유가 분명해야 한다. `mise run build-ipad`도 돌린다.
- 더하거나 바꾼 화면 요소를 포인터와 터치 둘 다로 쓸 수 있는지 본다. 마우스 올림, 도움말, 두 번 클릭, 수식 키 클릭, 오른쪽 클릭, 키보드만으로 되는 일이 없고, 터치 표적이 44pt 이상이어야 한다(`docs/DESIGN.md` "입력 기기").
- 날짜가 공부일(`Settings.studyDay`, 하루 경계 새벽 4시)인지 달력 날짜인지 구분한다. 오늘 할 일, 마감까지 남은 날, 복습 날짜는 공부일로 센다. 경계 직전과 직후를 테스트한다.
- 테스트와 미리보기가 실제 `Application Support` 폴더나 GIST 폴더를 읽거나 쓰지 않는지 본다.
- 사용자에게 보이는 변화가 있는 PR은 본문에 `## 패치 노트` 절을 둔다. 줄마다 `- feat: …`, `- fix: …`, `- change: …` 중 하나로 쓰고(종류는 커밋 규칙처럼 영어 그대로, 번역하지 않는다), 그 자리나 설정 탭이 있으면 끝에 `(folio://today)`, `(folio://settings/class)`처럼 링크를 붙인다. 앱의 새 기능 화면과 업데이트 뒤 시트가 이 줄을 종류 순으로 정렬해 칩과 함께 보여 주므로 사용자 말로 짧게 쓴다(개발 용어, PR 번호, 파일 이름 없이). 링크는 앱의 자리와 설정 탭만 쓴다. 노트나 과목처럼 사람마다 다른 항목은 가리키지 않는다. `feat`가 든 버전만 업데이트 뒤 시트를 띄우므로 고침을 `feat`로 올려 적지 않는다. CI, 테스트, 문서, 리팩터링처럼 보이는 변화가 없는 PR은 절을 쓰지 않는다. 머지 뒤에 고쳐도 릴리스 전이면 반영된다.
- 동작이나 규칙이 바뀌었으면 이 파일, `docs/DESIGN.md`, 해당 이슈 본문을 같은 PR에서 고친다.

### 새 이슈

- 만들기 전에 기존 이슈(닫힌 것 포함)에서 같은 일을 찾는다.
    - 열린 이슈와 같은 일이면 만들지 않는다. 발전시킨 것이면 그 이슈 본문을 고치거나, 새 내용과 합쳐 하나로 만든다. 합칠 때는 닫는 쪽의 범위를 남는 쪽 본문 체크리스트로 옮기고, 라벨, 상위 이슈, blocked-by 관계도 남는 쪽으로 옮긴다. 닫는 쪽에는 "→ #N로 합침" 댓글을 달고 not planned로 닫은 뒤 상위 이슈의 하위 이슈 목록에서 뺀다.
    - 끝나서 닫힌 이슈와 같은 일이면 다시 열지 않고, 고장이나 보완을 새 이슈로 만들어 원래 이슈 번호를 적는다. 하지 않기로 닫힌 이슈는 다시 열기 전에 사용자에게 묻는다.
- 맞는 상위 이슈가 있으면 그 하위 이슈로 넣는다. 맞는 것이 없을 때, 여러 이슈로 나뉠 규모면 상위 이슈(`epic`, 새 `area/*` 라벨)를 새로 만들고 `Order` 자리를 사용자에게 제안한다. 이슈 하나로 끝날 일이면 가장 가까운 상위 이슈 아래에 둔다. 하위 이슈가 하나뿐인 상위 이슈는 만들지 않는다.
- 기대거나 막는 이슈와는 blocked-by 관계를 건다. 아직 없는 축(위 "구조 축" 표)에 기대는 기능은 그 축 이슈에 막히게 걸거나 축과 함께 만든다. 화면마다 임시로 구현하지 않는다. 본문에서도 관련 이슈 번호를 적어 서로 찾아갈 수 있게 한다.
- 예시 하나가 아니라 그 기능이 다뤄야 할 범위를 적고, 같은 일을 여러 이슈로 쪼개지 않는다. 기존 기능에 딸린 일이면 새 이슈 대신 그 기능 이슈의 체크리스트에 더한다.
- 새로 생긴 결정이나 조사는 이슈로 만들지 않고, 영향을 받는 기능 이슈의 `정할 것`에 적는다.

## UI

- 화면을 만들거나 고치기 전에 `docs/DESIGN.md`를 읽는다. 원칙, 토큰과 구성 요소를 언제 쓰는지, 패턴, 새 토큰을 만드는 규칙이 있다.
- 디자인은 시안 C(밝은 종이 질감, 사이드바·과목 열·본문의 3단)에 리퀴드 글라스를 더한 방향이다. Mac 창은 시안 D처럼 반투명 창 재질 위에 사이드바와 툴바가 평평하게 놓이고 본문이 둥근 패널로 들어간다. 디자인 시스템: https://claude.ai/artifact/NQsFWSkuyHUDETivg5K5bA. 시안 캔버스 "Folio 시안": https://claude.ai/artifact/FT5gk3v1afr7pEsBFd6MLy. 새 시안은 이 캔버스의 영역 페이지에 디자인 시스템으로 그리고, 따로 Artifact를 만들지 않는다.
- 색, 간격, 모서리, 글꼴은 `app/design/theme.swift`에서만 정의하고 모든 화면이 그 토큰만 쓴다. 라이트와 다크 값을 함께 둔다. 공용 구성 요소는 `app/design/`에 역할별 파일(`Layout`, `Containers`, `Indicators`, `Inputs`, `Interaction`)로 있다. `mise run check-design`이 화면 코드의 글꼴 크기, 색, 모서리 숫자를 잡는다.
- 리퀴드 글라스는 창 틀(사이드바, 툴바)과 떠 있는 요소(빠른 추가, 팝오버, Claude 패널)에만 쓴다. 본문은 종이 색으로 둔다. 창 구조와 유리 위 구성 요소의 규칙은 `docs/DESIGN.md`의 "창 구조" 절에 있다.
- 과목 강조색은 `course.json`의 `color`(프리셋 이름)를 `CourseAccent`로 읽고, 비어 있으면 학기 안 순서로 프리셋을 고른다(무채색 `graphite`는 고르지 않는다). 예전에 고른 `#RRGGBB`는 파일을 바꾸지 않고 가장 가까운 프리셋으로 읽는다. 색은 프리셋 견본에서만 고른다. 과목 화면은 `\.accent` 환경값으로 색을 주입받는다. 프리셋 이름과 고르는 순서는 `FolioDomain`의 `CourseColor`가 정하고 앱과 CLI가 함께 쓴다. 색 값은 `theme.swift`에 둔다.

## 미결정 사항

미결정 사항은 해당 기능 이슈의 `정할 것` 절에 있다. 정해지기 전까지 지킬 것:

- 학업 외 폴더와 `2026-2`의 경진대회 자료(#106): 정리 도구는 이 항목을 건드리지 않는다.
- GIST 학칙의 재수강 처리, 졸업 평점 산정, 우등 졸업 기준(#123): 계산 규칙은 설정값으로 두고 하드코딩하지 않는다.
