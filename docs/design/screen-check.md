# 화면 확인

화면을 바꾸면 바꾸기 전과 후를 같은 상황으로 그려 비교한다. 먼저 화면 밖 렌더로 보고, 렌더가 그리지 못하는 것은 창 스냅숏으로 본다. PR에 그림을 붙이는 법은 AGENTS.md "PR 전 점검"에 있다.

## 화면 밖 렌더

- `mise run render`가 `FolioFixtures`의 상황(`Scenario`: 수업이 꽉 찬 날, 시험이 한 달 안에 여섯 개 몰린 날, 한가한 토요일, 빈 학기)마다 모든 페이지와 시트를 라이트와 다크로 그려 `FOLIO_RENDER_DIR`(기본 `.build/renders`)에 PNG로 남긴다.
- 폭과 높이는 `FOLIO_RENDER_SIZES`(`1180,720,1440x900`처럼, 높이를 빼면 페이지 끝까지)로, 화면과 상황은 `FOLIO_RENDER_SCREENS`(이름 앞부분)와 `FOLIO_RENDER_SCENARIOS`로 고른다.
- 상황에는 지어낸 성적, 사람, 졸업 분류가 들어 있어 성적과 졸업 요건 화면도 빈 화면이 아니다. 상황은 고정된 시각을 기준으로 액션을 거쳐 만들어서 실제 시계와 실제 GIST 폴더에 기대지 않고, 창이 화면에 뜨지 않는다. Xcode 캔버스에서는 같은 상황을 `TodayView`의 `#Preview`로 본다.
- 렌더는 리퀴드 글라스 재질(빠른 추가 칸, 툴바, 사이드바), 노트 보기(TextKit의 편집 보기, `WKWebView`의 미리보기), Claude 패널(`WKWebView`), 창 틀, 뷰 안에서 여는 시트(단원 복습 등), PDF 보기를 그리지 못한다.

## 창 스냅숏

- 디버그 빌드(`mise run build-mac`의 `.build/DerivedData/Build/Products/Debug/Folio.app`)를 `FOLIO_GIST`에 `mise run fixture -- <폴더>`로 만든 가짜 폴더, `FOLIO_SNAPSHOT_DIR`에 저장할 폴더를 주고 `open -n --env …`로 열면 실제 창으로 모든 화면을 PNG로 남기고 종료한다.
- 스냅숏의 단계는 주소(`AppLink`), 창이 띄우는 시트(`ItemSheet`), 화면 상태 요청(`ScreenRequest`: 목록 열 펼치기, 빠른 추가에 줄 넣기, 쪽 열의 범위 고르기, 퀴즈 시작)으로만 화면을 움직인다. 화면은 `\.screenRequests`로 받은 요청에 답할 뿐 스냅숏인지 모르므로, 화면 파일에 스냅숏 분기(`SnapshotDriver`)를 두지 않는다. `ScreenFitTests`도 같은 요청으로 화면을 연다.
- 모양과 사이드바는 앱 인자 `-appearance dark`, `-sidebarOpen NO`로 고른다.

| 변수 | 보는 것 |
| --- | --- |
| `FOLIO_SNAPSHOT_WIDTH`, `FOLIO_SNAPSHOT_HEIGHT` | 창의 폭과 높이. 낮은 창에서 시트가 넘기는 모습은 긴 메모로 연 과제 시트 `course-assignment-edit`로 본다 |
| `FOLIO_SNAPSHOT_TABS` | 툴바의 탭. 그 수(예: `4`, `14`)만큼 탭을 열어 둔다 |
| `FOLIO_SNAPSHOT_PANES` | 칸. `2`, `3`은 앞의 두 탭에 렉처와 퀴즈 칸을 더하고, `courses`는 첫 탭에 두 과목을 나란히 둔다 |
| `FOLIO_SNAPSHOT_COLUMN=open` | 접힌 목록 열을 연 모습 |
| `FOLIO_SNAPSHOT_HOLD` | 적은 단계(쉼표로 여러 개)에서 몇 초 머물러, 그 사이 실제 창(유리 포함)을 `screencapture -l`로 찍게 한다. `screen`을 주면 단계마다 `<단계>.ready`를 써서 바깥 스크립트가 유리와 팝오버까지 찍게 한다 |
| `FOLIO_SNAPSHOT_QUICK_ADD=1` | 빠른 추가 칸의 여러 줄(긴 줄, 과목을 찾지 못한 줄, 오늘 화면과 과목 화면의 툴바 팝오버, 칩과 달력, 반복의 직접 설정)만 `quick-add-*.png`로 남긴다 |
| `FOLIO_SNAPSHOT_NOTE_LINK=<노트 ID>` | 노트 링크의 클릭. 그 노트를 `link-note-before`로, 미리보기의 첫 앱 링크를 눌러 간 곳을 `link-note`로 남긴다 |
| `FOLIO_SNAPSHOT_OUTLINE=popover` | 목차 칸을 둘 자리가 없는 폭(`FOLIO_SNAPSHOT_WIDTH=1120`)에서 `course-notes`가 목차 팝오버를 연 모습 |
| `FOLIO_PANE_SESSION=<폴더>` | 회차 배치 기억과 PDF 칸의 폭 변화. 회차에 연결된 첫 노트를 열고, 옆 칸에 렉처를 6쪽으로 열고, 새 탭에서 그 노트를 다시 열고, 칸 경계를 끌고, 셋째 칸을 연다. 단계마다 PNG와 칸 주소(`panes.txt`)를 남긴다. `FOLIO_PANE_SESSION_BEFORE=1`은 배치를 기억하기 전, `FOLIO_PLAIN_PDF=1`은 PDFKit의 기본 보기다 |
| `FOLIO_PANE_BUNDLES=<폴더>` | 칸 묶음. 한 탭에 칸 다섯 개를 열어 한쪽 묶음, 양쪽 묶음, 칸 하나인 묶음과 그 목록을 연 모습을 남기고, 칸 셋인 둘째 탭에서 가운데 칸을 손으로 접는다(손으로 접는 단계는 폭 1280) |
| `FOLIO_SNAPSHOT_FIRST_RUN=1` | 첫 실행 화면. 폴더를 연 실행에서는 뜨지 않으므로, 첫 실행 창 크기 그대로 모든 단계와 폴더를 다시 연결하는 두 모습(`missing`, `downloading`)을 `first-run-<단계>.png`로 남긴다 |

- `FOLIO_GIST`로 연 앱은 배치 기억을 사용자의 것과 따로 둔다(`PaneMemoryStore.forThisRun`).
- iPad는 시뮬레이터에서 `SIMCTL_CHILD_`를 붙인 같은 변수로 돌리고, 폴더는 앱 컨테이너 안에 둔다. 칸 묶음에서 iPad의 렉처 자리에는 자료 페이지를 연다. 첫 실행은 `SIMCTL_CHILD_FOLIO_FIRST_RUN_STEP=<단계>`로 그 단계에서 열고 시뮬레이터 화면을 찍는다.
