# Folio

과목을 중심으로 강의 자료, 노트, 손필기, 복습, 퀴즈, 과제, 성적을 관리하는 macOS와 iPadOS용 네이티브 앱입니다. 무엇을 만들지는 `docs/SPEC.md`에 있습니다. 이 파일에는 어떻게 만들지에 대한 규칙을 적습니다. 작업을 시작하기 전에 `docs/SPEC.md`에서 해당 절을 먼저 읽습니다.

## 소통 규칙

- 사용자와는 한국어로 대화한다. 영어로 답하지 않는다.
- 코드의 식별자, 주석, 커밋 메시지는 영어로 쓴다.
- 앱의 UI 문자열은 한국어로 쓰고 String Catalog(`Localizable.xcstrings`)로 관리한다.
- 명세와 다르게 구현해야 할 이유가 생기면 구현하기 전에 사용자에게 묻는다. 명세에 없는 기능을 임의로 추가하지 않는다.

## 기술 기준

- 최소 지원 버전은 macOS 26, iPadOS 26이다.
- Swift 6 언어 모드를 쓰고 strict concurrency 검사를 켠다.
- UI는 SwiftUI로 만든다. AppKit과 UIKit은 SwiftUI로 할 수 없는 부분에만 쓴다. 예를 들어 PencilKit 캔버스와 PDFKit 뷰가 여기에 해당한다.
- 직접 구현보다 잘 관리되는 라이브러리를 먼저 쓴다. 표준 라이브러리와 Apple 프레임워크로 되지 않는 일이면, 직접 짜기 전에 널리 쓰이고 유지되는 Swift 패키지가 있는지 찾는다. 라이브러리가 데이터 원칙을 어기는 경우(예: 노트 frontmatter의 원문을 보존하지 못하는 YAML 파서)에만 직접 구현하고, 그 이유를 코드 주석에 남긴다.
- 외부 의존성은 Swift Package Manager로만 추가한다. 새 의존성은 넣은 뒤 사용자에게 무엇을 왜 넣었는지 알리고, 커밋 메시지에도 남긴다. 예외는 노트 편집기와 수식에 쓰는 웹 번들(`web/`)로, npm 패키지를 정확한 버전으로 고정하고 `mise run build-web`으로 `app/resources/web/`에 묶는다. 묶은 결과는 커밋해서 앱 빌드에 node가 필요 없게 한다.

## 프로젝트 구조

플랫폼과 무관한 로직은 Swift 패키지로 분리해서 `swift test`로 Xcode 없이 테스트할 수 있게 합니다.

