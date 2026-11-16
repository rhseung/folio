# 구조 축 세부

AGENTS.md "구조 축" 표의 축마다 지킬 규칙이다. 축에 기능을 얹거나 축을 고칠 때 그 절만 읽는다. 타입 이름이 원본을 가리키고, 여기에는 코드만 보고 알기 어려운 결정을 적는다.

## 액션 `@Action`

앱, CLI, MCP가 같은 선언을 쓴다. CLI 명령은 선언에서 생성하고(`mise run gen-cli`), 생성기가 다루지 못하는 입력만 손 명령(`cli: .manual(reason:)`)으로 쓴다. 쓰는 법은 AGENTS.md "레이어"의 액션 항목에 있다.

## 읽기 `@Query`

항목을 읽는 명령이다. 입력 필드는 액션과 같은 표시(`@Arg`, 종류의 ID)로 쓰고 `read(_:)`가 값을 돌려준다. CLI 명령과 `--json`, `folio run`, MCP 도구(입력 형식, 패널에 여는지 `panel:`, `folio help`의 `phrases:`)가 같은 선언에서 나온다. 사람용 출력은 FolioCLI에 `QueryOutput` 확장(`<명령>-output.swift`)으로 두고, 없으면 컴파일되지 않는다. 쓰기와 달리 `@New`, `Patch`, 문서 전체 필드는 받지 않는다. 선언으로 쓸 수 없는 읽기(그림을 주는 `material read`와 `note images`, 화면 밖 렌더, `search`, 검사 명령, `link`, `note format`, `settings show`)만 손 명령이고, `HandRead`에 이유와 패널·사본 표시를 단다(`actions --check`가 본다).

## 앱 링크 `AppLink`

앱 안의 모든 대상은 `folio://<종류>/<ID>[#page=N|#^블록|#제목|#t=12:30]`이다. 과목의 페이지는 `folio://course/<ID>/<페이지>`, 설정 탭은 `folio://settings/<탭>`이다.

- 종류마다 담는 곳, 받는 앵커, 페이지 경로는 `AppLink.Kind` 한 곳에 있다. 주소 해석, CLI 검사, `Workspace.entry`, 앱의 장소 이름과 아이콘(`place`), 항목이 여는 과목 페이지(`coursePage`), 목록의 고른 행(`selection(of:)`)이 이 표를 읽는다.
- 종류별 `switch`에는 `default:`를 두지 않는다(`kind-default`). 새 종류는 모든 곳이 다룰 때까지 컴파일되지 않아야 한다.
- 앱은 `\.openLink`로만 연다(여는 위치는 여기, 옆 칸, 새 탭, 새 창). 칸마다 `Navigator`가 뒤로·앞으로 기록을 둔다. 새 탭은 macOS 창 탭이 아니라 창이 툴바 줄에 그리는 탭이다(`WindowTabs`, 값은 `TabStrip`).
- 회차, 과제, 시험, 카드, 문제집 링크는 그 목록 페이지를 열고 항목으로 스크롤해 표시한다(`\.linkFocus`, `.linkTarget`). 자료의 쪽은 주소에 실려 기록의 지금 걸음을 고친다.
- 바깥에서 온 `folio://`는 앞에 있는 창의 새 탭에서 열고, 그 탭을 고르며 앱을 앞으로 가져온다.
- 같은 scheme이지만 `AppLink`가 아닌 주소가 둘 있다. 손으로 쓴 `[[제목]]`이 되는 `folio://note/<제목>`은 `[NoteFile].linked`로 찾고(`AppLink.noteTitle`), `folio://action/…`은 Claude 패널의 버튼이라 종류 이름으로 쓸 수 없다(`AppLink.actionHost`).

## 화면 계약 `ScreenView`

모든 화면은 주소 하나를 그리고 전체·칸·좁은 폭(1440·720·390)에서 넘치거나 잘리지 않는다. 주소에서 화면을 고르는 곳은 `Screen(entry)` 하나이고 `ScreenFitTests`가 세 폭을 검사한다. 규칙은 AGENTS.md "화면: 모델과 뷰"에 있다.

## 칸 배치 `PaneLayout`

탭 하나의 칸들(주소, 비율, 초점, 누른 순서)과 접기 규칙이다.

