# 리뷰 지침

claude-review-plugin이 PR을 검토할 때 `AGENTS.md`와 함께 읽는 파일입니다. 무엇을 만들지는 PR이 닫는 GitHub 이슈, 화면 규칙은 `docs/DESIGN.md`에 있습니다. 관련 이슈와 절을 읽고 대조합니다.

## 볼 것

검사가 잡지 못하는 규칙 위반을 찾습니다.

- **데이터 원칙.** 사용자의 실제 학업 자료를 다루므로 가장 먼저 봅니다.
    - `NSFileCoordinator`와 임시 파일 교체를 거치지 않는 쓰기
    - 기기별 로그(`.folio/logs/*.jsonl`)의 기존 줄을 고치거나 지우는 코드
    - 승인 화면 없이 파일을 옮기거나 이름을 바꾸거나 지우는 코드, `moves.jsonl`에 남기지 않는 이동
    - `schemaVersion`을 올리면서 마이그레이션을 빠뜨렸거나, 읽을 때 모르는 필드를 버리는 디코딩
    - 경로나 제목으로 항목을 식별하는 코드(ID로 식별해야 한다)
    - 개발이나 테스트 중에 실제 GIST 폴더나 이 Mac의 `Application Support/Folio`에 쓸 수 있는 경로. 경로를 직접 얻는 코드는 `check-code`가 잡으니, 그 밖의 길(환경 변수나 설정에서 읽은 경로, 테스트에서 덮어쓰지 않은 기본값)을 본다
- **공개 저장소.** 실제 성적, GPA, 학업 데이터(노션 내보내기, 캘린더, 학사편람 파일)가 테스트, 픽스처, 문서에 들어간 경우
- **화면의 모델과 뷰.** `check-code`는 뷰의 `workspace.<메서드>(` 호출과 `some View` 멤버 안의 `filter`, `reduce`, `sorted`, `count(where:)`, `min(by:)`, `max(by:)`, `partition`, `Dictionary(grouping:)`만 잡는다. 바뀐 화면마다 아래를 하나씩 본다.
    - 뷰가 `some View`가 아닌 도우미(`private func`, 계산 프로퍼티)로 묶기, 거르기, 세기, 정렬을 옮겨 놓고 `body`에서 부르는 경우. `first(where:)`, `contains(where:)`, `compactMap`으로 거르기, `.count`를 조건에 쓰는 것도 같다
    - 뷰가 `workspace`의 데이터(`settings`, `catalog`, `course`)를 읽어 스스로 판단하는 경우. 뷰는 모델이 내놓은 값을 그린다. 리비전 값(`notesRevision`, `quizRevision`)을 `onChange`로 지켜보는 것과 `liveNow`를 읽는 것은 괜찮다
    - 버튼을 켜고 끄거나 막힌 이유와 확인 문구를 화면이 직접 정하는 경우. `workspace.can`, `refusal`, `confirmation`, `ask`와 `.confirming`을 써야 한다
    - 모델이 파일을 직접 읽거나 쓰고(`FileManager`, `FolioStorage`의 쓰기) `FolioActions`를 거치지 않는 경우
    - 새 화면에 `<화면>-model.swift`가 없거나 모델이 `@MainActor @Observable final class`가 아닌 경우