```text
folio/
  CLAUDE.md
  docs/
    SPEC.md
    DESIGN.md         # 디자인 시스템: 원칙, 토큰과 구성 요소의 쓰임, 패턴
  packages/
    folio-core/       # 모델, 저장소, 파일 추적, 성적과 GPA 계산, 복습 스케줄러. UI 코드 없음
    folio-markdown/   # 마크다운 파서와 확장 문법(콜아웃, 위키링크, 블록 참조, cb-table, cb-widget)
    folio-ai/         # Claude 연동 계층. 프로바이더 추상화, 맥락 구성, 작업별 요청과 응답 스키마
  app/                # 멀티플랫폼 앱 타깃(macOS, iPadOS)
  app-tests/          # 앱 수준 테스트
  web/                # 노트 편집기(CodeMirror), 수식(KaTeX, AsciiMath), 노트 스타일. 번들은 app/resources/web
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
| `FolioActions` | `packages/folio-core` | 데이터를 바꾸는 모든 동작(명세의 "명령줄 도구" 절의 액션). Domain의 변환과 Storage의 쓰기, 폴더 생성, 로그를 한 액션으로 묶는다. 액션 목록의 단일 출처 | UI, 출력 형식. 앱과 CLI가 같은 구현을 부른다 |
| `FolioIndex` | `packages/folio-core` | 기기별 로컬 SQLite 검색 색인(GRDB, FTS5 trigram). 바뀐 과목만 다시 읽고 PDF 본문을 뽑아 둔다. 캐시 폴더에 두며 지워도 다시 만든다 | GIST 폴더에 쓰기. 순위와 발췌는 Domain의 `SearchIndex`에 맡긴다 |
| `FolioCLI` | `packages/folio-core` | 터미널 도구 `folio`. 모든 액션을 `<대상> <동작>` 명령으로 열고, 사람용 출력과 `--json` 출력을 만든다 | 액션 로직. 명령은 인자를 해석해 `FolioActions`를 부르고 결과를 그리기만 한다 |
| `FolioMacros` | `packages/folio-core` | `@Action`과 필드 표시(`@Arg`, `@New`, `@Off`, `@Hidden`). 선언에서 입력 형식, init, 코딩, `spec`을 만들고 실수(맨 `UUID`, 없는 `{필드}`, 확인 문구 없는 삭제)를 컴파일 오류로 막는다 | 실행 코드. 앱과 CLI에 링크되지 않는다 |
| `FolioGen` | `packages/folio-core` | `@Action` 액션의 `spec`에서 `folio-cli/generated/commands.swift`를 만든다. 결과는 커밋한다 | FolioCLI에 의존. 생성 파일이 깨져도 다시 만들 수 있게 한다 |
| `FolioFixtures` | `packages/folio-core` | 테스트와 개발 실행에 쓰는 가짜 GIST 폴더. 파일을 코드에 두고 쓸 때 디스크에 펼친다. 공개 저장소에 과목 파일 폴더를 두지 않기 위해서다 | 앱과 CLI에 링크되지 않는다 |
| App | `app/` | 화면. `app/`(진입점과 탐색), `design/`(디자인 토큰과 공용 구성 요소), `features/<화면>/`, `platform/`(PencilKit, PDFKit, WKWebView 연결), `resources/` | 파일 시스템 직접 접근과 `course.json` 값의 직접 변경. 반드시 `FolioActions`를 거친다 |

- 앱에 새 데이터 조작을 넣을 때는 `FolioActions`에 `@Action`으로 액션을 선언하고, 같은 변경에서 테스트를 함께 넣는다. 액션에 CLI 명령이 없으면 테스트가 실패한다.
    - 필드의 형식이 입력을 정한다. 가리키는 항목은 `Exam.ID`처럼 종류의 ID로 쓰고(경로로 가리키는 노트는 `Note.Path`), `set`의 필드는 `Patch<T>`(빠지면 그대로, `T?`면 `none`/`null`로 지운다), 새 항목의 ID는 `@New`, 위치 인자는 `@Arg`로 쓴다. `///` 주석이 도움말이다.
    - 확인 문구와 완료 문구는 `{필드}` 자리표시자로 쓰고, ID는 실행하기 전에 이름으로 바뀐다. `.removes`와 `.moves`는 `confirm:`이 있어야 컴파일된다.
    - 선언한 뒤 `mise run gen-cli`로 CLI 명령을 다시 만든다. 손으로 쓰는 명령은 `cli: .manual`로 둔다.
    - 규칙은 액션이 아니라 `FolioDomain`의 모델(`course-rules.swift`의 `Document.model`)에 둔다. 모든 저장이 그 규칙으로 검사한다.
    - 화면은 규칙을 다시 적지 않는다. 버튼을 켜고 끌 때는 `workspace.can(액션)`, 막힌 이유는 `refusal`, 확인 문구는 `confirmation`으로 묻는다. 앱이 보여 주는 문서로 미리 실행해 본다.
- 새 관심사가 생기면 위 표에 모듈을 추가하고 방향을 정한 뒤 만든다.
- 앱 수준 테스트(`app-tests/`)는 처음 필요할 때 만든다.

### 단일 출처(SSOT)

- 폴더와 파일 이름 규칙은 `FolioDomain`의 `standard-layout.swift`(`Term`, `SemesterFolder`, `CourseFolder`)에서만 정의한다. 다른 곳에서 `"Lectures"`, `".folio"` 같은 문자열을 다시 쓰지 않는다.
- 사용자가 바꿀 수 있는 값(하루 경계, 복습 간격, 알림 시점, 학점 규칙)은 코드 상수가 아니라 `settings.json`과 `transcript.json`에서 읽는다. 기본값은 Domain의 한 곳에서만 정의한다.
- 빌드와 테스트 명령은 `mise.toml`의 작업으로만 정의한다. 문서는 `mise run <작업>`을 가리킨다.
- Xcode 프로젝트는 `project.yml`에서 생성한다. `Folio.xcodeproj`는 커밋하지 않고 직접 고치지 않는다.
- 최소 지원 버전은 `project.yml`과 각 `packages/*/Package.swift`에 있다. 도구 제약으로 하나로 합칠 수 없으니 함께 고친다.

## 데이터 원칙

이 원칙들은 사용자의 실제 학업 자료를 다루기 때문에 반드시 지킵니다.