- 칸마다 기록(`Navigator`)과 위치 표시가 따로 있고(`TabPanes`), 툴바의 위치 표시와 뒤로·앞으로는 초점 칸을 따른다.
- 칸 수에는 한도가 없다. 몇 칸을 펼칠지는 기기가 아니라 그 순간의 칸 줄 폭과 누른 순서만으로 정한다(`PaneLayout.fold`, 칸 최소 폭 360pt). 폭이 줄면 칸을 빼거나 새 탭으로 떼지 않고 양 끝의 묶음(띠 하나)으로 접기만 한다. 다른 기기에서 남긴 배치와 이름 붙인 배치도 칸을 줄이지 않고 연다.
- 폭이 줄면 펼친 칸의 양 끝 중 더 오래 안 누른 쪽이 묶음으로 간다. 묶음에서 칸을 고르면 그 칸까지 펼친 칸들이 가장 짧게 밀려 간다. 손으로 접은 칸만 제자리 빗금 띠로 남는다(`PaneRow`). 자리가 없을 때 옆 칸에서 열면 새 칸이 초점으로 펼쳐지고 반대쪽 끝 칸이 묶음으로 간다.
- 툴바 탭이 줄어드는 순서는 `TabFit`이 정한다.
- Claude는 칸마다가 아니라 탭에 하나다(`WindowClaude`). 맥락에 칸 목록을 초점 칸부터 넣는다(`ContextBuilder.panes`).
- 칸이 둘 이상이고 노트와 녹음이 한 회차의 것인 탭(`PaneLayout.session(in:)`)은 바뀔 때마다 그 회차의 배치로 이 기기에 남는다(`PaneMemory`, `SessionLayoutSaver`). 칸이 하나인 탭이 그 회차의 노트나 녹음을 열거나 수업 시작이 나눠 보기 탭을 열면 남긴 배치로 돌아온다(`PaneMemory.restoring`). 노트 보기 방식도 칸에 함께 남는다(`PaneNotes`). PDF 칸은 폭이 바뀌어도 보던 자리를 지킨다(`SteadyPDFView`).
- 탭 메뉴의 "배치 ▸"가 기본 배치(`PanePreset.builtIn`)와 `settings.json`의 내 배치(`Settings.panePresets`)를 고르고 지금 배치를 저장한다. 수업 시작은 설정에서 고른 배치로 연다(`Settings.classStartPreset`).

## 제안 `ActionProposal`

승인하면 실행할 액션 하나(명령과 입력)와 제안을 만들 때 정한 ID다.

- 새 항목의 ID(`@New`)는 미리 실행에서 정해져 입력에 들어 있다.
- 제안으로 실행한 액션(`ActionContext.proposal`)은 바꾼 과목의 `course.json`(`appliedProposals`)과 기기 로그(`ProposalAppliedEvent`)에 그 ID를 남긴다. 이미 남은 제안은 실행 전에 멈춘다(`ActionContext.refuseAppliedProposal`, `ActionError.applied`). 부르는 쪽은 이것을 적용된 것으로 보고, 패널은 과목 문서에 남은 ID로 다른 기기가 적용한 제안을 적용됨으로 그린다(`Chat.markingApplied`).
- iCloud 충돌 사본은 과목을 읽을 때 항목 ID와 적용한 제안 ID로 합친다(`CourseFile.merged(with:)`, `CourseStore.resolveConflicts`). 같은 항목은 나중에 고친 쪽을 남기므로 액션은 저장할 때 바뀐 항목을 모두 찍는다(`touchChanged`). 합친 사본은 지우지 않고 해결됨으로만 둔다.
- 승인 화면에 보이는 제안은 `FolioDomain`의 `Proposal`이다. 종류(`ProposalKind`)가 묶음(`ProposalGroup`), 넣을 과목을 고르는지(`picksCourse`), 여러 제안을 한 액션으로 합칠 목록 필드(`list`)를 정한다. 승인은 `action`, 무시는 `dismissal`이고, 표시(`ProposalFlag`)가 검토할 것을 알리거나 승인을 막는다(LMS 뷰어 전용).
- 같은 명령의 제안 여럿은 목록 필드를 이어 액션 하나로 승인하고 무시한다(`[Proposal].approvals(in:)`, `dismissals`). 그래서 한 번 묻고, 하나가 막히면 아무것도 쓰지 않는다.
- 제안의 출처는 셋이고, 출처마다 승인하는 곳이 따로 있다. 종류의 묶음(`ProposalKind.group`)이 없는 제안은 LMS 탭에 오지 않는다.
    - LMS(`LMSProposal.proposal`, 승인은 `lms accept`, 무시는 `lms mark`): `ProposalBoard`가 강의실로 묶어 LMS 탭(`folio://lms`)에 모은다. 받은 과제가 LMS와 다른 것(`LMSDifference`)은 과목이 정해져 있어 과목을 고르지 않고, 승인은 `assignment status`나 `assignment set`이다.
    - 대화 파일(`Chat.pending`): 그 대화의 Claude 패널에서 승인한다. Claude는 LMS에 속하지 않아 LMS 탭에 모으지 않는다(사용자 결정). 패널의 거절은 #515다. CLI와 MCP는 `proposal list`로 모든 과목의 대화에서 기다리는 제안을 읽는다.
    - 폴더 정리 옮기기(`PlannedMove.proposal`, 검토 표시는 `.review` 표시, 승인은 `cleanup apply`): 자료 화면과 `cleanup plan`이 같은 선언을 읽는다.
