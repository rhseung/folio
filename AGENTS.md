# Folio

과목을 중심으로 강의 자료, 노트, 손필기, 복습, 퀴즈, 과제, 성적을 관리하는 Apple 기기용 네이티브 앱입니다. 무엇을 만들지와 남은 일은 GitHub 이슈와 [Project](https://github.com/users/rhseung/projects/10)에 있습니다. 이 파일에는 어떻게 만들지에 대한 원칙과 판단 기준을 적습니다. 작업을 시작하기 전에 해당 이슈와 그 상위 이슈를 먼저 읽습니다.

코드나 도구가 원본인 설명은 여기에 되풀이하지 않습니다. 작업 목록과 설명은 `mise tasks`, CLI 명령은 `folio help <명령>`, 검사 규칙은 `sources/tools/lint`의 규칙 이름(`mise run check-code`)이 원본입니다. 영역별 세부는 아래 문서에 있고, 그 영역을 고칠 때만 읽습니다.

| 문서 | 읽을 때 |
| --- | --- |
| `docs/DESIGN.md`, `docs/design/` | 화면을 만들거나 고칠 때 |
| `docs/axes.md` | 구조 축에 기능을 얹거나 축을 고칠 때 |
| `docs/notes.md` | 노트의 문법, 링크, 편집 보기와 미리보기, 그 회귀 검사 |
| `docs/sessions.md` | 회차, 녹음, 진도, 수업 정리 |
| `docs/mcp.md` | `folio mcp`, Claude 패널의 제안 단계, 자료 읽기 |
| `docs/lms.md` | GIST LMS 읽기와 LMS 탭 |
| `docs/tex.md` | TeX 엔진 Tectonic |
| `docs/release.md` | 버전, 패치 노트, 릴리스, 설치 |
| `docs/ci.md` | CI 작업, 검사 경로, 빌드 캐시 |

## 소통 규칙

- 사용자와는 한국어로 대화한다. 영어로 답하지 않는다.
- 식별자와 커밋 메시지는 영어로, 주석은 한국어로 쓴다.
- PR 본문은 한국어로 쓴다. 사용자가 읽고 무엇이 바뀌었는지 이해해야 하기 때문이다. 기능은 이슈 번호만 쓰지 않고 이름과 함께 쓴다("툴바 탭(#304)"). PR 제목은 스쿼시 커밋 제목이 되므로 커밋 규칙대로 영어로 쓴다. 스쿼시 커밋은 PR 제목과 PR 본문의 `## 패치 노트` 절만 남긴다(매니저가 자동 머지를 걸 때 커밋 본문을 정한다).
- 앱의 UI 문자열은 한국어로 쓰고 String Catalog(`Localizable.xcstrings`)에 키로 둔다("문자열 키" 절).
- 이슈와 다르게 구현해야 할 이유가 생기면 구현하기 전에 사용자에게 묻는다. 이슈에 없는 기능을 임의로 추가하지 않는다. 사용자와 새로 정한 동작은 그 이슈 본문에 적는다.

## 기술 기준

- 최소 지원 버전은 macOS 26, iPadOS 26이다. `project.yml`과 `Package.swift`에 있고, 도구 제약으로 하나로 합칠 수 없어 함께 고친다.
- Swift 6 언어 모드를 쓰고 strict concurrency 검사를 켠다.
- UI는 SwiftUI로 만든다. AppKit과 UIKit은 SwiftUI로 할 수 없는 부분(PencilKit 캔버스, PDFKit 뷰)에만 쓴다.
- 직접 구현보다 잘 관리되는 라이브러리를 먼저 쓴다. 표준 라이브러리와 Apple 프레임워크로 되지 않는 일이면, 직접 짜기 전에 널리 쓰이고 유지되는 Swift 패키지를 찾는다. 라이브러리가 데이터 원칙을 어기는 경우(예: 노트 frontmatter의 원문을 보존하지 못하는 YAML 파서)에만 직접 구현하고 그 이유를 주석에 남긴다.
- 외부 의존성은 Swift Package Manager로만 추가한다. 새 의존성은 넣은 뒤 사용자에게 무엇을 왜 넣었는지 알리고 커밋 메시지에도 남긴다. 예외는 둘이다.
    - 웹 번들(`sources/web`): 수식 변환, 코드 하이라이팅, 노트 미리보기, Claude 패널에 쓴다. npm 패키지를 정확한 버전으로 고정하고 `mise run build-web`으로 `app/resources/web/`에 묶는다. 묶은 결과는 커밋해서 앱 빌드에 node가 필요 없게 한다.
    - TeX 엔진 Tectonic: iPadOS가 다른 프로그램을 띄우지 못하게 해서 정적 라이브러리로 앱 안에 넣는다(`docs/tex.md`).

## 프로젝트 구조

플랫폼과 무관한 로직은 Swift 패키지의 모듈로 분리해서 `swift test`로 Xcode 없이 테스트한다. 앱은 패키지 밖에서 Xcode가 빌드하므로 저장소 최상위 `app/`에 둔다. 코드는 `sources/<모듈>`, 그 단위 테스트는 `tests/unit/<모듈>`, 앱을 띄워 바깥에서 조작하는 테스트는 `tests/e2e/<모듈>`이다. 언어와 빌드 도구가 달라도(Swift 패키지, Xcode 앱, npm 웹 번들, Rust 브리지) 같다. 폴더 이름에는 `folio-` 접두어를 붙이지 않고, 모듈과 제품 이름(`FolioDomain`)은 Swift 관례대로 둔다.

```text
folio/
  app/                # 멀티플랫폼 앱 타깃(macOS, iPadOS, iOS). project.yml이 읽는다
    folio-app.swift   # 진입점
    workspace/        # Workspace와 그 확장, services/(녹음, 시계, 알림 같은 앱 서비스)
    window/           # 창 틀: 화면 고르기, 탭, 칸, 링크 창, 항목 시트, debug/(창과 칸을 재는 DEBUG 훅)
    design/ platform/ features/ resources/
  docs/               # 디자인 시스템과 영역별 문서
  sources/
    core/ domain/ storage/ actions/ index/ lms/ ai/ markdown/ cli/ macros/ fixtures/   # 아래 "레이어"의 모듈
    tools/            # 실행 파일마다 폴더 하나. 이름은 실행 파일 이름에서 folio-를 뺀 것이다
      folio/          # folio의 진입점(명령은 FolioCLI에 있다)
      gen/ fixture/   # folio-gen, folio-fixture
      lint/           # AGENTS.md 규칙 검사기 folio-lint(`mise run check-code`)
      dev/            # 개발 도구 folio-dev(버전, 태그, 릴리스)
    web/              # 노트 미리보기와 Claude 패널의 웹 번들 원본
    tectonic/         # Tectonic 정적 라이브러리의 원본과 받기(`docs/tex.md`)
  tests/
    unit/<모듈>/      # sources와 1:1(tools/lint, tools/dev 포함). app/은 화면 모델과 노트 보기 검사(`test-app`), app/ipad/는 iPad 검사(`test-ipad`)
    e2e/app/          # 앱을 띄워 접근성을 검사한다(`test-a11y`, CI만 돌린다)
  Package.swift       # Swift 패키지 하나. 앱 밖의 모든 모듈과 테스트, 실행 파일(folio, folio-gen, folio-fixture, folio-lint, folio-dev)
  project.yml         # 앱의 Xcode 프로젝트(`mise run generate`)
  mise.toml           # 도구 버전, 환경 변수, 한 줄짜리 작업. 여러 줄 작업과 lefthook·CI가 부르는 스크립트는 .mise/tasks/<이름>
  .swiftlint-baseline.json, .folio-lint-baseline.txt   # 두 린트의 기준선
```

폴더의 깊이는 무게를 따른다. 무게는 담은 Swift 파일 수와 다른 코드가 그 폴더에 기대는 정도다. 많은 코드가 기대는 것(바탕 타입, Workspace, 디자인 토큰)은 얕은 곳에 두고, 한 곳만 쓰는 것은 그곳 안에 둔다. 한 층에는 기준을 하나만 쓴다.

| 층 | 기준 |
| --- | --- |
| 저장소 최상위 | 무엇을 만드는가: 앱(`app/`), 패키지 코드(`sources/`), 테스트(`tests/`), 문서(`docs/`) |
| `sources/` 바로 아래 | 모듈 하나에 폴더 하나. 실행 파일은 `sources/tools/<이름>`에 모은다 |
| 어느 폴더든 바로 아래의 파일 | 그 폴더의 하위 폴더들이 함께 쓰는 바탕(액션 틀, CLI 출력, 쓰기 바탕). 그래서 모듈 안에 `core`, `shared` 같은 폴더를 만들지 않는다 |
| 모듈 바로 아래의 폴더 | 학업을 다루는 영역 층(`sources/domain`, `storage`, `actions`, `cli/commands`, `cli/generated`, `app/features`, `app/platform`과 이를 따르는 `tests/unit`)은 영역이다. 그 밖의 모듈(`markdown`, `ai`, `design`)은 그 모듈의 주제다 |
| 영역 안 | 하위 영역이나 대상. 뷰, 모델, 행 같은 역할은 파일 이름이 말하고 폴더로 나누지 않는다 |

- 영역 이름은 모든 모듈이 같다. 성적은 domain, actions, cli, app, tests 어디서나 `grades/`다. 영역 이름표는 folio-lint의 표(`sources/tools/lint/area.swift`)가 원본이다. 셀 수 있는 영역은 복수(`courses`, `notes`)로 쓰고, 표에 없는 영역이 생기면 표에 먼저 더한다. 영역 층의 폴더는 이름표의 이름이어야 한다(`area-folder`). 층의 바탕인 `actions/query`와 생성 폴더 `generated`는 뺀다.
- 작은 폴더는 합치고 넘치는 폴더는 나눈다. Swift 파일(하위 폴더 포함)이 하나뿐인 폴더는 두지 않고, 둘뿐인 폴더는 영역 이름일 때만 둔다(`folder-small`). 다음 폴더는 파일 수로 보지 않는다.
    - 영역 층 바로 아래의 영역 폴더: 자리는 영역 이름표가 정하므로 파일이 하나여도 다른 영역에 옮길 수 없다(`actions/claude`의 `ProposalList`).
    - 소스 폴더를 따라 만든 `tests/unit`의 폴더: 테스트는 소스와 같은 경로로 나누므로 무게를 소스 폴더가 정한다(`tests/unit/domain/exams`는 `sources/domain/exams`를 따른다).
    - 모듈 폴더(`sources/<모듈>`, `sources/tools/<도구>`, `tests/unit/<모듈>`, `tests/e2e/<모듈>`)와 `generated`: 모듈 경계는 `Package.swift`와 `project.yml`이, 생성 폴더는 생성기가 정한다.
- 바로 아래 파일이 20개를 넘으면 하위 영역이나 대상으로 나눈다(`folder-size`). 나눈 폴더의 이름은 하위 영역의 이름이고, 그 안의 타입 이름이나 부모 이름을 되풀이하지 않는다(`sessions/sessions`가 아니라 `sessions/transcription`).
- `app`, `core`, `shared`처럼 무거운 이름은 최상위나 `sources/` 바로 아래에만 쓴다. 모듈 안에 `core`, `shared`, `common`, `base`, `utils`, `helpers`, `misc`, `app` 폴더를 만들지 않고, `app/features` 아래에 `-view`, `-model`로 끝나는 폴더를 만들지 않는다(`folder-name`).
- 축의 틀(타입, 등록, 검사)은 그 축을 쓰는 가장 낮은 곳의 바탕에 두고, 종류마다의 선언은 그 종류의 영역 폴더에 둔다. `@Action`의 틀은 `actions/` 바로 아래에, 액션은 영역 폴더에 있다. 항목 메뉴의 `<종류>-menu-command`도 그 종류의 영역에 둔다.

- 파일 밖에서 쓰는 타입 하나에 파일 하나를 두고, 파일 이름은 타입 이름 전체의 케밥 케이스다(`NoteFigureAdd`: `note-figure-add.swift`). Swift가 한 모듈 안에 같은 파일 이름을 두 번 받지 않아서, 폴더가 이름의 앞부분을 말해도 파일 이름을 줄이지 않는다. 그 파일 안에서만 쓰는 `private` 조각과 한 값의 `extension`은 그 값의 파일에 둔다(`one-type-per-file`).
- 액션은 `sources/actions/<영역>/[<대상>/]<타입 이름 케밥>.swift`다(`action-path`). 영역은 타입 이름의 앞 낱말로 영역 이름표(`sources/tools/lint/area.swift`)에서 정하고, 대상 폴더는 영역에 파일이 20개를 넘을 때만 이름의 낱말로 둔다(`notes/figure/note-figure-add.swift`). 여러 액션이 함께 쓰는 도우미는 그 영역 폴더의 이름 있는 파일(`notes/note-lookup.swift`)에, 모든 액션의 바탕은 `actions/` 바로 아래에, 읽기의 바탕은 `actions/query/`에 둔다. 읽기 선언(`@Query`)도 같은 규칙이다. CLI의 손 명령은 `sources/cli/commands/<영역>/`에 같은 모양으로 두고, 하위 명령마다 `extension <상위 명령> { struct … }` 파일 하나다.
- 계산 로직(환산 점수, GPA, 복습 간격, 우선순위)은 순수 함수로 만들고 단위 테스트를 붙인다.
- Claude 호출은 `FolioAI`의 프로토콜 뒤에 둔다. 테스트에서는 가짜 프로바이더를 쓴다.

### 레이어

의존은 아래 방향으로만 흐른다. 모듈 경계로 나눴으므로 거꾸로 import하면 컴파일이 실패한다. 컴파일러가 막지 못하는 시스템 프레임워크 쪽(패키지의 `import SwiftUI`, `FolioCore`, `FolioDomain`, `FolioMarkdown`의 디스크 접근, `app/features`의 `FileManager`)은 `layer` 규칙이 본다.

```text
App (SwiftUI), FolioCLI  ->  FolioActions  ->  FolioAI, FolioStorage  ->  FolioDomain  ->  FolioCore
App (SwiftUI), FolioCLI  ->  FolioIndex  ->  FolioStorage   (검색 색인)
App (SwiftUI)  ->  FolioLMS  ->  FolioDomain   (GIST LMS 읽기)
FolioStorage, FolioActions, App  ->  FolioMarkdown   (노트 frontmatter와 렌더링)
FolioActions  ..>  FolioMacros   (@Action 매크로. 컴파일 때만 쓰고 앱에 링크되지 않는다)
FolioDev  ->  FolioDomain   (릴리스 본문을 PatchNotes로 쓴다)
FolioGen  ->  FolioActions   (액션 목록과 CLI 명령, 명령 트리를 쓴다)
```

| 모듈 | 맡는 일 | 하지 않는 일 |
| --- | --- | --- |
| `FolioCore` | 학업 낱말이 없는 바탕 타입: `Entity`와 `DeviceID`, `LocalDate`, `ClockText`, `WeekdayLetters`, `JSONValue`, `LogEvent`, `StatusTone`, `Korean`, `ContentHash`, `TextDiff`, `FileNameParts`. 쓰는 파일마다 `import FolioCore`를 적는다 | 과목이나 성적표 같은 엔티티를 아는 타입, 파일 입출력, UI. 모델 규칙 엔진은 규칙마다 `World`를 받으므로 Domain에 둔다 |
| `FolioDomain` | 모델 규칙 엔진(`Model`, `Document`, `World`), 엔티티, 값 타입, 표준 구조 규칙, 성적·GPA·복습 계산, 모든 데이터 규칙. 디스크에서 읽은 내용은 `FolderTree` 같은 값으로 받는다 | 파일 입출력, UI, 네트워크 |
| `FolioStorage` | GIST 폴더 읽기와 쓰기, JSON 스키마 버전과 마이그레이션, 원자적 쓰기, 기기별 로그, 파일 추적 | 규칙 판단. 판단은 Domain에 맡긴다 |
| `FolioMarkdown` | 마크다운 파서와 확장 문법, frontmatter, HTML 렌더러, 제목 판단(`NoteOutline`), 편집 보기의 입력 규칙(`editing/`, Mac과 iPad가 함께 쓰는 순수 함수). 세부는 `docs/notes.md` | 다른 Folio 모듈에 의존 |
| `FolioAI` | Claude API 호출(Swift SDK가 없어 문서화된 HTTP 형식 그대로), 작업별 모델과 effort 표, 맥락 구성, 응답 스키마, 사용량과 비용 | 파일 쓰기. 결과는 제안으로만 돌려준다 |
| `FolioActions` | 데이터를 바꾸는 모든 동작. Domain의 변환과 Storage의 쓰기, 폴더 생성, 로그를 한 액션으로 묶는다. 액션 목록의 단일 출처. 읽기 선언(`@Query`)도 둔다 | UI, 출력 형식. 앱과 CLI가 같은 구현을 부른다 |
| `FolioIndex` | 기기별 로컬 SQLite 검색 색인(GRDB, FTS5 trigram). 캐시 폴더에 두며 지워도 다시 만든다 | GIST 폴더에 쓰기. 순위와 발췌는 Domain의 `SearchIndex`에 맡긴다 |
| `FolioLMS` | GIST LMS(Coursemos) 읽기(`docs/lms.md`) | 파일 쓰기와 제안 판단 |
| `FolioCLI` | 터미널 도구 `folio`의 명령 라이브러리. 실행 파일은 진입점만 있는 `FolioCommand`다(실행 타깃의 테스트 빌드에는 카탈로그 심볼이 생기지 않아서다). 모든 액션을 `<대상> <동작>` 명령으로 열고, 사람용 출력과 `--json` 출력을 만든다. 노트 그림과 위젯의 그려 보기는 macOS에서 화면 밖 `WKWebView`로 그리고, 앱의 노트 색은 링크할 수 없어 생성한 사본(`NoteTheme`)을 쓴다 | 액션 로직. 명령은 인자를 해석해 `FolioActions`를 부르고 결과를 그리기만 한다 |
| `FolioMacros` | `@Action`과 필드 표시. 선언에서 입력 형식, init, 코딩, `spec`을 만들고 실수(맨 `UUID`, 없는 `{필드}`, 확인 문구 없는 삭제)를 컴파일 오류로 막는다 | 실행 코드. 앱과 CLI에 링크되지 않는다 |
| `FolioGen` | `@Action`과 `@Query` 선언을 읽어 `Actions.all`, `Queries.all`(`#if` 안의 선언은 같은 조건 안에), 생성 명령(명령 하나에 파일 하나), 명령 트리(`command-tree.swift`)를 쓴다. 결과는 커밋한다 | FolioCLI에 의존. 생성 파일이 깨져도 다시 만들 수 있어야 한다 |
| `FolioDev` | 개발 도구 `folio-dev`. 태그에서 버전 읽기, 다음 버전 정하기, 태그, 릴리스 본문(`docs/release.md`) | 앱과 CLI에 링크되지 않는다. 앱 작업은 이 도구를 빌드하지 않는다 |
| `FolioFixtures` | 테스트와 개발 실행에 쓰는 가짜 GIST 폴더. 공개 저장소에 과목 파일 폴더를 두지 않기 위해 파일을 코드에 두고 쓸 때 펼친다. 화면 확인용 상황(`Scenario`)은 고정된 시각 기준으로 액션을 돌려 만든다 | CLI에 링크되지 않는다. 앱에서는 `#if DEBUG`의 `Workspace.scenario`만 쓴다 |
| App | 화면. `folio-app.swift`(진입점), `workspace/`(Workspace와 앱 서비스), `window/`(창 틀과 탐색), `design/`(토큰과 공용 구성 요소), `features/<화면>/`, `platform/`(PencilKit, PDFKit, WKWebView 연결, 파일 보기, 노트 미리보기와 편집 보기), `resources/` | 파일 시스템 직접 접근과 `course.json` 값의 직접 변경. 반드시 `FolioActions`를 거친다 |

앱(`app/`) 밖의 모듈은 SwiftUI를 import하지 않는다. 새 관심사가 생기면 위 표에 모듈을 추가하고 방향을 정한 뒤 만든다.

### 액션

앱에 새 데이터 조작을 넣을 때는 `FolioActions`에 `@Action`으로 액션을 선언하고, 같은 변경에서 테스트를 함께 넣는다. 액션에 CLI 명령이 없으면 테스트가 실패한다.

- 필드의 형식이 입력을 정한다. 가리키는 항목은 종류의 ID(`Exam.ID`, 경로로 가리키는 노트는 `Note.Path`)로, 새 항목의 ID는 `@New`, 위치 인자는 `@Arg`로 쓴다. `///` 주석이 CLI 도움말이다.
- `set`의 필드는 `Patch<T>`다(빠지면 그대로, `T?`면 `none`/`null`로 지운다). 액션이 지금 값 위에 준 칸만 덮으므로 CLI가 지금 값을 읽어 빈 칸을 채우지 않는다. 시트처럼 값 전체를 가진 화면은 모든 칸을 `.set`으로 보내거나 `Patch.changed(이전, 새 값)`으로 바뀐 칸만 보낸다.
- CLI 입력의 모양도 선언에 적는다(`@CLIName`, `@FromFile`, `@Folder`, `@Off`, `@Parsed`, `@Hidden`). 위치 인자의 순서는 필드 순서이고, 과목 인자 뒤의 항목 인자는 `<과목>/<항목>` 하나로 받는다. 과목을 `Course.ID?`로 두면 빼서 모든 과목에 한다. 빠지면 지금 것으로 채울 값(지금 학기)은 옵셔널로 두고 액션이 채운다. `made`가 `moves.jsonl` 묶음이면 `undoable: true`로 되돌리는 법을 보인다.
- 확인 문구와 완료 문구는 `{필드}` 자리표시자로 쓰고, ID는 실행하기 전에 이름으로 바뀐다. `.removes`와 `.moves`는 `confirm:`이 있어야 컴파일된다.
- 선언한 뒤 `mise run gen-cli`로 생성 파일을 다시 만든다. 목록에 손으로 줄을 더하지 않는다. 생성기가 다루지 못하는 입력(한 옵션을 두 필드로 나누기, 플래그 여럿이 값 하나가 되기, 액션 여러 번 돌리기, 해시 비교)만 손으로 쓰고 `cli: .manual(reason: "...")`에 이유를 적는다. 손 명령도 같은 액션 하나를 `perform(spec:)`으로 부른다.
- 규칙은 액션이 아니라 `FolioDomain`의 모델(`course-rules.swift`의 `Document.model`)에 둔다. 모든 저장이 그 규칙으로 검사한다.
- 화면은 규칙을 다시 적지 않는다. 버튼을 켜고 끌 때는 `workspace.can(액션)`, 막힌 이유는 `refusal`, 확인 문구는 `confirmation`으로 묻는다. 앱이 보여 주는 문서로 미리 실행해 본다.
- `confirm:`이 있는 액션은 `workspace.ask(액션)`으로 실행하고 결과를 모델의 `pending`에 둔다. 뷰는 `.confirming($model.pending)`으로 묻고, 막힌 액션이면 묻지 않고 이유를 보여 준다.
- 여러 항목을 한 번에 바꾸는 버튼은 액션을 반복해 부르지 않고 목록을 받는 액션 하나로 실행한다. 그래야 한 번 묻고, 하나가 막히면 아무것도 쓰기 전에 멈춘다.

### 구조 축

`@Action`처럼 한 번 선언하고 여러 곳이 같은 선언을 읽는 구조를 축이라 부른다. 새 기능은 맞는 축 위에 얹고, 같은 일을 화면마다 따로 구현하지 않는다. 축마다 지킬 결정은 `docs/axes.md`에 있다.

- 축은 첫 소비자 두세 개와 함께 만든다. 소비자 없이 미리 만들지 않는다.
- 값의 모양과 규칙은 `FolioDomain`에 두고, 앱은 그 값을 그리기만 한다.
- 축을 새로 만들면 이 표와 `docs/axes.md`에 적는다.

| 축 | 하나로 모으는 것 | 상태 |
| --- | --- | --- |
| 액션 `@Action` | 데이터를 바꾸는 모든 동작. 앱, CLI, MCP가 같은 선언을 쓴다 | 있음 |
| 읽기 `@Query` | 항목을 읽는 명령. CLI, `--json`, `folio run`, MCP 도구가 같은 선언에서 나온다 | 있음 |
| 표준 구조 `sources/domain/folder/` | 폴더와 파일 이름 | 있음 |
| 앱 링크 `AppLink` | 앱 안의 모든 대상을 가리키는 `folio://` 주소와 종류 표(`AppLink.Kind`). 모든 이동이 `\.openLink`로 간다 | 있음 |
| 화면 계약 `ScreenView` | 주소 하나를 그리는 화면과 세 폭(1440·720·390) 검사 | 있음 |
| 칸 배치 `PaneLayout` | 탭 하나의 칸과 접기 규칙, 회차 배치 기억, 이름 붙인 배치 | 있음(#62) |
| 제안 `ActionProposal`, `Proposal` | 승인하면 실행할 액션과 그 ID, 적용 기록, 충돌 사본 합치기, 승인 화면의 종류·묶음·표시 | 있음(Claude 패널, LMS 탭, 폴더 정리). 패널의 거절은 #515, 파일 분류와 정보 추출은 #90 |
| 파일 보기 렌더러 | 형식 판단(`MaterialFormat`)과 형식별 보기(`FileView`) | 있음 |
| 파일 분류 `FileRule` | 파일 이름으로 종류를 읽는 규칙 표와 과제 종류 표 | 있음 |
| 단축키 | 명령마다 한 번 등록하는 단축키 표 | #116 |
| 설정 항목 `SettingItem` | `settings.json`의 키, 모양, 범위, 기본값, 화면의 자리 | 있음 |
| 자동 완성 메뉴 `CompletionMenu` | 편집 보기의 모든 자동 완성 | 있음(Mac). iPad는 #31 |
| 노트 문법 `NoteSyntax`, 콜아웃 종류 `CalloutTable` | 노트의 확장 문법과 콜아웃 종류 | 있음 |
| 항목 메뉴 `ItemCommand` | 항목 종류마다 하나인 메뉴 | 있음(#403) |
| 라이브 시계 `LiveClock` | 화면이 그리는 지금 시각 | 있음 |
| 빠른 추가 인식기 `QuickAdd` | 빠른 추가 한 줄을 읽는 법 | 있음 |

### 화면: 모델과 뷰

화면 하나는 `app/features/<영역>/`의 `<화면>-view.swift`와 `<화면>-model.swift`로 나눈다. 다른 파일에서 쓰는 큰 조각(행, 카드, 시트)은 타입마다 `features/<영역>/<조각>.swift`로 빼고, 그 화면 안에서만 쓰는 조각은 `private`으로 둔다. 본보기는 `features/grades/catalog/`다.

- **모델** `<화면>Model`: `@MainActor @Observable final class`이고 `init(workspace:, 대상 ID)`로 만든다. 화면의 상태(검색어, 고른 항목, 지우려는 항목)를 들고, 뷰가 바로 그릴 값(묶고, 거르고, 세고, 문구로 만든 값)과 동작을 내놓는다. 동작은 `workspace.run(액션)`을 부른다.
- **뷰**: 모델을 읽고 배치만 한다. `body`에서 묶기, 거르기, 세기를 하지 않고 `workspace`를 직접 부르지 않는다(`view-body-logic`, `view-workspace-call`). 뷰는 `@State private var model`을 `init(workspace:)`에서 만들고, `@State`는 시트, 마우스 올림, 포커스 같은 화면 상태에만 쓴다.
- **Workspace**: 폴더 읽기, 파일 감시, 액션 실행, `can`/`refusal`/`confirmation`만 맡는다. 한 기능만 쓰는 함수는 그 기능의 모델에 둔다. 한 기능이 다른 기능의 모델을 쓰지 않는다(`app-direction`).
- 파생 계산 중 데이터의 규칙(주차 묶기, 빠진 복습 노트 판단)은 `FolioDomain`에 두고 `swift test`로 검사한다. 화면에만 필요한 계산은 모델에 둔다.
- `course.json` 밖의 파일을 읽는 목록(노트, 퀴즈 카드)은 `workspace.notesRevision`과 `quizRevision`이 바뀔 때 다시 읽는다. 두 값은 `Workspace`가 액션 결과의 `changes`와 폴더 전체 다시 읽기로만 올린다. 화면이 직접 올리지 않으므로 어느 화면이나 Claude 패널, CLI로 써도 열린 목록에 나타난다.
- 열린 편집기(노트, 텍스트 파일)도 `notesRevision`이 바뀌면 디스크를 마지막으로 읽거나 쓴 내용과 비교한다. 저장하지 않은 변경이 없으면 본문과 메타를 다시 읽고, 있으면 덮어쓰지 않고 충돌로 묻는다. 메타는 처음 연 `NoteFile`이 아니라 지금의 `course.json`에서 읽는다.
- 다른 화면이나 항목으로 옮길 때는 `@Environment(\.openLink)`에 `AppLink`를 넘긴다. 화면이 목적지를 직접 고르거나 링크 여는 법을 따로 구현하지 않는다. 그래야 모든 이동이 창의 기록 하나에 들어간다. 화면은 창이 지금 가리키는 곳을 `\.place`로 받아 따라가고, 자기 안에서 연 것(파일, 단원, 노트)은 다시 링크로 알린다.
- **화면 계약**: 화면은 앱 링크 하나를 그린다. 링크에서 화면을 고르는 곳은 `app/window/screen.swift`의 `Screen(entry)` 하나다. 창의 본문, 칸, iPhone이 모두 이것으로 그린다.
    - 화면은 `init(workspace:)`와 링크의 ID만 받는다. 링크가 가리키는 안쪽(과목의 구역, 연 파일·단원·노트, 사람)은 `\.place`로 읽는다. 다른 화면은 `\.openLink`로 열고, 여는 클로저를 인자로 받지 않는다.
    - 화면은 창 틀에 기대지 않는다. 툴바에 항목을 넣지 않고(`screen-toolbar`. 도구는 `PageBar`, 보조 패널은 FAB), 창 크기가 아니라 자기 폭으로 배치를 고르며, 위치 표시에는 `.crumb`로 단계를 알리기만 한다.
    - 화면은 받은 폭 안에 그린다. 옆으로 넘치거나 행을 자르지 않고 접는다. 나란한 블록은 `Fold(wideFrom:)`, 행은 `FormRow`와 `FoldingRow`로 접는다.
    - 목록 열과 본문이 나란한 화면은 `ColumnSplit`으로 둔다. 본문이 `ColumnSplit.pageRoom`보다 좁아지거나 사용자가 손으로 접으면 열은 열 버튼 뒤로 접히고, 버튼을 누르면 같은 열이 본문 위에 유리 판으로 뜬다. 칸이 하나든 여럿이든 같다. 항목이 늘어나는 목록(사람, 퀴즈 범위, 과목의 노트 목록)은 자리가 없고 본문에 보일 것이 없으면 목록이 본문이 된다(`.list(showingPage:)`). 링크를 가진 고르기는 `\.openLink`로 가서 창의 기록에 남고, 주소가 그대로인 고르기는 `ColumnPick`으로 떠 있는 열을 닫는다. 탭 없는 `folio://settings`는 `Workspace.entry(for:)`가 마지막으로 고른 탭으로 채우므로 기록의 모든 칸이 탭을 가진다.
    - 화면 안의 상태(목록 열 펼치기, 빠른 추가에 넣은 줄, 쪽 열의 범위, 퀴즈 시작, 펼친 학기)를 바깥에서 정할 때는 `ScreenRequest`를 `\.screenRequests`로 내려 준다. 화면은 아는 요청에만 답하고 누가 요청했는지 보지 않는다. 화면 파일에 `SnapshotDriver`를 읽는 `#if DEBUG` 분기를 두지 않는다.
    - `ScreenFitTests`(`mise run test-app`)가 모든 화면을 세 폭으로 그려 넘치는지 본다. `ColumnSplit`의 본문은 평소 0까지 줄어들어 넘친 것을 자르므로, 검사는 `\.revealsOverflow`로 이를 풀어 본다. 바뀐 화면은 `FOLIO_RENDER_SIZES=1440x900,720,390 mise run render`로 그려 눈으로 본다.
- 모델 테스트는 `tests/unit/app/models/<화면>-model-tests.swift`(과목 화면은 `models/course/`)에 Swift Testing으로 쓰고, `fixtureWorkspace()`로 가짜 GIST 폴더를 연다.
- `mise run check-code`(`mise run test`에 포함)가 이 절과 아래 규칙 중 구문 트리로 보이는 것을 잡는다. 규칙 이름은 `sources/tools/lint`에 있고 규칙마다 단위 테스트가 있다(`tests/unit/tools/lint`). 규칙이 보는 경로는 `repo-path.swift`의 표 하나에 있다. 검사가 생기기 전부터 있던 곳은 `.folio-lint-baseline.txt`에 있어 통과하고 새로 생긴 곳은 실패한다. 고친 곳이 목록에 남아 있어도 실패하므로 `mise run check-code -- --update`로 목록을 줄인다. 새 위반을 목록에 넣어 통과시키지 않는다. 처음부터 위반이 없던 규칙(디자인 값, `local-folders`, `one-type-per-file`, `doc-comment`)은 기준선이 없어 `--update`로도 통과하지 않는다.

### 문자열 키

화면과 CLI에 보이는 문구는 코드에 적지 않고 문자열 카탈로그에 키로 넣는다. 카탈로그는 문구를 내놓는 모듈마다 하나다(`app/resources`, `sources/domain`, `sources/actions`, `sources/cli`). 카탈로그에 직접 넣은 키(`extractionState: manual`)마다 Swift 심볼이 생기므로 키를 잘못 쓰면 컴파일이 실패한다.

```swift
// "sessions.add" = "회차 추가",  "sessions.count" = "회차 %lld개"
Button(.sessionsAdd) { ... }
Text(.sessionsCount(file.sessions.count))
PageHeader(title: String(localized: .sessionsAdd))   // String을 받는 API
```

- 키 이름은 `<기능>.<무엇>`이고 소문자, 점, 단어 안의 `-`만 쓴다. 여러 화면이 같은 뜻으로 쓰는 문구는 `common.*`에 둔다.
- 인자는 `Int`면 `%lld`, 그 밖은 코드에서 문자열로 바꿔 `%@`로 넘긴다. 연도는 자릿수 구분 기호가 붙지 않게 `String(year)`로 넘긴다. 인자가 여럿이면 `%1$@ %2$lld`처럼 쓴다. 문자 `%`는 인자가 있는 키에서만 `%%`로 쓴다.
- 파일에 쓰는 값이나 사용자 입력과 비교하는 값처럼 데이터인 문자열은 코드에 두고, 그 줄 끝에 `// strings: data, <이유>`를 단다(`ui-string`). 블록이나 배열을 여는 줄에 달면 그 안 전체가 빠진다. `#if DEBUG`, `#Preview`, `debug-*.swift`, `*-snapshots.swift`는 검사하지 않는다.
- `@Action`의 `confirm:`과 `done:` 문구는 선언에 그대로 둔다. 매크로가 그 안의 `{필드}`를 컴파일할 때 검사하기 때문이다.

### 이름과 주석

- 파일과 폴더 이름은 소문자 케밥 케이스이고 파일 이름은 그 파일의 타입 이름에서 온다(`kebab-names`). 약어는 한 낱말로 읽고(`LMSPages`: `lms-pages`), `TeX`, `LaTeX`, `SyncTeX`, `AsciiMath`는 낱말 하나다. 도구가 이름을 정하는 파일(`Package.swift`, `Localizable.xcstrings`, `FolioTectonic.xcframework`와 `libFolioTectonic.a`)은 예외다.
- 주석은 정말 필요한 것만 남긴다. 남는 것은 다르게 짜면 깨지는 이유, 바깥 제약(OS 버그, 도구의 한계, 따라야 하는 파일 형식), 숫자의 근거 정도다. 이름이나 코드에서 읽히는 것, 이슈 번호만 남긴 이력은 적지 않는다(`restating-comment`).
- 주석은 `//`로, 한국어로 쓴다. 말투는 `dadeum` 스킬을 따른다(빠진 성분 없이 완결된 문장, 비유 없이, 기술 용어와 식별자는 원어 그대로).
- 문서 주석(`///`, `/** */`)은 `@Action` 타입에 바로 선언한 필드에만 쓴다(`doc-comment`). 매크로가 읽어 CLI 도움말로 만드는 데이터다. 생성 파일(`generated` 폴더)의 글은 원본에서 고친다.

### 단일 출처(SSOT)

- 폴더와 파일 이름 규칙은 `FolioDomain`의 `sources/domain/folder/`(`StandardLayout`, `Term`, `SemesterFolder`, `CourseFolder`, `AssignmentKind`)에서만 정의한다. 다른 곳에서 `"Lectures"`, `".folio"` 같은 문자열을 다시 쓰지 않는다(`layout-name`).
- 사용자가 바꿀 수 있는 값(하루 경계, 복습 간격, 알림 시점, 학점 규칙)은 코드 상수가 아니라 `settings.json`과 `transcript.json`에서 읽는다. 기본값은 Domain의 한 곳에서만 정의한다.
- 빌드와 테스트 명령은 mise 작업(`mise.toml`과 `.mise/tasks`)으로만 정의한다. 규칙이 든 일(버전, 릴리스 본문)은 셸이 아니라 Swift 도구 `folio-dev`에 둔다. 문서는 `mise run <작업>`을 가리킨다.
- Xcode 프로젝트는 `project.yml`에서 생성한다. `Folio.xcodeproj`는 커밋하지 않고 직접 고치지 않는다.
- 버전은 `v<X.Y.Z>` 태그에서만 정한다. patch는 패치 노트가 있는 PR이 머지되면 `release.yml`이 올리고, minor는 기능 묶음이 끝나 사용자가 승인하면 올린다. 커밋한 `FolioVersion.marketing`은 자리표시값이고 릴리스 빌드만 태그의 버전을 써넣는다(`docs/release.md`).

## 데이터 원칙

이 원칙들은 사용자의 실제 학업 자료를 다루기 때문에 반드시 지킵니다.

1. **파일이 원본이다.** 모든 상태는 GIST 폴더 안의 파일(`course.json`, `transcript.json`, 마크다운 노트, `.drawing`, 기기별 `.jsonl` 로그)에 저장한다. 앱 내부의 SQLite는 검색과 집계를 위한 캐시이며, 지워도 파일에서 다시 만들 수 있어야 한다.
2. **폴더 구조는 Folio가 정한다.** GIST 폴더는 아래 "폴더 구조와 이름 규칙"을 따른다. 과목 폴더의 하위 폴더는 `Syllabus`, `Lectures`, `Exercises`, `Textbooks`, `Inherited`, `Assignments/<과제>`, `Exams/<시험>`, `Study`, `Notes`, `Ink`, `Recordings`, `Archive`, `.folio`만 쓴다. 과제와 시험은 하나당 폴더 하나이고, 시험 폴더는 데이터 모델의 Exam과 1:1이다. 과제 폴더 안의 파일 이름은 바꾸지 않는다. 예전 학기의 다양한 폴더 이름을 허용하는 분기 코드를 만들지 않고, 기존 폴더는 일회성 정리 도구(`cleanup`)로 표준 구조에 맞춘다.
3. **삭제와 이동은 사용자 승인 후에만 한다.** 파일 이동, 이름 변경, 삭제는 사용자가 확인 화면에서 승인한 경우에만 수행한다. 수행한 이동과 이름 변경은 `.folio/moves.jsonl`에 기록해 되돌릴 수 있게 한다. Claude가 제안한 분류와 위치도 제안으로만 저장한다.
4. **쓰기는 원자적으로 한다.** 파일 쓰기는 `NSFileCoordinator`를 거치고, 임시 파일에 쓴 뒤 교체한다. iCloud 충돌 사본은 `NSFileVersion`으로 감지한다.
5. **로그는 추가만 한다.** `.folio/logs/<기기 ID>.jsonl`은 각 기기가 자기 파일에만 줄을 추가한다. 기존 줄을 고치거나 지우지 않는다.
6. **스키마에 버전을 둔다.** 모든 JSON 파일 최상위에 `schemaVersion`을 두고, 버전이 바뀌면 마이그레이션 함수를 추가한다. 모르는 필드는 읽을 때 버리지 않고 보존한다.
7. **식별은 ID로 한다.** 파일, 노트, 엔티티는 UUID로 식별한다. 경로와 제목은 표시용이며 바뀔 수 있다.

### 폴더 구조와 이름 규칙

코드의 단일 출처는 `sources/domain/folder/`이고, 이 절은 그 규칙을 사람이 읽는 형태로 적는다. 과목 폴더는 출처로만 나뉜다. 받은 것(`Syllabus`, `Lectures`, `Exercises`, `Textbooks`, `Inherited`), 평가 기록(`Assignments/<과제>`, `Exams/<시험>`), 내가 만든 것(`Study`, `Notes`, `Ink`, `Recordings`, `Archive`)이다. 어느 시험이나 단원을 위한 파일인지는 폴더가 아니라 `course.json`의 연결(ID)로 표시한다.

```text
Me/GIST/
  .folio/
    transcript.json            # 학기 목록(인정학기와 그 출처 포함), 학점 규칙, 목표
    catalog.json               # 강의 코드, 세부 분류, 평어, 교수 정보
    settings.json              # 전역 설정
  2026-3/
    _Admin/                    # 학기 전체의 시험 시간표, 강의실 배정, 수강신청 서류, 성적증명서
    EC4207 그래프 이론/
      Syllabus/                # 강의계획서, OT 자료, 수업 운영 안내
      Lectures/                # 강의 슬라이드. 05_Matchings.pdf
      Exercises/               # 교수가 준 채점 없는 연습 문제만
      Textbooks/               # 교재, 참고서, 해설집
      Inherited/               # 선배와 이전 학기에서 받은 자료. 원래 이름 그대로, 출처별 하위 폴더는 있어도 된다
      Assignments/HW03/        # 과제 하나에 폴더 하나. 안의 파일은 원래 이름 유지
      Exams/Midterm/           # 이 시험의 기록만. 안내, 좌석표, 받은 시험지와 해설, 채점된 답안
      Study/                   # 직접 만든 파일. 문제집, 모의고사, 요약 PDF와 .tex 원본, 노트를 빌드한 PDF
      Notes/                   # Folio 노트(.md, .tex). 그림과 파일은 Notes/assets
      Ink/                     # PencilKit 필기 (.drawing)
      Recordings/              # 강의 녹음(.m4a)과 받아쓰기(.transcript.json)
      Archive/                 # 이전 필기
      .folio/                  # course.json, quizzes/, chats/, widgets/, moves.jsonl, logs/<기기 ID>.jsonl
  _Credited/
    영재고 AP/                 # 인정학기의 출처. 그 학기의 과목 폴더가 여기 들어간다
```

- GIST 폴더 최상위에는 학기 폴더, `_Credited`, `.folio`만 둔다. 학기 폴더는 `<연도>-<번호>`이고 번호 1은 봄, 2는 여름, 3은 가을, 4는 겨울학기다. 학기 폴더 안에는 `_Admin`과 과목 폴더만 둔다. 인정학기는 학기 폴더가 없고 과목 폴더를 `_Credited/<출처>`에 둔다. 출처는 `transcript.json`의 학기에 적고, 출처가 없는 인정학기에는 과목을 만들 수 없다.
- 과목 폴더는 `<대표 과목코드> <과목명>`이다. 원본은 `course.json`이고, 과목 편집에서 바꾸면 앱이 폴더 이름을 맞춘다(저장 전 새 이름을 보여 주는 것이 승인이며 `moves.jsonl`에 남긴다). 과목 폴더 최상위에는 파일을 두지 않는다. 모든 과목은 과목 폴더와 `course.json`을 가진다. 과목을 만들 때는 `.folio`만 만들고, 하위 폴더는 처음 필요할 때 만든다.
- `Lectures`의 파일은 `<주차 두 자리>_<제목>`이고, 한 주에 여러 개면 `05-1_`, `05-2_`로 나눈다.
- `Assignments/<과제>`는 종류 접두어와 두 자리 번호다(`AssignmentKind`, `settings.json`의 `assignmentKinds`로 추가). 안의 파일 이름은 바꾸지 않는다. 제출본은 교수가 정한 형식을 따라야 하기 때문이다. 문제, 제출본, 해설 같은 역할은 `course.json`에 기록한다. 코드 과제는 프로젝트를 이 폴더에 그대로 두고, `.git`이 있는 폴더는 이름도 바꾸지 않는다. 실험 매뉴얼은 그 실험 회차의 강의 자료로 `Lectures`에 둔다.
- `Exams/<시험>`은 Exam과 1:1이고 그 시험의 기록만 둔다. 폴더는 처음 파일이 들어갈 때 만들고, 시험을 추가해도 빈 폴더를 만들지 않는다. 폴더 이름은 새 시험의 제목으로 정하고(`Exams/중간고사`) `course.json`에 남겨, 제목을 바꿔도 그대로 둔다. 예전 시험의 `Midterm`, `Final`, `Quiz1`도 그대로 쓴다.
- `Inherited`에는 선배와 이전 학기에서 받은 자료를 종류와 상관없이 원래 이름으로 둔다. 족보 시험지인지는 이름이 아니라 `course.json`의 자료 종류(`pastExam`)로 표시하고, 시험에 쓸 자료는 그 시험에 연결한다. `Exams/Past`는 없앴다.
- `Study`에는 직접 만든 파일을 둔다. 어느 시험·단원용인지는 자료 연결로 표시하고, 시험 화면은 시험 폴더의 파일과 연결된 자료를 함께 센다. 어떤 자료가 회차, 단원, 시험에 딸리는지는 `CourseFile.routes(of:to:)` 하나가 정한다. 회차는 그 단원과 상위 단원의 자료를, 단원은 그 회차의 자료를 함께 본다. 단원으로 나눈 렉처는 자료 연결 없이도 그 쪽 구간(`lecturePages`)으로 단원과 그 회차에 딸리고, 화면은 이것을 직접 연결과 구분한다(`MaterialRoute.pages`).
- 회차, 회차 노트, 녹음의 이름은 `docs/sessions.md`, 노트 링크의 꼴은 `docs/notes.md`에 있다.
- 앱 밖의 파일은 복사해서 들여오고, 같은 이름이 있으면 ` 2`를 붙여 덮어쓰지 않는다.

## 실제 데이터 위치

- GIST 폴더: `~/Library/Mobile Documents/com~apple~CloudDocs/Me/GIST`
- 옵시디언 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain`. Folio는 이 볼트를 읽거나 쓰지 않고 `obsidian://` 링크로만 참조한다.
- 개발과 테스트 중에는 실제 GIST 폴더에 쓰지 않는다. 테스트는 `FolioFixtures`의 가짜 폴더를 임시 디렉터리에 써서 쓴다. 앱이나 CLI를 가짜 폴더로 돌릴 때는 `mise run fixture -- <폴더>`로 만든다.
- 실제 폴더를 대상으로 처음 실행하기 전에 사용자에게 알리고, 백업이 있는지 확인한다.
- 앱이 여는 폴더는 기기마다 기억한다(`Workspace.bookmarkKey`). 기억한 폴더가 없으면 첫 실행 화면이 뜨고, 기억한 폴더가 없어졌거나 iCloud에서 아직 내려받지 않았으면 그 폴더를 열지 않고 다시 연결하게 한다(`FolderProbe.availability`). 테스트, 미리보기, `FOLIO_GIST` 실행은 기억한 폴더를 바꾸지 않는다(`Workspace.remembersFolders`). 테스트 호스트가 앱 자신이라 `UserDefaults.standard`가 실제 앱의 것이기 때문이다.

## 테스트 기준

- `FolioFixtures`에는 가짜 GIST 폴더를 두 벌 둔다.
    - `Fixture.standard`: 표준 구조를 따르는 폴더. 일반 기능 테스트에 쓴다.
    - `Fixture.legacy`: 지금 실제 폴더처럼 정리되지 않은 폴더. 정리 도구 테스트에만 쓴다. 한국어 하위 폴더, 과목마다 다른 영어 하위 폴더, 과목 폴더 최상위의 학사 파일, `.git`이 있는 코드 과제, 같은 이름의 `.tex`와 PDF, 학업 외 폴더, 예전 정리 규칙이 남긴 모양을 담는다.
- 정리 도구는 `legacy`를 정리한 결과가 표준 구조를 만족하는지, `moves.jsonl`로 되돌리면 원래 상태와 같아지는지 테스트한다.
- 성적 계산 테스트에는 지어낸 등급과 손으로 계산한 기대값을 쓴다. 저장소가 공개라서 실제 성적과 GPA는 테스트, 픽스처, 문서에 넣지 않는다.
- 계산 로직에는 손으로 계산한 예시와 함께, 무작위 입력에서도 지켜져야 하는 성질을 `propertyCheck`로 검사한다. 예시가 정답을 고정하고 성질 테스트는 예시가 놓친 경계를 찾는다. 실패하면 출력된 시드를 `.fixedSeed(...)`로 붙여 다시 돌린다.
- 그래프 이론의 "Quiz 최저 점수 1회 제외"와 선형대수학의 "결석 6회면 최대 B0, 9회 이상이면 F"를 성적 규칙 테스트 사례로 넣는다.
- 하루 경계 테스트는 새벽 4시 경계를 기준으로 경계 직전과 직후를 모두 검사한다.
- 노트 보기의 회귀 검사와 기준 이미지 규칙은 `docs/notes.md`에 있다.
- 테스트, 미리보기, 화면 밖 렌더는 이 Mac의 `Application Support/Folio`(녹음 복구, Whisper 모델)를 쓰지 않는다. 그 폴더는 앱의 `LocalFolders`로만 얻고 패키지는 쓰지 않으며(`local-folders`), 테스트와 미리보기에서 얻으려 하면 실행이 멈춘다. 화면 모델 테스트는 `fixtureWorkspace()`, 미리보기와 렌더는 `Workspace.scenario`가 임시 폴더를 준다. `FOLIO_GIST`로 가짜 폴더를 연 앱 실행은 녹음 폴더를 그 GIST 폴더마다 따로 임시 폴더에 둔다.

## 빌드와 실행

도구 버전과 환경 변수는 `mise.toml`이 정한다. Xcode 툴체인은 전역 `xcode-select`를 바꾸지 않고 `DEVELOPER_DIR`로 이 저장소에서만 쓴다. 명령은 항상 `mise run <작업>`으로 실행하고, 작업 목록과 설명은 `mise tasks`가 원본이다. CLI 명령은 `folio help`(자연어로 찾기는 `folio help <하고 싶은 일>`)가 원본이다. 아래에는 작업 설명만으로 알기 어려운 규칙을 적는다.

- 모든 `xcodebuild` 작업은 체크아웃 안의 `.build/DerivedData`(`FOLIO_DERIVED_DATA`)에 빌드한다. 워크트리마다 몇 GB씩 남지 않고 워크트리를 지우면 함께 지워진다. 디버그 앱은 `.build/DerivedData/Build/Products/Debug/Folio.app`이다. `FolioMacros`는 로컬 패키지라 Xcode가 매크로 신뢰를 묻지 않고, 작업의 `-skipMacroValidation`은 명령줄 빌드가 멈추지 않게 하는 안전장치다.
- 커밋 전 검사(`lefthook.yml`)는 `mise run hooks`로 한 번 넣는다. 훅은 `.git/hooks`에 들어가고 워크트리가 이 폴더를 함께 쓰므로 세션 워크트리에서도 돈다.
- 포매팅은 `mise run format`이고 포매터를 부르는 곳은 mise 작업 `swift-format`(`.mise/tasks/swift-format`) 하나이고, lefthook과 `format`, `format-check`가 이것을 부른다. 한 줄에 여러 문장이나 선언을 쓰는 Folio의 문체를 바꾸는 규칙은 끄고, 그 이유는 `mise.toml`의 `format` 작업에 적었다. main에 올라온 브랜치를 다시 얹다가 모양만 다른 충돌이 나면 손으로 풀지 않고 한쪽을 고른 뒤 `mise run format`을 다시 돌린다.
- 생성 파일은 모두 `generated` 폴더에 두고 검사가 만든 내용과 그대로 비교하므로, swift-format과 SwiftLint가 그 폴더를 뺀다. `@Action` 선언이나 손 명령을 고치면 `mise run gen-cli`를 돌린다. 생성기는 링크한 액션 목록으로 명령을 쓰므로 목록을 고친 뒤 한 번 더 돈다.
- SwiftLint의 레이아웃 규칙은 포매터에 맡겨 끈다. `.swiftlint-baseline.json`은 고친 곳을 빼거나 옮긴 파일을 따라갈 때만 `mise run swiftlint-baseline`으로 다시 쓰고, 새 위반을 넣어 통과시키지 않는다.
- 거의 모든 파일을 건드리는 기계적 변경(옮기기, 포매터 판 올리기)을 머지하면 그 스쿼시 커밋 해시를 주석과 함께 `.git-blame-ignore-revs`에 더한다. 로컬에서는 `git config blame.ignoreRevsFile .git-blame-ignore-revs`를 한 번 실행한다.
- `test-app`은 테스트 중에 앱이 기억해 둔 GIST 폴더를 열지 않고, 창을 띄우거나 포커스를 가져가지 않는다. `FOLIO_TEST_PART=notes`는 노트 보기 검사만, `rest`는 나머지만 돌린다.
- iPad 테스트 타깃(`FolioTests`)은 Mac과 iPad를 함께 지원하고, iPad에서는 `tests/unit/app/ipad`만, Mac에서는 그 밖만 빌드한다(`project.yml`의 `destinationFilters`). 앱 타깃은 iPhone과 iPad를 함께 지원하므로 iPhone도 `build-ipad`로 확인한다.
- `test-a11y`는 화면과 키보드를 가져가고 앱의 UserDefaults를 설치한 Folio와 함께 쓰므로 사용 중인 Mac에서 돌리지 않는다(`docs/ci.md`).
- `render`는 창 없이 그리고 실제 GIST 폴더와 시계를 쓰지 않는다. 폭과 높이는 `FOLIO_RENDER_SIZES=1180,720,1440x900`(높이를 빼면 페이지 끝까지), 고르기는 `FOLIO_RENDER_SCREENS=today,course-`(이름 앞부분)와 `FOLIO_RENDER_SCENARIOS=busyDay`다. 리퀴드 글라스, 노트 보기와 `WKWebView`, 뷰 안에서 여는 시트, 창 틀은 그리지 못하니 창 스냅숏으로 본다. 화면 확인 방법은 `docs/design/screen-check.md`에 있다.
- `fixture`는 이미 있는 폴더에 쓰지 않는다. 상황(`busyDay` 등)은 회차와 마감이 채워진 폴더다. 다른 `.pdf`는 열리지 않는 자리표시자지만, `busyDay`와 `manyExams`의 그래프 이론 렉처(`05_Matchings.pdf`)는 단원으로 나눈 24쪽 PDF(`SampleLecture`)다.
- 앱을 설치할 때는 `install-release`로 커밋된 코드를 깨끗한 임시 워크트리에서 빌드한다(`docs/release.md`).
- 모든 CLI 쓰기 명령은 `--dry-run`으로 먼저 본다. GIST 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다.
- 에이전트 스킬의 원본은 `sources/cli/commands/skill.swift`다. 고친 뒤 `mise run cli -- skill > .claude/skills/folio/SKILL.md`로 사본을 맞춘다(테스트가 확인한다).
- `import notion`, `import notes`, `import exams`, `import units`, `import requirements`, `import handbook`이 읽는 파일은 실제 학업 데이터라 저장소에 넣지 않는다.
- 이름을 바꾸거나 옮기는 일회성 도구(`cleanup apply`, `note retitle`, `recording retitle`, `transcript move`)는 실제 GIST 폴더에 사용자 승인 뒤에만 돌린다. 출처가 불확실한 파일은 `cleanup`이 검토 표시로 두고 `--include-flagged` 없이는 옮기지 않는다.

작업을 끝냈다고 보고하기 전에 관련 테스트와 빌드가 통과하는지 확인한다.

## 이슈와 작업 순서

할 일은 GitHub 이슈로, 순서와 상태는 [Project](https://github.com/users/rhseung/projects/10)로 관리한다. 별도의 명세 문서는 두지 않는다.

- 기능 하나는 이슈 하나다. 이슈 제목은 앱 기능 목록에서 부를 법한 기능 이름으로 짓는다. 세부 작업은 따로 이슈로 만들지 않고 본문 체크리스트로 둔다. 모델, 화면, CLI 같은 층별로 이슈를 나누지 않는다.
- 이슈마다 영역 라벨(`area/*`) 하나를 붙이고 그 영역의 상위 이슈(`epic` 라벨) 아래 하위 이슈로 둔다. 상위 이슈 본문에는 하위 기능 목록을 적는다. 상위 이슈의 진행 순서는 Project의 `Order` 필드로 둔다.
- 모든 이슈에 `Priority`(P0~P3), `Size`(XS~XL), `Status`(Backlog, Ready, In progress, Blocked, Done)를 정한다. Ready는 막는 이슈가 모두 닫힌 상태이고, 열린 이슈에 막힌 이슈는 Blocked로 둔다.
- 결정과 조사는 이슈로 두지 않는다. 그 결정이 영향을 주는 기능 이슈 본문의 `정한 것` / `정할 것` 절에 적는다. `정할 것`에 남은 부분은 사용자가 답할 때까지 구현하지 않는다. 사용자와 새로 정하면 `정한 것`으로 옮긴다.
- 지금 하지 않기로 미룬 기능에는 `later` 라벨을 붙인다(P3, Backlog). 기능의 일부만 미룰 때는 그 체크리스트 항목에 "(나중에)"를 붙인다.
- 사용자가 지정한 일을 먼저 한다. 그 밖의 다음 할 일은 Ready 중 상위 이슈의 `Order`가 앞선 것, 같은 상위 이슈 안에서는 `Priority`가 높은 것이다. P0는 순서와 상관없이 먼저 한다. `main`의 CI가 실패하면 P0로 보고 다른 일보다 먼저 고친다.
- 상태는 손으로 옮긴다(Project 자동화는 하위 이슈 추가만 켜 있다). 시작하면 In progress, PR 본문에 `Closes #번호`를 적고, 닫히면 Done으로 옮긴다. 닫힌 이슈에 막혀 있던 이슈는 남은 막힘이 없으면 Ready로 옮긴다. 일부만 끝냈으면 닫지 않고, 끝낸 항목을 체크하고 남은 일을 체크리스트에 적는다. 한 이슈가 테스트까지 끝나면 커밋하고 다음으로 넘어간다.
- PR은 `main` 룰셋의 승인 1개와 필수 검사(`packages`, `mac app`, `ipad app`)를 모두 채워야 머지된다. 승인은 리뷰 봇이 하고(Dependabot PR 포함), 문서만 바뀐 PR은 Actions가 한다(`docs/ci.md`). PR은 스쿼시로만 머지되므로 PR 제목을 커밋 규칙대로 짓는다. 자동 머지는 커밋 제목(`<PR 제목> (#번호)`)과 본문(PR 본문의 `## 패치 노트` 절, 절이 없으면 빈 본문)을 정해서 건다. 정하지 않으면 GitHub가 PR 본문 전체를 커밋 본문으로 쓰기 때문이다. 관리자 권한(`--admin`)으로 룰셋을 우회하지 않는다.
- 사용자가 이슈 없이 시킨 일은 바로 하고, 남은 범위나 새로 정한 동작은 해당 이슈에 적거나 새 이슈로 만든다.

### PR 전 점검

리뷰 봇이 여러 PR에서 거듭 지적한 실수다. PR을 열기 전에 바뀐 코드에 대해 하나씩 확인한다.

- 화면을 바꾼 PR은 눈으로 확인한 증거를 본문에 붙인다(`docs/design/screen-check.md`). 리뷰 봇은 코드만 읽으므로 화면의 고장은 이 확인으로만 잡힌다.
    - 그림은 main에 커밋하지 않고 orphan 브랜치 `pr-assets`의 `<이슈>/`에 커밋해 올린다(없으면 `git switch --orphan pr-assets`로 만들고, 다른 체크아웃을 건드리지 않게 `git worktree add`로 따로 꺼낸다). 본문에는 `<img src="https://raw.githubusercontent.com/rhseung/folio/<커밋>/<이슈>/…" width="…">`처럼 커밋 해시로 가리켜 바로 보이게 넣는다. 디자인이 바뀌면 이전과 이후를 나란히 두고 라이트·다크와 바뀐 폭을 함께 보이며, 그림마다 무엇을 보면 되는지 한 줄을 붙인다.
- 무엇을 보여 줄지, 언제 막을지, 날짜와 개수를 어떻게 셀지 같은 규칙을 뷰나 모델에 다시 적지 않았는지 본다. 규칙은 `FolioDomain`에 두고 `swift test`로 검사한다.
- `#if os(macOS)`나 `#if os(iOS)` 안에 넣은 기능에 다른 플랫폼 쪽(`#else`)이 있는지 본다. 없다면 그 플랫폼에 필요 없는 이유가 분명해야 한다. `mise run build-ipad`도 돌린다.
- 더하거나 바꾼 화면 요소를 포인터와 터치 둘 다로 쓸 수 있는지 본다. 마우스 올림, 도움말, 두 번 클릭, 수식 키 클릭, 오른쪽 클릭, 키보드만으로 되는 일이 없고, 터치 표적이 44pt 이상이어야 한다(`docs/design/input.md`).
- 날짜가 공부일(`Settings.studyDay`, 하루 경계 새벽 4시)인지 달력 날짜인지 구분한다. 오늘 할 일, 마감까지 남은 날, 복습 날짜는 공부일로 센다. 경계 직전과 직후를 테스트한다.
- 테스트와 미리보기가 실제 `Application Support` 폴더나 GIST 폴더를 읽거나 쓰지 않는지 본다.
- 사용자에게 보이는 변화가 있는 PR은 본문에 `## 패치 노트` 절을 둔다. 줄마다 `- feat: …`, `- fix: …`, `- change: …` 중 하나로 쓰고(종류는 영어 그대로), 그 자리나 설정 탭이 있으면 끝에 `(folio://today)`, `(folio://settings/class)`처럼 링크를 붙인다. 앱의 새 기능 화면과 업데이트 뒤 시트가 이 줄을 종류 순으로 칩과 함께 보여 주므로 사용자 말로 짧게 쓴다(개발 용어, PR 번호, 파일 이름 없이). 링크는 앱의 자리와 설정 탭만 쓰고, 노트나 과목처럼 사람마다 다른 항목은 가리키지 않는다. `feat`가 든 버전만 업데이트 뒤 시트를 띄우므로 고침을 `feat`로 올려 적지 않는다. 보이는 변화가 없는 PR(CI, 테스트, 문서, 리팩터링)은 절을 쓰지 않는다. 머지 뒤에 고쳐도 릴리스 전이면 반영된다.
- 동작이나 규칙이 바뀌었으면 이 파일, `docs/`의 해당 문서, 해당 이슈 본문을 같은 PR에서 고친다.

### 새 이슈

- 만들기 전에 기존 이슈(닫힌 것 포함)에서 같은 일을 찾는다.
    - 열린 이슈와 같은 일이면 만들지 않는다. 발전시킨 것이면 그 이슈 본문을 고치거나 새 내용과 합쳐 하나로 만든다. 합칠 때는 닫는 쪽의 범위를 남는 쪽 체크리스트로, 라벨, 상위 이슈, blocked-by 관계도 남는 쪽으로 옮긴다. 닫는 쪽에는 "→ #N로 합침" 댓글을 달고 not planned로 닫은 뒤 상위 이슈의 하위 이슈 목록에서 뺀다.
    - 끝나서 닫힌 이슈와 같은 일이면 다시 열지 않고, 고장이나 보완을 새 이슈로 만들어 원래 이슈 번호를 적는다. 하지 않기로 닫힌 이슈는 다시 열기 전에 사용자에게 묻는다.
- 맞는 상위 이슈가 있으면 그 하위 이슈로 넣는다. 맞는 것이 없을 때, 여러 이슈로 나뉠 규모면 상위 이슈(`epic`, 새 `area/*` 라벨)를 새로 만들고 `Order` 자리를 사용자에게 제안한다. 이슈 하나로 끝날 일이면 가장 가까운 상위 이슈 아래에 둔다. 하위 이슈가 하나뿐인 상위 이슈는 만들지 않는다.
- 기대거나 막는 이슈와는 blocked-by 관계를 건다. 아직 없는 축에 기대는 기능은 그 축 이슈에 막히게 걸거나 축과 함께 만든다. 화면마다 임시로 구현하지 않는다. 본문에서도 관련 이슈 번호를 적는다.
- 예시 하나가 아니라 그 기능이 다뤄야 할 범위를 적고, 같은 일을 여러 이슈로 쪼개지 않는다. 기존 기능에 딸린 일이면 그 기능 이슈의 체크리스트에 더한다.
- 새로 생긴 결정이나 조사는 이슈로 만들지 않고 영향을 받는 기능 이슈의 `정할 것`에 적는다.

## UI

- 화면을 만들거나 고치기 전에 `docs/DESIGN.md`와 그 화면 영역의 `docs/design/` 문서를 읽는다.
- 디자인은 시안 C(밝은 종이 질감, 사이드바·과목 열·본문의 3단)에 리퀴드 글라스를 더한 방향이다. Mac 창은 시안 D처럼 반투명 창 재질 위에 사이드바와 툴바가 평평하게 놓이고 본문이 둥근 패널로 들어간다. 디자인 시스템과 시안 캔버스의 링크는 `docs/DESIGN.md`에 있다. 새 시안은 그 캔버스의 영역 페이지에 그리고 따로 Artifact를 만들지 않는다.
- 색, 간격, 모서리, 글꼴, 투명도, 그림자, 움직임, 크기는 `app/design/tokens/theme.swift`의 토큰만 쓴다. 라이트와 다크 값을 함께 둔다. 공용 구성 요소는 `app/design/`의 네 층(`tokens/`, `atoms/`, `components/`, `structures/`)에 있다. 기능 화면은 시스템 컨트롤과 버튼 스타일을 직접 쓰지 않고 원자를 쓰며, 기능 안에 `ButtonStyle`을 선언하지 않는다(`design-control`). 화면 코드의 디자인 값은 `design-*` 규칙이 잡는다.
- 구성 요소와 인자의 이름은 널리 쓰는 UI 라이브러리의 이름을 따른다. Apple(SwiftUI, HIG)을 먼저 보고, 없으면 Radix, shadcn/ui, MUI에서 흔한 이름을 쓰며, SwiftUI 타입과 겹치는 이름은 피한다. 같은 뜻의 인자는 모든 구성 요소에서 같은 이름이다.
- 리퀴드 글라스는 창 틀(사이드바, 툴바)과 떠 있는 요소(빠른 추가, 팝오버, Claude 패널)에만 쓰고 본문은 종이 색으로 둔다(`docs/design/window.md`).
- 과목 강조색은 `course.json`의 `color`(프리셋 이름)를 `CourseAccent`로 읽고, 비어 있으면 학기 안 순서로 프리셋을 고른다(무채색 `graphite`는 고르지 않는다). 예전에 고른 `#RRGGBB`는 파일을 바꾸지 않고 가장 가까운 프리셋으로 읽는다. 색은 프리셋 견본에서만 고른다. 과목 화면은 `\.accent` 환경값으로 색을 주입받는다(`course-accent`). 프리셋 이름과 고르는 순서는 `FolioDomain`의 `CourseColor`, 색 값은 `theme.swift`에 있다.

## 미결정 사항

미결정 사항은 해당 기능 이슈의 `정할 것` 절에 있다. 정해지기 전까지 지킬 것:

- 학업 외 폴더와 `2026-2`의 경진대회 자료(#106): 정리 도구는 이 항목을 건드리지 않는다.
- GIST 학칙의 재수강 처리, 졸업 평점 산정, 우등 졸업 기준(#123): 계산 규칙은 설정값으로 두고 하드코딩하지 않는다.