1. **파일이 원본이다.** 모든 상태는 GIST 폴더 안의 파일(`course.json`, `transcript.json`, 마크다운 노트, `.drawing`, 기기별 `.jsonl` 로그)에 저장한다. 앱 내부의 SQLite는 검색과 집계를 위한 캐시이며, 지워도 파일에서 다시 만들 수 있어야 한다.
2. **폴더 구조는 Folio가 정한다.** GIST 폴더는 `docs/SPEC.md`의 "표준 폴더 구조"와 "이름 규칙"을 따른다. 과목 폴더의 하위 폴더는 `Syllabus`, `Lectures`, `Exercises`, `Textbooks`, `Assignments/<과제>`, `Exams/Past`, `Exams/<시험>`, `Notes`, `Ink`, `Recordings`, `Archive`, `.folio`만 쓴다. 과제와 시험은 하나당 폴더 하나이고, 시험 폴더는 데이터 모델의 Exam과 1:1로 대응한다. 과제 폴더 안의 파일 이름은 바꾸지 않는다. 예전 학기의 다양한 폴더 이름을 허용하는 분기 코드를 만들지 않는다. 기존 폴더는 일회성 정리 도구로 표준 구조에 맞춘다.
3. **삭제와 이동은 사용자 승인 후에만 한다.** 파일 이동, 이름 변경, 삭제는 사용자가 확인 화면에서 승인한 경우에만 수행한다. 수행한 이동과 이름 변경은 `.folio/moves.jsonl`에 기록해 되돌릴 수 있게 한다. Claude가 제안한 분류와 위치도 제안으로만 저장한다.
4. **쓰기는 원자적으로 한다.** 파일 쓰기는 `NSFileCoordinator`를 거치고, 임시 파일에 쓴 뒤 교체하는 방식으로 한다. iCloud 충돌 사본은 `NSFileVersion`으로 감지한다.
5. **로그는 추가만 한다.** `.folio/logs/<기기 ID>.jsonl`은 각 기기가 자기 파일에만 줄을 추가한다. 기존 줄을 고치거나 지우지 않는다.
6. **스키마에 버전을 둔다.** 모든 JSON 파일 최상위에 `schemaVersion`을 두고, 버전이 바뀌면 마이그레이션 함수를 추가한다. 모르는 필드는 읽을 때 버리지 않고 그대로 보존한다.
7. **식별은 ID로 한다.** 파일, 노트, 엔티티는 UUID로 식별한다. 경로와 제목은 표시용이며 바뀔 수 있다.

## 실제 데이터 위치

- GIST 폴더: `~/Library/Mobile Documents/com~apple~CloudDocs/Me/GIST`
- 옵시디언 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain`. Folio는 이 볼트를 읽거나 쓰지 않고, `obsidian://` 링크로만 참조한다.
- 개발과 테스트 중에는 실제 GIST 폴더에 쓰지 않는다. 테스트는 `FolioFixtures`의 가짜 폴더를 임시 디렉터리에 써서 쓴다. 앱이나 CLI를 가짜 폴더로 돌릴 때는 `mise run fixture -- <폴더>`로 만든다.
- 실제 폴더를 대상으로 처음 실행하기 전에 사용자에게 알리고, 백업이 있는지 확인한다.

## 테스트 기준

- `FolioFixtures`에는 가짜 GIST 폴더를 두 벌 둔다. 파일 목록과 내용은 `packages/folio-core/sources/folio-fixtures`에 코드로 있다.
    - `Fixture.standard`: 표준 구조를 따르는 폴더. 앱의 일반 기능 테스트에 쓴다.
    - `Fixture.legacy`: 현재 실제 폴더처럼 정리되지 않은 폴더. 정리 도구 테스트에만 쓴다. 한국어 하위 폴더(`강의자료`, `노트`, `숙제`, `족보`), 과목마다 다른 영어 하위 폴더(`Lectures`, `Homeworks`, `Exam Review`, `Slow Problems`, `Books`), `족보 (소순범)` 같은 이름, 학기 폴더의 `학사` 폴더와 흩어진 학사 파일, 과목 폴더 최상위의 강의계획서, 교재, 시험 안내, 자리 배치표, `Manuals` 폴더, `.git`이 있는 코드 과제 폴더, 같은 이름의 `.tex`와 PDF, 학업 외 폴더(`과대표`, `GIST OTP`)를 포함한다.
