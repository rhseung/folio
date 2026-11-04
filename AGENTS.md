# Folio

과목을 중심으로 강의 자료, 노트, 손필기, 복습, 퀴즈, 과제, 성적을 관리하는 macOS와 iPadOS용 네이티브 앱입니다. 무엇을 만들지와 남은 일은 GitHub 이슈와 [Project](https://github.com/users/rhseung/projects/10)에 있습니다. 이 파일에는 어떻게 만들지에 대한 규칙을 적습니다. 작업을 시작하기 전에 해당 이슈와 그 상위 이슈를 먼저 읽습니다.

## 소통 규칙

- 사용자와는 한국어로 대화한다. 영어로 답하지 않는다.
- 코드의 식별자, 주석, 커밋 메시지는 영어로 쓴다.
- 앱의 UI 문자열은 한국어로 쓰고 String Catalog(`Localizable.xcstrings`)에 키로 둔다. 아래 "문자열 키" 절을 따른다.
- 이슈와 다르게 구현해야 할 이유가 생기면 구현하기 전에 사용자에게 묻는다. 이슈에 없는 기능을 임의로 추가하지 않는다. 사용자와 새로 정한 동작은 그 이슈 본문에 적는다.

## 기술 기준

- 최소 지원 버전은 macOS 26, iPadOS 26이다.
- Swift 6 언어 모드를 쓰고 strict concurrency 검사를 켠다.
- UI는 SwiftUI로 만든다. AppKit과 UIKit은 SwiftUI로 할 수 없는 부분에만 쓴다. 예를 들어 PencilKit 캔버스와 PDFKit 뷰가 여기에 해당한다.
- 직접 구현보다 잘 관리되는 라이브러리를 먼저 쓴다. 표준 라이브러리와 Apple 프레임워크로 되지 않는 일이면, 직접 짜기 전에 널리 쓰이고 유지되는 Swift 패키지가 있는지 찾는다. 라이브러리가 데이터 원칙을 어기는 경우(예: 노트 frontmatter의 원문을 보존하지 못하는 YAML 파서)에만 직접 구현하고, 그 이유를 코드 주석에 남긴다.
- 외부 의존성은 Swift Package Manager로만 추가한다. 새 의존성은 넣은 뒤 사용자에게 무엇을 왜 넣었는지 알리고, 커밋 메시지에도 남긴다. 예외는 수식 변환과 코드 하이라이팅, Claude 패널에 쓰는 웹 번들(`web/`)로, npm 패키지를 정확한 버전으로 고정하고 `mise run build-web`으로 `app/resources/web/`에 묶는다. 묶은 결과는 커밋해서 앱 빌드에 node가 필요 없게 한다.

## 프로젝트 구조

플랫폼과 무관한 로직은 Swift 패키지로 분리해서 `swift test`로 Xcode 없이 테스트할 수 있게 합니다.

```text
folio/
  AGENTS.md
  docs/
    DESIGN.md         # 디자인 시스템: 원칙, 토큰과 구성 요소의 쓰임, 패턴
  packages/
    folio-core/       # 모델, 저장소, 파일 추적, 성적과 GPA 계산, 복습 스케줄러. UI 코드 없음
    folio-markdown/   # 마크다운 파서와 확장 문법(콜아웃, 위키링크, 블록 참조, cb-table, cb-widget)
    folio-ai/         # Claude 연동 계층. 프로바이더 추상화, 맥락 구성, 작업별 요청과 응답 스키마
  app/                # 멀티플랫폼 앱 타깃(macOS, iPadOS)
  app-tests/          # 화면 모델 테스트(`mise run test-app`)
  web/                # AsciiMath 변환과 코드 하이라이팅(노트 보기가 JavaScriptCore로 부른다), Claude 패널의 수식(KaTeX)과 스타일. 번들은 app/resources/web
```

- `FolioCore`는 SwiftUI를 import하지 않는다.
- 계산 로직(환산 점수, GPA, 복습 간격, 우선순위)은 순수 함수로 만들고 단위 테스트를 붙인다.
- Claude 호출은 `FolioAI`의 프로토콜 뒤에 둔다. 테스트에서는 가짜 프로바이더를 쓴다.

### 레이어

의존은 아래 방향으로만 흐른다. 거꾸로 import하지 않는다. 모듈 경계로 나눴으므로 어기면 컴파일이 실패한다.

```text
App (SwiftUI), FolioCLI  ->  FolioActions  ->  FolioAI, FolioStorage  ->  FolioDomain
App (SwiftUI), FolioCLI  ->  FolioIndex  ->  FolioStorage   (검색 색인)
FolioStorage, FolioActions, App  ->  FolioMarkdown   (노트 frontmatter와 렌더링)
FolioActions  ..>  FolioMacros   (@Action 매크로. 컴파일 때만 쓰고 앱에 링크되지 않는다)
FolioGen  ->  FolioActions   (생성한 CLI 명령을 folio-cli/generated에 쓴다)
```

| 모듈 | 위치 | 맡는 일 | 하지 않는 일 |
| --- | --- | --- | --- |
| `FolioDomain` | `packages/folio-core` | 엔티티, 값 타입, 표준 구조 규칙, 성적·GPA·복습 계산. 디스크에서 읽은 내용은 `FolderTree` 같은 값으로 받는다 | 파일 입출력(`FileManager`, `NSFileCoordinator`), UI, 네트워크 |
| `FolioStorage` | `packages/folio-core` | GIST 폴더 읽기와 쓰기, JSON 스키마 버전과 마이그레이션, 원자적 쓰기, 기기별 로그, 파일 추적 | 규칙 판단. 판단은 Domain에 맡긴다 |
| `FolioMarkdown` | `packages/folio-markdown` | 마크다운 파서와 확장 문법, frontmatter, HTML 렌더러. `swift-markdown` 기반 | 다른 Folio 모듈에 의존 |
| `FolioAI` | `packages/folio-ai` | Claude API 호출(Swift SDK가 없어 문서화된 HTTP 형식 그대로), 작업별 모델과 effort 표, 맥락 구성, 구조화된 응답 스키마, 사용량과 비용 | 파일 쓰기. 결과는 제안으로만 돌려준다 |
| `FolioActions` | `packages/folio-core` | 데이터를 바꾸는 모든 동작. Domain의 변환과 Storage의 쓰기, 폴더 생성, 로그를 한 액션으로 묶는다. 액션 목록의 단일 출처 | UI, 출력 형식. 앱과 CLI가 같은 구현을 부른다 |
| `FolioIndex` | `packages/folio-core` | 기기별 로컬 SQLite 검색 색인(GRDB, FTS5 trigram). 바뀐 과목만 다시 읽고 PDF 본문을 뽑아 둔다. 캐시 폴더에 두며 지워도 다시 만든다 | GIST 폴더에 쓰기. 순위와 발췌는 Domain의 `SearchIndex`에 맡긴다 |
| `FolioCLI` | `packages/folio-core` | 터미널 도구 `folio`의 명령 라이브러리. 실행 파일은 진입점만 있는 `FolioCommand`다(실행 타깃의 테스트 빌드에는 카탈로그 심볼이 생기지 않아서다). 모든 액션을 `<대상> <동작>` 명령으로 열고, 사람용 출력과 `--json` 출력을 만든다 | 액션 로직. 명령은 인자를 해석해 `FolioActions`를 부르고 결과를 그리기만 한다 |
| `FolioMacros` | `packages/folio-core` | `@Action`과 필드 표시(`@Arg`, `@New`, `@Off`, `@Hidden`). 선언에서 입력 형식, init, 코딩, `spec`을 만들고 실수(맨 `UUID`, 없는 `{필드}`, 확인 문구 없는 삭제)를 컴파일 오류로 막는다 | 실행 코드. 앱과 CLI에 링크되지 않는다 |
| `FolioGen` | `packages/folio-core` | `@Action` 액션의 `spec`에서 `folio-cli/generated/commands.swift`를 만든다. 결과는 커밋한다 | FolioCLI에 의존. 생성 파일이 깨져도 다시 만들 수 있게 한다 |
| `FolioFixtures` | `packages/folio-core` | 테스트와 개발 실행에 쓰는 가짜 GIST 폴더. 파일을 코드에 두고 쓸 때 디스크에 펼친다. 공개 저장소에 과목 파일 폴더를 두지 않기 위해서다. 화면 확인용 상황(`Scenario`)은 표준 폴더에 고정된 시각 기준으로 액션을 돌려 만든다 | CLI에 링크되지 않는다. 앱에서는 `#if DEBUG`의 `Workspace.scenario`(미리보기와 화면 밖 렌더)만 쓴다 |
| App | `app/` | 화면. `app/`(진입점과 탐색), `design/`(디자인 토큰과 공용 구성 요소), `features/<화면>/`, `platform/`(PencilKit, PDFKit, WKWebView 연결과 `note-text/`의 TextKit 2 노트 보기), `resources/` | 파일 시스템 직접 접근과 `course.json` 값의 직접 변경. 반드시 `FolioActions`를 거친다 |

- 앱에 새 데이터 조작을 넣을 때는 `FolioActions`에 `@Action`으로 액션을 선언하고, 같은 변경에서 테스트를 함께 넣는다. 액션에 CLI 명령이 없으면 테스트가 실패한다.
    - 필드의 형식이 입력을 정한다. 가리키는 항목은 `Exam.ID`처럼 종류의 ID로 쓰고(경로로 가리키는 노트는 `Note.Path`), `set`의 필드는 `Patch<T>`(빠지면 그대로, `T?`면 `none`/`null`로 지운다), 새 항목의 ID는 `@New`, 위치 인자는 `@Arg`로 쓴다. `///` 주석이 도움말이다.
    - 확인 문구와 완료 문구는 `{필드}` 자리표시자로 쓰고, ID는 실행하기 전에 이름으로 바뀐다. `.removes`와 `.moves`는 `confirm:`이 있어야 컴파일된다.
    - 선언한 뒤 `mise run gen-cli`로 CLI 명령을 다시 만든다. 손으로 쓰는 명령은 `cli: .manual`로 둔다.
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
| 액션 `@Action` | 데이터를 바꾸는 모든 동작. 앱, CLI, MCP가 같은 선언을 쓴다 | 있음 |
| 표준 구조 `standard-layout.swift` | 폴더와 파일 이름 | 있음 |
| 앱 링크(Route) | 앱 안의 모든 대상을 가리키는 주소. 알림, 위젯, 단축어, 멀티뷰, 기록이 쓴다 | #43 |
| 화면 계약 | 모든 화면이 주소 하나를 그리고 전체·칸·좁은 폭에서 동작 | #43 |
| 제안 | Claude가 내놓는 분류, 추출, 일정을 승인 화면으로 받는 공통 구조 | #90 |
| 파일 보기 렌더러 | 형식 판단(`MaterialFormat`)과 형식별 보기(`FileView`) | #179 |
| 단축키 | 명령마다 한 번 등록하고 메뉴, 설정, 팔레트가 읽는 표와 키 녹음 검사 | #116 |

축을 새로 만들면 이 표에 적는다.

### 화면: 모델과 뷰

화면 하나는 `app/features/<기능>/`의 `<화면>-view.swift`와 `<화면>-model.swift`로 나눈다. 본보기는 `features/catalog/`다.

- **모델** `<화면>Model`: `@MainActor @Observable final class`이고 `init(workspace:, 대상 ID)`로 만든다. 검색어, 고른 항목, 지우려는 항목처럼 화면의 상태를 들고, 뷰가 바로 그릴 값(묶고, 거르고, 세고, 문구로 만든 값)과 동작(`add()`, `remove()`)을 내놓는다. 동작은 `workspace.run(액션)`을 부른다.
- **뷰**: 모델을 읽고 배치만 한다. `body`에서 묶기, 거르기, 세기를 하지 않고 `workspace`를 직접 부르지 않는다. 뷰는 `@State private var model`을 `init(workspace:)`에서 만들고, `@State`는 시트, 마우스 올림, 포커스 같은 화면 상태에만 쓴다.
- **Workspace**: 폴더 읽기, 파일 감시, 액션 실행, `can`/`refusal`/`confirmation`만 맡는다. 한 기능만 쓰는 함수는 그 기능의 모델에 둔다.
- `course.json` 밖의 파일을 읽는 목록(노트, 퀴즈 카드)은 `workspace.notesRevision`과 `quizRevision`이 바뀔 때 다시 읽는다. 두 값은 `Workspace`가 액션 결과의 `changes`(`touchesNotes`, `touchesQuizzes`)와 폴더 전체 다시 읽기로만 올린다. 화면이 직접 올리지 않으므로, 어느 화면이나 Claude 패널, CLI로 써도 열린 목록에 나타난다.
- 파생 계산 중 데이터의 규칙(주차 묶기, 빠진 복습 노트 판단)은 `FolioDomain`에 두고 `swift test`로 검사한다. 화면에만 필요한 계산은 모델에 둔다.
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
      Recordings/              # 강의 녹음(.m4a)과 받아쓰기(.transcript.json). 2주차-1.m4a
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
- `Study`에는 직접 만든 파일을 둔다. 문제집, 모의고사, 요약 PDF와 `.tex` 원본, 노트를 빌드한 PDF(`Study/<제목>.pdf`)가 여기 온다. 어느 시험·단원용인지는 `material link-exam`, `material link-unit`으로 연결하고(앱에서는 자료 연결 편집기, 단원 페이지, 시험 카드), 시험 화면은 시험 폴더의 파일과 연결된 자료를 함께 센다. 어떤 자료가 회차, 단원, 시험에 딸리는지는 `CourseFile.routes(of:to:)` 하나가 정한다. 회차는 그 단원과 상위 단원의 자료를, 단원은 그 회차의 자료를 함께 본다. Folio 마크다운 노트는 `Notes`에 둔다.
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
- 테스트, 미리보기, 화면 밖 렌더는 이 Mac의 `Application Support/Folio`(녹음 복구, Whisper 모델)를 쓰지 않는다. 그 폴더는 앱의 `LocalFolders`로만 얻고 패키지는 쓰지 않으며(`mise run check-local-folders`가 `app`, `app-tests`, `packages`를 검사한다), 테스트와 미리보기에서 얻으려 하면 실행이 멈춘다. 화면 모델 테스트는 `fixtureWorkspace()`, 미리보기와 렌더는 `Workspace.scenario`가 임시 폴더를 준다. `FOLIO_GIST`로 가짜 폴더를 연 앱 실행(창 스냅숏 포함)은 녹음 폴더를 그 GIST 폴더마다 따로 임시 폴더에 둔다.

## 빌드와 실행

도구 버전과 환경 변수는 `mise.toml`이 정한다. Xcode 툴체인은 전역 `xcode-select`를 바꾸지 않고 `DEVELOPER_DIR`로 이 저장소에서만 쓴다. 명령은 항상 `mise run`으로 실행한다. 정의는 `mise.toml`에 있다.

- Xcode 프로젝트 생성: `mise run generate`. 그 뒤 `open Folio.xcodeproj`
- 패키지 테스트: `mise run test` (모든 패키지, 디자인 토큰 검사, Application Support 경로 검사)
- 화면 모델 테스트: `mise run test-app`. macOS에서 앱을 호스트로 `app-tests/`를 돌린다. 테스트 중에는 앱이 기억해 둔 GIST 폴더를 열지 않고, 창을 띄우거나 포커스를 가져가지 않는다
- 화면 밖 렌더: `mise run render`. `FolioFixtures`의 상황마다 모든 페이지(오늘, 학기, 과목의 각 탭, 성적, 졸업 요건, 사람, 코드, 설정의 각 탭)와 시트(입력 폼, 검색)를 라이트·다크 PNG로 `FOLIO_RENDER_DIR`(기본 `.build/renders`)의 `<상황>/`에 쓴다. 폭과 높이는 `FOLIO_RENDER_SIZES=1180,720,1440x900`(높이를 빼면 페이지 끝까지), 고르기는 `FOLIO_RENDER_SCREENS=today,course-`(이름 앞부분)와 `FOLIO_RENDER_SCENARIOS=busyDay`. 창이 뜨지 않고 실제 GIST 폴더와 시계를 쓰지 않는다. 리퀴드 글라스, 노트 보기와 `WKWebView`, 뷰 안에서 여는 시트, 창 틀은 그리지 못하니 `FOLIO_SNAPSHOT_DIR` 창 스냅숏(`docs/DESIGN.md` 마지막 절)으로 본다
- 가짜 GIST 폴더: `mise run fixture -- <폴더> [standard|legacy|<상황>]`. 상황(`busyDay` 등)은 `Scenario`로 회차와 마감이 채워진 폴더다. 이미 있는 폴더에는 쓰지 않는다
- 웹 번들: `mise run build-web`. `web/src/`를 고친 뒤 실행한다. Claude 패널의 색은 `theme.swift`의 값을 `NoteStyle`이 CSS 변수로 넘기므로 CSS에 색을 적지 않는다. 노트 보기의 글꼴, 색, 간격은 `app/design/note-look.swift`에 있다
- 노트 보기 렌더: `TEST_RUNNER_FOLIO_NOTE_RENDER=<폴더>`를 주고 `NoteSourceTests`와 `NoteReaderTests`를 돌리면 `app-tests/fixtures/all-markdown.md`(모든 문법을 쓴 노트)를 편집 보기와 미리보기로 그린 PNG가 그 폴더에 남는다
- macOS 빌드: `mise run build-mac`. `FolioMacros`는 로컬 패키지라 Xcode가 매크로 신뢰를 묻지 않는다. mise 작업의 `-skipMacroValidation`은 명령줄 빌드가 멈추지 않게 하는 안전장치다
- macOS 앱 설치: `mise run install-mac`. Release로 빌드해 `/Applications/Folio.app`을 바꾼다
- iPad 빌드: `mise run build-ipad`
- 생성 CLI 명령: `mise run gen-cli`. `@Action` 선언을 고친 뒤 실행한다. `mise run test`가 커밋된 파일이 낡지 않았는지 본다
- 명령줄 도구: `mise run cli -- <명령>`. `~/.local/bin`에 설치는 `mise run install-cli`. GIST 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다. 모든 쓰기 명령은 `--dry-run`으로 먼저 본다. 명령 목록은 `folio help`, 자연어로 찾기는 `folio help <하고 싶은 일>`
- MCP: `folio mcp`가 모든 쓰기 액션과 읽기 명령을 표준 입출력 MCP 도구로 연다. 앱의 Claude 패널은 `--propose`로 붙여 쓰기를 제안으로만 받는다. 셸 없는 클라이언트에는 `claude mcp add folio -- folio mcp`처럼 붙인다
- 에이전트 스킬: 원본은 `packages/folio-core/sources/folio-cli/commands/skill.swift`. 고친 뒤 `mise run cli -- skill > .claude/skills/folio/SKILL.md`로 사본을 맞춘다(테스트가 확인한다). 다른 에이전트에는 `folio skill --install <스킬 폴더>`
- 액션 커버리지: `mise run cli -- actions --check`. 모든 액션에 명령과 동등성 테스트가 있고 앱이 액션 밖에서 쓰지 않는지 본다. `mise run test`가 함께 돌린다
- 구조 검사: `check`
- 폴더 정리: `cleanup plan --out plan.json [--skip <경로>]`, 검토 뒤 `cleanup apply --plan plan.json --backup <iCloud 밖 폴더> [--include-flagged]`, 되돌리기는 `cleanup undo <batch ID>`. 계획은 `Exams/Past`를 `Inherited`로(낱개 파일은 족보로 표시), `Exam Review`와 `moves.jsonl`이 `Exam Review`에서 왔다고 기록한 `Exercises`의 파일을 `Study`로(시험 연결), `Notes/Exports`를 `Study`로 옮기고 빈 시험 폴더를 지운다. 출처가 불확실한 파일(그런 `Exercises`에 섞인 나머지, 이름에 정리·요약·대비·mock이 든 파일)은 검토 표시라 `--include-flagged` 없이는 옮기지 않는다. 되돌려도 `course.json`에 쓴 연결과 족보 표시는 남는다
- 노션 가져오기: `import notion <export.json>`. `export.json`은 Notion MCP로 읽은 내용을 `NotionExport` 형식으로 담은 파일이며, 실제 학업 데이터라 저장소에 넣지 않는다. 새 파일만 만들고 기존 파일은 덮어쓰지 않는다
- 노션 강의 정리와 점수: `import notes <덤프 폴더>`. 덤프 폴더는 과목마다 `<노션 페이지 ID>/index.json`, `notes/`, `assets/`를 가진다(`NotionCourseDump`). 노트 ID는 노션 페이지 ID라 다시 실행해도 중복되지 않고, 기존 항목은 덧붙이기만 한다
- 자료 등록과 과제 폴더 반영: `material track [<과목>]`. 과목을 빼면 모든 과목의 파일을 추적 목록에 넣고, `Assignments/` 폴더 중 과제가 없는 것에 과제를 만든다
- 시험 일정: `import exams <exams.json>`. `exams.json`은 구글 캘린더 "시험" 캘린더에서 읽은 `CalendarExam` 목록이며 저장소에 넣지 않는다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면 바꾸지 않고 알린다
- 단원: `import units <units.json>...`. 과목마다 `{"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["3주차-1"], "children"}]}`. 제목으로 맞춰 없는 단원만 더하고 회차 연결은 더하기만 한다
- 시험 범위: `exam scope <과목>/<시험> --taught`. 그 시험 전에 지난 회차에 연결된 단원(과 상위 단원)을 범위에 더한다. 빼지는 않는다
- 졸업 요건과 학생 정보: `import requirements <requirements.json>`. 학사편람 분류 표: `import handbook <handbook.json> [--accept]`. 두 파일 모두 실제 학업 데이터라 저장소에 넣지 않는다
- 폴더 없는 과목 옮기기: `transcript move`. 스키마 1의 `transcript.json`에 있던 과목을 같은 ID로 과목 폴더에 옮긴다. 인정학기 과목이 있으면 먼저 `semester source <학기> <출처>`로 출처를 정한다. `cleanup undo`로 되돌린다
- 학기별 학점과 GPA: `gpa`

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
- PR은 `main` 룰셋의 승인 1개와 검사(test, build)를 모두 채워야 머지된다. 승인은 리뷰 봇이 하고, 문서(`docs/`, 최상위 `*.md`, `.github/**/*.md`)만 바뀐 PR은 리뷰 없이 Actions가 한다(`review.yml`). 테스트 픽스처처럼 그 밖에 있는 `.md`는 리뷰를 받는다. PR을 열면 `gh pr merge --auto --merge`로 자동 머지를 걸어 둔다. 관리자 권한(`--admin`)으로 룰셋을 우회하지 않는다.
- 사용자가 이슈 없이 시킨 일은 바로 하고, 남은 범위나 새로 정한 동작은 해당 이슈에 적거나 새 이슈로 만든다.

### PR 전 점검

리뷰 봇이 여러 PR에서 거듭 지적한 실수다. PR을 열기 전에 바뀐 코드에 대해 하나씩 확인한다.

- 화면을 바꾼 PR은 눈으로 확인한 증거를 본문에 붙인다. 바뀐 화면을 `mise run render`(`FOLIO_RENDER_SCREENS`로 좁혀서)로 그린 PNG를 붙이고, 렌더가 그리지 못하는 것(리퀴드 글라스, 노트 보기와 `WKWebView`, 뷰 안에서 여는 시트, 창 틀)과 스크롤, 클릭 같은 동작은 `FOLIO_SNAPSHOT_DIR` 창 스냅숏(`docs/DESIGN.md` 마지막 절)이나 실행 화면으로 확인한다. 리뷰 봇은 코드만 읽으므로 화면의 고장은 이 확인으로만 잡힌다.
- 무엇을 보여 줄지, 언제 막을지, 날짜와 개수를 어떻게 셀지 같은 규칙을 뷰나 모델에 다시 적지 않았는지 본다. 규칙은 `FolioDomain`에 두고 `swift test`로 검사한다.
- `#if os(macOS)`나 `#if os(iOS)` 안에 넣은 기능에 다른 플랫폼 쪽(`#else`)이 있는지 본다. 없다면 그 플랫폼에 필요 없는 이유가 분명해야 한다. `mise run build-ipad`도 돌린다.
- 날짜가 공부일(`Settings.studyDay`, 하루 경계 새벽 4시)인지 달력 날짜인지 구분한다. 오늘 할 일, 마감까지 남은 날, 복습 날짜는 공부일로 센다. 경계 직전과 직후를 테스트한다.
- 테스트와 미리보기가 실제 `Application Support` 폴더나 GIST 폴더를 읽거나 쓰지 않는지 본다.
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
- 디자인은 시안 C(밝은 종이 질감, 사이드바·과목 열·본문의 3단)에 리퀴드 글라스를 더한 방향이다. Mac 창은 시안 D처럼 반투명 창 재질 위에 사이드바와 툴바가 평평하게 놓이고 본문이 둥근 패널로 들어간다. 시안 캔버스: https://claude.ai/artifact/Rk6BXvbGaSAbtjbVJA8JYK
- 색, 간격, 모서리, 글꼴은 `app/design/theme.swift`에서만 정의하고 모든 화면이 그 토큰만 쓴다. 라이트와 다크 값을 함께 둔다. 공용 구성 요소는 `app/design/`에 역할별 파일(`Layout`, `Containers`, `Indicators`, `Inputs`, `Interaction`)로 있다. `mise run check-design`이 화면 코드의 글꼴 크기, 색, 모서리 숫자를 잡는다.
- 리퀴드 글라스는 창 틀(사이드바, 툴바)과 떠 있는 요소(빠른 추가, 팝오버, Claude 패널)에만 쓴다. 본문은 종이 색으로 둔다. 창 구조와 유리 위 구성 요소의 규칙은 `docs/DESIGN.md`의 "창 구조" 절에 있다.
- 과목 강조색은 `course.json`의 `color`(프리셋 이름)를 `CourseAccent`로 읽고, 비어 있으면 학기 안 순서로 프리셋을 고른다. 예전에 고른 `#RRGGBB`는 파일을 바꾸지 않고 가장 가까운 프리셋으로 읽는다. 색은 프리셋 견본에서만 고른다. 과목 화면은 `\.accent` 환경값으로 색을 주입받는다. 프리셋 이름과 고르는 순서는 `FolioDomain`의 `CourseColor`가 정하고 앱과 CLI가 함께 쓴다. 색 값은 `theme.swift`에 둔다.

## 미결정 사항

미결정 사항은 해당 기능 이슈의 `정할 것` 절에 있다. 정해지기 전까지 지킬 것:

- 학업 외 폴더와 `2026-2`의 경진대회 자료(#106): 정리 도구는 이 항목을 건드리지 않는다.
- GIST 학칙의 재수강 처리, 졸업 평점 산정, 우등 졸업 기준(#123): 계산 규칙은 설정값으로 두고 하드코딩하지 않는다.
