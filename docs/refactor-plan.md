# 리팩터링 계획

상태: 계획. CI(rhseung/folio#1)는 main에 들어갔다. 이름 바꾸기처럼 범위가 넓은 변경도 단계마다 PR을 올려 CI가 깨끗한 체크아웃에서 확인하게 한다.

## 목표

1. 저장소가 정하는 파일과 폴더 이름은 모두 케밥 케이스로 쓴다.
2. 뷰는 그리기만 한다. 상태, 파생 값, 동작은 화면별 모델이 맡는다(MVVM).
3. 앱 코드는 기능 단위 폴더로 나눈다.
4. 도메인 코드는 관심사별로 나눈다.
5. 주석은 코드가 말할 수 없는 이유만 남긴다.
6. UI 문자열은 코드에 직접 쓰지 않고, 문자열 카탈로그의 키로 쓴다.

## 지금 상태 (2026-10-29)

| 항목 | 값 |
| --- | --- |
| 앱 Swift 코드 | 69개 파일, 약 16,000줄. `Features`만 31개 파일 10,855줄이고, 파일 하나가 평균 350줄 |
| 큰 파일 | `SessionsView` 727줄, `RootView` 630줄, `Requirements` 615줄, `QuizSolveView` 606줄, `CourseView` 582줄 |
| 화면 모델 | `QuizModel` 하나. 나머지 화면의 로직은 `Workspace+<기능>` 확장(930줄)과 뷰의 `body` 안에 있다. 예: `SessionsView.body`가 주차별로 묶고 빠진 복습 노트를 센다 |
| `Features/Course` | 15개 파일에 회차, 단원, 시험, 과제, 자료, 노트, 과목 성적이 섞여 있다 |
| `FolioDomain` | 50개 파일이 한 폴더에 있다. 핵심 모델, 계산, 외부 형식 가져오기(노션, 캘린더, 학사편람), 정리 계획이 섞여 있다 |
| 주석 | `///` 앱 698줄, 패키지 1,296줄. `//` 앱 358줄, 패키지 327줄. 이 중 `FolioActions`의 `///` 296줄은 CLI 도움말로 쓰인다 |
| UI 문자열 | 카탈로그에 키 3개뿐. 한국어 문자열이 앱 1,361곳, CLI 668곳, Actions 289곳, Domain 172곳, AI 27곳, Storage 6곳에 코드로 박혀 있다 |

## 1. 케밥 케이스

파일과 폴더 이름에 적용한다. Swift의 타입 이름과 모듈 이름은 언어 식별자라서 PascalCase로 남는다. 모듈 이름에는 하이픈을 쓸 수 없다.

| 지금 | 바꾼 뒤 |
| --- | --- |
| `Folio/` | `app/` (제품 이름 Folio는 `project.yml`에 그대로 둔다) |
| `Packages/FolioCore/Sources/FolioDomain/`, `Tests/FolioDomainTests/` | `packages/folio-core/sources/folio-domain/`, `tests/folio-domain-tests/`. 타깃마다 `Package.swift`에 `path:`를 적는다 |
| `Web/`, `scripts/` | `web/`, `scripts/` |
| `SessionsView.swift`, `Workspace+Sessions.swift` | `sessions-view.swift`. `Workspace+Sessions`는 4단계에서 화면 모델로 옮겨지며 없어진다 |
| `Folio/Resources/Web/` | `app/resources/web/`. 번들을 읽는 경로와 `build-web` 출력 경로를 함께 고친다 |
| `FolioCLI/Generated/` | `generated/commands.swift`. `FolioGen`이 쓰는 경로를 함께 고친다 |

도구가 이름을 정해서 그대로 두는 것:
- `Package.swift`, `Package.resolved`, `mise.toml`, `AGENTS.md`, `README.md`, `SKILL.md`, `docs/SPEC.md`, `docs/DESIGN.md`, `.github/workflows/`, `main.swift`
- `Localizable.xcstrings`: 기본 표 이름이다. 바꾸면 모든 호출에 표 이름을 넘겨야 한다.
- `AppIcon.icon`: 빌드 설정의 앱 아이콘 이름과 묶여 있다.
- 가짜 GIST 폴더(`FolioFixtures`)의 폴더와 파일 이름: 가짜 GIST 데이터라 `StandardLayout`의 이름 규칙(`Lectures`, `2026-3/EC4207 그래프 이론`)을 따라야 한다. 절대 바꾸지 않는다.

하는 방법:
- 스크립트 하나가 옛 경로와 새 경로의 대응표를 만들고, 파일을 옮기고, 경로를 적은 곳(`project.yml`, `Package.swift`, `mise.toml`, CI, 테스트, 문서, 스킬)을 고친다.
- macOS 파일 시스템은 대소문자를 구분하지 않는다. 그래서 대소문자만 다른 이름은 임시 이름을 거쳐 두 번에 옮긴다(`Web` → `web-tmp` → `web`).
- 커밋은 영역별로 나눈다(패키지, 앱, 나머지).
- 미리 확인함: Swift 6.4 SwiftPM에서 케밥 케이스 Swift 파일이 문제없이 컴파일된다.

## 2. 주석

남기는 것:
- 이 방식이어야 하는 이유, 다르게 짜면 깨지는 이유.
- `shortcut:` 메모.
- `// design: one-off` 표시. `check-design`이 이 표시를 읽는다.
- `@Action`과 그 필드의 `///`. CLI 도움말과 `folio help <하고 싶은 일>` 검색에 쓰이는 데이터라서 주석이 아니다.

지우는 것:
- 이름을 되풀이하는 타입, 함수, 속성 설명.
- 코드가 무엇을 하는지 옮겨 적은 설명.
- 지난 경위(예: "예전 이름은 Coursebook").

코드는 건드리지 않고 주석만 지운다. 커밋은 모듈별로 나눠서, 리뷰할 때 삭제만 있는 diff로 보이게 한다. 4단계에서 코드를 옮기기 전에 해서, 옮길 코드의 양을 줄인다.

## 3. 도메인 관심사 분리

`FolioDomain`을 관심사별 폴더로 나눈다. 모듈은 그대로 두고 폴더만 나눈다. 아래는 초안이다.

| 폴더 | 파일 |
| --- | --- |
| `course/` | Course, CourseRules, CourseWork, Sessions, UnitTree, ExamPlan, AssignmentFiles, Note, Material*, Recording |
| `grades/` | Grading, GradeCalculator, GPACalculator, GradePlanning, GradeLock, Transcript, Catalog, RequirementAudit, HandbookClassifier |
| `study/` | ReviewScheduler, Quiz, QuizDeck, StudyActivity, Today, NotificationPlan |
| `layout/` | StandardLayout, LayoutCheck, FolderTree, PathTree, CleanupPlanner, IndexRules, BackupRetention |
| `import/` | NotionImport, NotionNotes, CalendarImport, UnitImport, RequirementImport, QuickAdd |
| `shared/` | Entity, Model, JSONValue, LogEvent, Settings, Search, SidebarOrder, CourseColor, Chat |

- `import/`는 바깥 형식을 도메인으로 바꾸는 어댑터다. 별도 모듈(`FolioImport`, Domain ← Import ← Actions)로 뺄 후보다. 의존 방향이 분명해지면 뺀다.
- Domain의 한국어 문자열(규칙이 막는 이유, 회차 이름 같은 표시 이름)은 5단계에서 그 모듈의 카탈로그 키로 옮긴다.

## 4. 앱: 기능 단위 폴더와 MVVM

```text
app/
  app/          진입점, 루트 화면과 탐색, Workspace(저장소)
  design/       디자인 토큰과 공용 구성 요소
  platform/     PDFKit, PencilKit, WKWebView 연결
  features/
    today/        today-view.swift, today-model.swift, ...
    course/       과목 화면의 틀과 섹션 전환
    sessions/  units/  exams/  assignments/  materials/  notes/  course-grades/
    grades/  requirements/  quiz/  review/  recording/  search/  semester/  settings/  catalog/  claude/
  resources/
```

역할 규칙:
- **모델** `<기능>Model`: `@MainActor @Observable final class`. Workspace와 대상 ID를 받는다. 뷰가 바로 그릴 수 있는 값과 동작(`add()`, `remove()`)을 내놓는다. 동작은 `workspace.run(액션)`을 부른다. 지금 있는 `QuizModel`이 본보기다.
- **뷰**: 모델을 읽고 배치만 한다. `body` 안에서 묶기, 거르기, 세기를 하지 않는다. `workspace`를 직접 부르지 않는다. `@State`는 시트가 열렸는지, 마우스가 올라갔는지 같은 화면 상태에만 쓴다.
- **Workspace**: 폴더 읽기, 파일 감시, 액션 실행, `can`/`refusal`/`confirmation`만 맡는다. `Workspace+<기능>` 확장은 각 기능의 모델로 옮긴다.
- 파생 계산 중 규칙에 해당하는 것(주차 묶기, 빠진 복습 노트 판단)은 `FolioDomain`으로 내려서 `swift test`로 검사한다. 화면에만 필요한 것은 모델에 둔다. 모델 테스트는 `FolioTests/`를 이때 처음 만들어 넣는다.

순서: 작은 화면에서 본보기를 만든 뒤 큰 화면으로 간다.
1. catalog(교수와 조교, 강의 코드)
2. today
3. sessions (가장 크다. 타임라인 패턴을 여기서 정한다)
4. 나머지 과목 화면
5. grades와 requirements
6. quiz
7. settings
8. 루트 화면

기능 하나를 커밋 하나로 묶는다. 모델, 뷰, 문자열 키, 테스트가 같이 들어간다. 라이트와 다크 스냅숏으로 화면이 그대로인지 본다.

## 5. UI 문자열 키

웹의 i18n 키처럼 쓰는 방법이 Xcode 26 문자열 카탈로그에 있다. 카탈로그에 키를 직접 넣으면 Swift 심볼이 생성된다.

```swift
// Localizable.xcstrings:  "sessions.add" = "회차 추가",  "sessions.count" = "회차 %lld개"
Button(.sessionsAdd) { ... }
Text(.sessionsCount(file.sessions.count))
```

- 키 이름은 `<기능>.<무엇>` 형식이다(`sessions.add`, `sessions.subtitle.missing-notes`). 키를 잘못 쓰면 컴파일이 실패한다. 복수형과 변수는 카탈로그의 변형 기능으로 처리한다.
- 미리 확인함: Swift 6.4 SwiftPM에서도 심볼이 생성된다(`String(localized: .sessionsAdd)`, 인자를 받는 `.sessionsCount(3)`).
- 앱은 `project.yml`에 `STRING_CATALOG_GENERATE_SYMBOLS: YES`를 넣는다. Xcode 빌드에서 동작하는지는 첫 기능을 옮길 때 확인한다.
- 카탈로그는 문자열을 내놓는 모듈마다 하나씩 둔다(앱, CLI, Actions, Domain).
- 예외: `@Action`의 `confirm:`과 `done:` 문구는 선언에 그대로 둔다. 매크로가 이 문자열 안의 `{필드}`를 컴파일할 때 검사하는데, 카탈로그로 옮기면 그 검사가 사라진다.
- 앱 화면은 4단계에서 기능별로 옮길 때 함께 옮긴다. 그래야 뷰 하나를 한 번만 건드린다.
- `check-design`에 Swift 코드 속 한국어 문자열을 잡는 검사를 더한다. 테스트, 픽스처, 액션 문구, `///` 도움말은 검사에서 뺀다.

## 6. 규칙 문서

- AGENTS.md: 이름 규칙, MVVM 역할, 주석 규칙, 문자열 키, 새 경로.
- `docs/DESIGN.md`의 경로.
- 에이전트 스킬: `Skill.swift`를 고친 뒤 `SKILL.md` 사본을 맞춘다.

## 순서와 확인

| 단계 | 내용 | 확인 |
| --- | --- | --- |
| 0 | 작업 중인 다른 브랜치가 없는지 `but status`로 확인 | |
| 1 | 이름 바꾸기 | `mise run test`, `build-mac`, `build-ipad`, `build-web`, `gen-cli` 최신 여부 |
| 2 | 주석 정리 | `mise run test`, `build-mac` |
| 3 | 도메인 폴더, Domain·Actions·CLI 카탈로그 | `mise run test` |
| 4~5 | 기능별 MVVM과 문자열 키 | 기능마다 `mise run test`, `build-mac`, 스냅숏 |
| 6 | 문서 | 스킬 사본 테스트 |

단계마다 브랜치 하나와 PR 하나로 올려서 CI가 확인하게 한다.

## 정한 것

- 앱 폴더는 `app/`이다.
- 패키지 안의 `Sources/`와 `Tests/`도 소문자 케밥 케이스(`sources/`, `tests/`)로 바꾼다.

## 정할 것

- `import/`를 별도 모듈로 뺄지.

## 위험

- 이름 바꾸기는 작업 중인 모든 브랜치와 충돌한다. 다른 브랜치가 없을 때 한 번에 한다. 바꾼 뒤 파일 이력은 `git log --follow`로 봐야 한다.
- 4단계는 변경이 크다. 기능별 PR로 잘게 나누고, 화면이 그대로인지 스냅숏으로 비교한다.