- 정리 도구는 `legacy`를 정리한 결과가 표준 구조를 만족하는지, `moves.jsonl`로 되돌리면 원래 상태와 같아지는지 테스트한다.
- 성적 계산 테스트에는 지어낸 등급과 손으로 계산한 기대값을 쓴다. 저장소가 공개라서 실제 성적과 GPA는 테스트, 픽스처, 문서에 넣지 않는다.
- 계산 로직에는 손으로 계산한 예시와 함께, 무작위 입력에서도 지켜져야 하는 성질을 `PropertyBased`(`propertyCheck`)로 검사한다(예: `GradePropertyTests`). 예시가 정답을 고정하고, 성질 테스트는 예시가 놓친 경계를 찾는다. 실패하면 출력된 시드를 `.fixedSeed(...)`로 붙여 다시 돌린다.
- 그래프 이론의 "Quiz 최저 점수 1회 제외"와 선형대수학의 "결석 6회면 최대 B0, 9회 이상이면 F"를 성적 규칙 테스트 사례로 넣는다.
- 하루 경계 테스트는 새벽 4시 경계를 기준으로 경계 직전과 직후를 모두 검사한다.

## 빌드와 실행

도구 버전과 환경 변수는 `mise.toml`이 정한다. Xcode 툴체인은 전역 `xcode-select`를 바꾸지 않고 `DEVELOPER_DIR`로 이 저장소에서만 쓴다. 명령은 항상 `mise run`으로 실행한다. 정의는 `mise.toml`에 있다.

- Xcode 프로젝트 생성: `mise run generate`. 그 뒤 `open Folio.xcodeproj`
- 패키지 테스트: `mise run test` (모든 패키지와 디자인 토큰 검사)
- 가짜 GIST 폴더: `mise run fixture -- <폴더> [standard|legacy]`. 이미 있는 폴더에는 쓰지 않는다
- 노트 편집기와 수식 번들: `mise run build-web`. `web/src/`를 고친 뒤 실행한다. 노트 색은 `theme.swift`의 값을 `NoteStyle`이 CSS 변수로 넘기므로 CSS에 색을 적지 않는다
- macOS 빌드: `mise run build-mac`. `FolioMacros`는 로컬 패키지라 Xcode가 매크로 신뢰를 묻지 않는다. mise 작업의 `-skipMacroValidation`은 명령줄 빌드가 멈추지 않게 하는 안전장치다
- macOS 앱 설치: `mise run install-mac`. Release로 빌드해 `/Applications/Folio.app`을 바꾼다
- iPad 빌드: `mise run build-ipad`
- 생성 CLI 명령: `mise run gen-cli`. `@Action` 선언을 고친 뒤 실행한다. `mise run test`가 커밋된 파일이 낡지 않았는지 본다
- 명령줄 도구: `mise run cli -- <명령>`. `~/.local/bin`에 설치는 `mise run install-cli`. GIST 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다. 모든 쓰기 명령은 `--dry-run`으로 먼저 본다. 명령 목록은 `folio help`, 자연어로 찾기는 `folio help <하고 싶은 일>`
- 에이전트 스킬: 원본은 `packages/folio-core/sources/folio-cli/commands/skill.swift`. 고친 뒤 `mise run cli -- skill > .claude/skills/folio/SKILL.md`로 사본을 맞춘다(테스트가 확인한다). 다른 에이전트에는 `folio skill --install <스킬 폴더>`
- 액션 커버리지: `mise run cli -- actions --check`. 모든 액션에 명령과 동등성 테스트가 있고 앱이 액션 밖에서 쓰지 않는지 본다. `mise run test`가 함께 돌린다
- 구조 검사: `check`
- 폴더 정리: `cleanup plan --out plan.json [--skip <경로>]`, 검토 뒤 `cleanup apply --plan plan.json --backup <iCloud 밖 폴더> [--include-flagged]`, 되돌리기는 `cleanup undo <batch ID>`
- 노션 가져오기: `import notion <export.json>`. `export.json`은 Notion MCP로 읽은 내용을 `NotionExport` 형식으로 담은 파일이며, 실제 학업 데이터라 저장소에 넣지 않는다. 새 파일만 만들고 기존 파일은 덮어쓰지 않는다
- 노션 강의 정리와 점수: `import notes <덤프 폴더>`. 덤프 폴더는 과목마다 `<노션 페이지 ID>/index.json`, `notes/`, `assets/`를 가진다(`NotionCourseDump`). 노트 ID는 노션 페이지 ID라 다시 실행해도 중복되지 않고, 기존 항목은 덧붙이기만 한다
- 자료 등록과 과제 폴더 반영: `material track [<과목>]`. 과목을 빼면 모든 과목의 파일을 추적 목록에 넣고, `Assignments/` 폴더 중 과제가 없는 것에 과제를 만든다
- 시험 일정: `import exams <exams.json>`. `exams.json`은 구글 캘린더 "시험" 캘린더에서 읽은 `CalendarExam` 목록이며 저장소에 넣지 않는다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면 바꾸지 않고 알린다
- 단원: `import units <units.json>...`. 과목마다 `{"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["3주차-1"], "children"}]}`. 제목으로 맞춰 없는 단원만 더하고 회차 연결은 더하기만 한다
- 시험 범위: `exam scope <과목>/<시험> --taught`. 그 시험 전에 지난 회차에 연결된 단원(과 상위 단원)을 범위에 더한다. 빼지는 않는다
- 졸업 요건과 학생 정보: `import requirements <requirements.json>`. 학사편람 분류 표: `import handbook <handbook.json> [--accept]`. 두 파일 모두 실제 학업 데이터라 저장소에 넣지 않는다
- 학기별 학점과 GPA: `gpa`