- 파일 분류, 자료에서 정보 추출, 렉처 단원 구간 제안은 #90에 남았다. 패널의 제안 단계는 `docs/mcp.md`에 있다.

## 파일 보기 렌더러

`FolioDomain`의 `MaterialFormat`이 확장자로 형식을 정하고(`material show`도 같은 값을 쓴다) `renderer`가 보기를 고른다. `app/platform/materials/file-view/`의 `FileView` 하나가 그린다. PDF는 PDFKit(`PDFPane`), 마크다운은 노트 미리보기, `.tex`·코드·텍스트는 편집기(자료와 노트) 또는 읽기 전용 소스, 이미지와 오디오는 네이티브 보기, 나머지는 같은 칸 안의 Quick Look이고, 그것도 못 보이면 "열 수 없음"과 다른 앱으로 열기다. 자료는 `folio://material` 링크로 자료 탭에서 연다(과제, 문제집, 시험, 단원, 검색이 모두 이 길). 복습의 원본과 학기의 `_Admin` 파일도 `FileView`로 보인다. 화면이 파일을 따로 열지 않는다.

## 파일 분류 `FileRule`

파일 이름으로 그 파일이 무엇인지 읽는 순서 있는 규칙 표(`FileRule.table`)다. 자료 추측(`MaterialIntake.guess`)과 정리 계획(`CoursePlanner`)이 같은 표를 앞에서부터 읽고, 규칙마다 어느 쪽이 읽는지(`readers`)를 적는다. 주차 낱말(`FileRule.week`, `numbered`)도 함께 쓴다. 과제 종류와 별칭(`AssignmentKind`)은 표 하나(`Settings.assignmentKindTable`)이고 `settings.json`의 `assignmentKinds`로 더하고 고친다(비어 있으면 `AssignmentKind.builtIn`). 자료 추측과 정리 계획은 접두어와 별칭을, 빠른 추가와 과제 폴더 이름(`AssignmentFiles`)은 접두어를 읽는다.

## 설정 항목 `SettingItem`

`settings.json`의 항목마다 키(점 경로), 값의 모양과 허용 범위, 지울 수 있는지, 기본값과 이름(`fallback`, `name`), 설정 화면의 자리(`place`), 단위, 눈금, 켜고 끄는 토글(`switchedBy`), 선택지 이름을 `FolioDomain`에 한 번 적는다.

- `Settings()`의 기본값, 설정 화면, `settings set`의 검사와 MCP 입력 형식, `settings show`가 이 선언을 읽는다. `Settings`에 선언하지 않은 키가 생기면 테스트가 실패한다.
- 켜고 끄기, 숫자, 고르기, 시각, 글 항목은 `SettingBlock`과 `SettingRow`가 선언에서 행으로 그린다. 따로 그리는 항목(배치 목록, 스니펫, 노트 템플릿, 콜아웃 종류 `CalloutList`, 백업 위치)도 선언하고 자리를 적는다.
- 알림 종류는 표 하나(`NotificationSettings`의 `[Kind: Rule]`)이고, 종류마다 칸이 `notifications.<종류>.<칸>` 항목이다. 알림 계획(`NotificationPlan`)과 설정 화면이 같은 표를 읽고, 종류가 어느 칸을 쓰는지는 선언된 항목이 정한다(`Kind.item`).
- 학점 규칙은 `transcript.json`의 값이라 이 표에 없다.

## 자동 완성 메뉴 `CompletionMenu`

편집 보기의 모든 자동 완성(`/` 블록, 콜아웃 종류, 코드 언어, TeX 명령과 환경, AsciiMath 기호, 스니펫, 링크, 수식의 기호 전체 목록)이 이 메뉴 하나다.