- **규칙의 자리.** 무엇을 보여 줄지, 언제 막을지, 날짜와 개수를 어떻게 셀지는 `FolioDomain`에 두고 `swift test`로 검사한다. 화면 모델에 있으면 지적한다. 특히 날짜 계산(공부일과 달력 날짜, 주차, 마감까지 남은 날), 회차와 단원과 자료의 연결 판단, 점수와 출석 계산, 같은 판단을 두 화면 이상에 따로 적은 경우를 본다. CLI나 MCP도 같은 답을 내야 하는 판단이면 모델이 아니라 Domain이다
- **검사 기준선.** `.folio-lint-baseline.txt`에 줄을 더한 PR은 그 줄이 새 위반을 통과시키는지 본다. 줄은 고쳐서 줄어들거나, 기존 위반이 옮겨 가서 바뀔 때만 바뀐다. `// strings: data`를 화면 문구에 달아 검사를 피한 경우, `// design: one-off`를 화면 하나만의 값이 아닌 곳에 단 경우도 지적한다
- **단일 출처.** 폴더와 파일 이름을 `standard-layout.swift` 밖에서 다시 쓴 경우. 이름과 똑같은 문자열은 `check-code`가 잡으니, `"Notes/assets"`처럼 경로에 섞어 쓴 것을 본다. 사용자가 바꿀 수 있는 값(하루 경계, 복습 간격, 알림 시점, 학점 규칙)을 코드 상수로 둔 경우. 기본값을 두 곳에 정의한 경우
- **문자열.** 화면이나 CLI에 보이는 문구를 String Catalog 키 대신 코드에 적은 경우. 반대로 파일에 쓰는 값처럼 데이터인 문자열을 카탈로그에 넣은 경우
- **테스트.** 계산 로직(환산 점수, GPA, 복습 간격, 우선순위)에 손으로 계산한 예시나 `propertyCheck` 성질 테스트가 빠진 경우. 새 화면 모델에 `tests/unit/app` 테스트가 없는 경우. 하루 경계를 다루는 코드에 새벽 4시 직전과 직후 사례가 없는 경우
- **플랫폼.** macOS에만 있는 API를 `#if os(macOS)` 없이 쓰는 경우처럼 한 플랫폼에서만 깨지는 코드. iPad 빌드는 CI가 확인하지만 `#if`로 기능이 빠진 쪽은 확인하지 않는다
- **의존성.** Swift Package Manager가 아닌 방법으로 넣은 의존성. 잘 관리되는 라이브러리가 있는데 직접 구현했고 그 이유를 주석에 남기지 않은 경우
- **패치 노트.** 사용자에게 보이는 변화가 있는데 PR 본문에 `## 패치 노트` 절이 없거나, 줄이 `- feat: …`, `- fix: …`, `- change: …` 꼴이 아니거나(종류는 영어 그대로), 링크가 앱의 자리나 설정 탭이 아닌 경우(AGENTS.md "PR 전 점검"). `fix`를 `feat`로 적으면 업데이트 뒤 시트가 뜨니 종류도 본다
- **이슈.** 관련 이슈에 없는 기능을 더했거나 이슈와 다르게 구현한 경우. 맞는 구조 축(AGENTS.md "구조 축")이 있는데 화면마다 따로 구현한 경우
- **주석.** 코드가 이미 말하는 내용을 되풀이하는 주석, 이름을 풀어 쓴 설명형 문서 주석, 지난 동작이나 바꾼 이력을 적은 주석, 주석으로 막아 둔 코드. 주석은 정말 필요한 것(다르게 짜면 깨지는 이유, 바깥 제약, 숫자의 근거)만 `//`로, 한국어로 적는다(AGENTS.md "이름과 주석"). `check-code`는 `@Action` 필드 밖의 `///`와 한 줄 주석의 낱말이 아래 선언 이름에 다 들어 있는 경우를 잡는다. `@Action` 필드의 `///`는 CLI 도움말이라 데이터다
- 로직 오류, 빠진 경계 사례, 함께 바뀌지 않은 호출부와 문서, 구현이 하나뿐인 프로토콜이나 전달만 하는 래퍼

## 보지 않을 것

아래는 CI가 이미 잡습니다. 코멘트하지 않습니다.

- 컴파일러: 모듈 경계를 거스르는 import, strict concurrency, 없는 문자열 키, `@Action`의 `{필드}`와 `confirm:` 누락
- `mise run test`: 액션의 CLI 명령과 테스트 누락(`folio actions --check`), 낡은 생성 CLI 명령(`folio-gen --check`), `check-code`: 화면 코드의 글꼴 크기, 색, 모서리, 4pt 격자를 벗어난 치수, `.courseAccent` 없이 넣은 과목 색, `LocalFolders`를 거치지 않고 Application Support 경로를 얻는 코드, 뷰의 `workspace.<메서드>(` 호출과 `some View` 멤버 안의 거르기, 정렬, 묶기, `sources/app`의 한글 문자열과 화면 문구 자리의 영어 문자열, 표준 구조 폴더 이름의 문자열, 패키지의 `import SwiftUI`, Domain과 Markdown의 디스크 접근, `@Action` 필드 밖의 `///`, 이름만 되풀이하는 한 줄 주석, `app/design`·`app/platform`이 쓰는 기능 타입과 다른 기능의 Model, `AppLink.Kind` `switch`의 `default:`, 분 단위 `TimelineView`, 화면의 `.toolbar`, 실행 설정 밖의 환경 변수 읽기, 케밥 케이스가 아닌 이름, 20개 넘는 폴더. SwiftLint(`.swiftlint.yml`): 강제 언래핑, 이미지의 접근성 라벨, `first(where:)`·`isEmpty` 같은 컬렉션 관용구, 긴 함수와 타입
- macOS 앱 빌드와 화면 모델 테스트, iPad 빌드