작업을 끝냈다고 보고하기 전에 관련 테스트와 빌드가 통과하는지 확인한다.

## 작업 순서

다른 기능이 의존하는 부분부터 쌓는다. 한 단계가 테스트까지 끝나면 커밋하고 다음 단계로 넘어간다.

1. 패키지 구조와 Xcode 프로젝트 생성, 가짜 GIST 폴더(`FolioFixtures`) 작성
2. 표준 구조 검사, 파일 추적, `course.json`과 `transcript.json` 읽기와 쓰기, 기기별 로그
3. 기존 폴더 정리 도구. 이동 계획을 만들어 보여 주고, 승인받은 뒤 실행하며, 되돌리기를 지원한다. 실제 폴더에 실행하기 전에 사용자가 계획을 검토한다
4. 노션 가져오기(명세의 "기존 데이터 이전" 절)
5. 성적, 학점, GPA 계산
6. 마크다운 파서와 노트 편집기, 렌더러
7. 강의 회차, 과제, 시험
8. 복습 스케줄러와 오늘 화면
9. Claude 연동 계층, 퀴즈와 채점
10. iPad 손필기
11. 위젯, 내보내기, 백업, 알림

## UI

- 화면을 만들거나 고치기 전에 `docs/DESIGN.md`를 읽는다. 원칙, 토큰과 구성 요소를 언제 쓰는지, 패턴, 새 토큰을 만드는 규칙이 있다.
- 디자인은 시안 C(밝은 종이 질감, 사이드바·과목 열·본문의 3단)에 리퀴드 글라스를 더한 방향이다. Mac 창은 시안 D처럼 반투명 창 재질 위에 사이드바와 툴바가 평평하게 놓이고 본문이 둥근 패널로 들어간다. 시안 캔버스: https://claude.ai/artifact/Rk6BXvbGaSAbtjbVJA8JYK
- 색, 간격, 모서리, 글꼴은 `app/design/theme.swift`에서만 정의하고 모든 화면이 그 토큰만 쓴다. 라이트와 다크 값을 함께 둔다. 공용 구성 요소는 `app/design/`에 역할별 파일(`Layout`, `Containers`, `Indicators`, `Inputs`, `Interaction`)로 있다. `mise run check-design`이 화면 코드의 글꼴 크기, 색, 모서리 숫자를 잡는다.
- 리퀴드 글라스는 창 틀(사이드바, 툴바)과 떠 있는 요소(빠른 추가, 팝오버, Claude 패널)에만 쓴다. 본문은 종이 색으로 둔다. 창 구조와 유리 위 구성 요소의 규칙은 `docs/DESIGN.md`의 "창 구조" 절에 있다.
- 과목 강조색은 `course.json`의 `color`(`#RRGGBB`, 예전 파일은 프리셋 이름)를 `CourseAccent`로 읽고, 비어 있으면 학기 안 순서로 프리셋을 고른다. 과목 화면은 `\.accent` 환경값으로 색을 주입받는다. 프리셋 이름과 고르는 순서는 `FolioDomain`의 `CourseColor`가 정하고 앱과 CLI가 함께 쓴다. 색 값은 `theme.swift`에 둔다.

## 미결정 사항

- GIST 폴더의 학업 외 폴더(`과대표`, `기숙사`, `기타`, `GIST OTP`, `무한도전 프로젝트`)와 `2026-2`에 놓인 경진대회 자료를 어디로 옮길지 사용자가 정해야 한다. 정해지기 전까지 정리 도구는 이 항목을 건드리지 않는다.
- GIST 학칙의 재수강 처리, 졸업 평점 산정 방식, 우등 졸업 기준은 아직 확인하지 않았다. 계산 규칙은 설정값으로 두고 하드코딩하지 않는다.
- 그 밖의 미결정 사항은 `docs/SPEC.md`의 "보류 사항과 미결정 사항" 절을 따른다.