- 무엇을 완성할지는 `FolioMarkdown`의 `Completion`이 원문에서 읽고, 메뉴는 캐럿 옆에 하나만 뜬다. 늦게 오는 후보(링크)는 `more`로 더한다.
- 수식 기호의 분류와 목록은 `MathSymbols`가 정하고 f(x) 기호 팔레트와 함께 쓴다.
- 링크 후보는 `NoteLinkCompletion`이 검색 색인과 파일에서 찾고, 보일 것과 순서는 `FolioDomain`의 `LinkCandidates`가 정한다.
- 한글 조합 중에는 메뉴, 짝 기호, 목록 이어 쓰기가 끼어들지 않는다.
- 입력 안내 시트(⌘/)는 같은 표를 `InputGuide`로 읽어 상황별로 보인다.
- 지금은 Mac만 있다. iPad 메뉴는 #31이다.

## 노트 문법 `NoteSyntax`, 콜아웃 종류 `CalloutTable`

노트의 확장 문법(대시 목록 항목, 블록 ID, 이스케이프, 위키링크, 맨 주소, 각주)마다 파서 전에 원문을 가리는 법, 편집 보기가 칠할 범위(`SourceSpan`), 그린 HTML을 고치는 법을 `FolioMarkdown`의 목록 하나에 둔다. `ParsedNote`, 편집 보기, `HTMLRenderer`는 목록을 차례로 돌기만 한다. 편집 보기의 맨 주소만 `AppLink`로 읽어야 해서 앱이 목록 뒤에 칠한다. 입힐 속성은 앱의 `SourceStyler`가 종류마다 정한다.

콜아웃 종류는 기본 종류(`CalloutKind.defaults`)에 `settings.json`의 `callouts`를 더한 표다. 편집 보기의 색, 페이지의 CSS(`NoteStyle.callouts`), 번호, 자동 완성, 입력 안내, `note format`이 이 표를 읽는다.

## 항목 메뉴 `ItemCommand`

항목 종류마다 메뉴가 하나다. 무슨 행이 어느 무리(`MenuGroup`)로 서는지는 `FolioDomain`이 데이터와 시각, 연 자리(`MenuHost`)로 정하고(`CourseFile.commands(for:at:host:)`), 앱의 `ItemMenu`가 세 띠로 나눠 그린다. 오른쪽 클릭, ⋯, 검색 결과가 같은 메뉴를 쓰고, 화면의 단추는 같은 행을 `ItemButton`으로 그린다. "편집…"의 시트, "삭제…"의 확인, 파일 추가는 창이 띄운다(`\.itemSheets`). 종류마다 명령은 `<종류>MenuCommand`다(CLI의 명령 타입과 이름이 겹치지 않게 하기 위해서다). 노트·자료·단원·녹음·과목 화면은 페이지 끝의 `⋯`(`PageMenuButton`)로 같은 메뉴를 연다. 노트와 자료의 이름 바꾸기는 그 시트의 이름 칸이다.

## 라이브 시계 `LiveClock`

화면이 그리는 지금 시각이다. 분이 바뀔 때, 앱이 앞으로 오거나 Mac이 깨어날 때 갱신한다. 분 단위로 바뀌는 뷰는 `TimelineView` 대신 `workspace.liveNow`나 `LiveTime`으로 읽는다(`minute-timeline`). 초를 세는 타이머만 `TimelineView`를 쓴다.

## 빠른 추가 인식기 `QuickAdd`

빠른 추가 한 줄을 읽는 법이다. 낱말마다 인식기(`lexicon.swift`)가 읽고, 결합 규칙(`grammar.swift`의 `Rule`)이 이웃을 묶고, 해석(`resolve.swift`)이 줄의 구간 `spans`(마감, 과목, 과제 종류와 번호)와 저장할 값을 낸다. 제목은 어느 구간에도 들지 않은 글이다. 칸의 알약과 칸 아래 칩은 `spans`와 그 값만 읽는다. 새 종류(시험, 메모)는 인식기와 `Span.Field`를 하나씩 더한다. Apple의 날짜 인식기는 실제 시계로 읽으므로 표가 못 읽은 나머지에만 쓴다. CLI의 `folio add`도 같은 `QuickAdd.parse`를 쓴다.

## 단축키

명령마다 한 번 등록하고 메뉴, 설정, 팔레트가 읽는 표와 키 녹음 검사다. 아직 없다(#116).
