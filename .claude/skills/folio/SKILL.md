---
name: folio
description: Folio 데이터(과목, 회차, 출석, 단원, 시험, 과제, 점수, 노트, 자료, 복습, 퀴즈)를 읽거나 바꿀 때 쓴다. GIST 폴더의 course.json, transcript.json, 노트, 로그를 직접 고치지 않고 명령줄 도구 folio를 거친다. "과제 추가해 줘", "노트 만들어 줘", "이번 주 결석 표시", "중간고사 범위 넣어 줘", "점수 기록", "이 과목 HUS야 PPE야?", "새 학사편람 나왔어" 같은 요청에 쓴다.
---

# folio

Folio의 모든 데이터 변경은 `folio` 명령으로 한다. `course.json`이나 노트 파일을 직접 고치지 않는다. 직접 고치면 앱이 지키는 규칙(양방향 연결, 폴더 생성, 기기별 로그, 원자적 쓰기, 모르는 필드 보존)이 빠진다.

## 실행

- `folio`가 PATH에 없으면 Folio 저장소에서 `mise run install-cli`로 설치하거나, 저장소 안에서 `mise run cli -- <명령>`으로 실행한다.
- GIST 폴더는 `--gist <경로>`, 환경 변수 `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다.
- 사용자의 실제 학업 자료다. 사용자가 시킨 것만 바꾼다. Folio를 개발하는 중이면 실제 폴더 대신 `mise run fixture -- <임시 폴더>`로 만든 가짜 폴더를 쓴다.
- 결과를 읽을 때는 `--json`을 붙인다. 쓰기 명령의 JSON은 `{action, dryRun, made, changes, notes}`다.
- 셸 없이 MCP만 쓰는 클라이언트는 `folio mcp`를 MCP 서버로 붙인다(`claude mcp add folio -- folio mcp`). 도구 이름은 명령의 공백을 `_`로 바꾼 것이고(`exam add` → `exam_add`), 입력은 `folio run`과 같다. 도구 목록에 없는 일은 `action_search`(하고 싶은 일을 말로 적으면 명령과 입력 형식을 돌려준다)로 찾아 `action_run`(명령 이름과 JSON 입력)으로 실행한다. 위 안전 규칙은 MCP 도구에도 같다. 앱의 Claude 패널이 붙이는 `folio mcp --propose`에서는 쓰기가 제안으로만 남고, 한 답 안의 제안은 차례로 쌓여서 다음 쓰기와 읽기가 그 위에서 돈다. 읽은 결과에 `proposed`가 붙은 항목은 아직 승인 전이다.

## 안전

1. 쓰기 전에 먼저 `--dry-run`으로 바뀔 것을 보고, 사용자에게 보여 준다.
2. 이동, 이름 변경, 삭제, 여러 항목을 한 번에 바꾸는 명령은 확인이 필요하다. 터미널이 아니면 종료 코드 5로 멈춘다. `folio run`도 무언가를 지우거나 옮기면 같은 확인을 받는다. 사용자가 승인한 뒤에만 `--yes`를 붙여 다시 실행한다.
3. 종료 코드 3은 대상을 못 찾았거나 여러 개에 맞은 경우다. 오류에 나온 후보 중 하나를 사용자에게 확인하고 다시 실행한다.
4. 노트의 일부를 고치거나 끝에 덧붙일 때는 `note edit`에 바꿀 원문(`--old`)과 새 글(`--new`), 붙일 글(`--append`)만 준다. 원문은 노트에 꼭 한 번 나와야 한다. 노트 전체를 새로 쓸 때만 `note write`를 쓰고, `note show --json`의 `hash`를 `--expect`에 넘긴다. 어느 쪽이든 그사이 앱이나 다른 기기에서 바뀌었으면 종료 코드 6으로 멈추니, 다시 읽고 고친다.
5. `set` 명령에서 값을 지우려면 `none`을 준다(`--due none`). 항목 인자는 빼지 않는다. 터미널이 아니면 고를 수 없어 종료 코드 2로 끝난다.
6. 성적, GPA, 점수는 잠겨 있다. `gpa`, `transcript`, `score list`는 잠겨 있으면 사용자의 Mac에 Touch ID 창을 띄우고, 사용자가 풀지 않으면 종료 코드 5로 멈춘다. 다른 명령의 성적 칸은 `••`로 나온다. 사용자가 성적을 물었을 때만 이 명령을 쓴다. 성적을 여러 번 읽는 긴 작업이면 처음에 `folio unlock --for 1h`로 한 번 승인받는다.

## 가리키기

과목은 강의 코드(`EC4207`), 폴더 이름, 과목 이름, UUID로 가리킨다. 과목 안의 항목은 `<과목>/<항목>`이다. 회차는 날짜(`11-03`, `11/3`, `2026-11-03`. 하루에 수업이 둘이면 `11-03 14:00`)나 그 수업의 단원, 시험과 과제와 단원은 제목, 노트와 자료는 경로나 파일 이름이다. 정확히 맞는 이름이 없으면 포함하는 이름을 찾는다.

답에서 항목을 가리킬 때는 `folio link <종류> <항목>`이 주는 `folio://` 링크를 붙인다. 사용자가 누르면 Folio에서 그 화면이 열린다(`folio link exam EC4207/중간고사`, 자료의 쪽은 `--page 12`, 노트의 제목은 `--heading 정의`, 녹음의 재생 위치는 `--time 12:30`). 노트에는 `[글](링크)`, `.tex`에는 `\href{링크}{글}`로 넣는다. `folio open`은 같은 대상을 사용자의 앱에서 바로 연다. 사용자가 열어 달라고 할 때만 쓴다.

## 자료 읽기

PDF의 글과 쪽 그림, 녹음 받아쓰기, 노트의 그림과 손필기 사진은 읽기 명령으로 본다. 한 번에 주는 양에 상한이 있고, 넘으면 잘라서 다음에 읽을 범위(`next`)를 알려 준다. 질문에 필요한 만큼만 이어 읽는다.

- `folio material read <과목>/<자료> --titles --json`으로 쪽 제목, 낱말 수, PDF 목차를 먼저 훑는다. 필요한 쪽만 `--pages 9-12`로 글을 읽고, 글이 적거나 그림, 수식, 스캔인 쪽만 `--images`로 쪽 그림을 본다. 터미널에서는 그림을 `--out <폴더>`(GIST 폴더 밖)에 파일로 쓰고, MCP에서는 그림을 바로 준다.
- `folio recording transcript <과목>/<회차> --from 10:00 --to 20:00 --json`은 녹음 받아쓰기를 시간 구간으로 자른다. 줄의 시각을 `folio link recording`의 `--time`에 넘기면 그 자리를 가리킨다.
- `folio note images <과목>/<노트> --json`은 노트가 넣은 그림을 준다. 과목만 주면 `Notes/assets`의 그림 목록이고, `--file <이름>`으로 그중 하나를 고른다.

## 자주 하는 일

```sh
# 읽기
folio session list EC4207 --json
folio assignment list EC4207 --json
folio exam show EC4207/중간고사 --json
folio unit list EC4207 --json

# 과제
folio assignment add EC4207 "HW 4" --due "2026-11-11 23:59" --dry-run
# 사용자가 적은 한 줄을 앱의 빠른 추가처럼 읽어서. 읽은 과목, 마감, 반복, 폴더를 보이고, 못 읽으면 쓰지 않는다
folio add "그래프 HW5 금 23:59" --dry-run
folio assignment status EC4207/HW3 submitted --dry-run

# 노트. 단원 노트의 종류 값은 예전 이름 그대로 topic이다
folio note add EC4207 "매칭 정리" --kind topic --dry-run
folio note link "EC4207/매칭 정리" --kind topic --unit 매칭 --dry-run
folio note edit EC4207/09-08 --old "non-adjacent" --new "서로 이웃하지 않는" --dry-run
# 밀린 몇 회차를 복습 노트 하나로 복습했을 때. 회차 하나를 뗄 때는 note unlink-session
folio note link-sessions "EC4207/10-26(월) 정리" 10-26 10-28 --dry-run

# 회차와 출석
folio session add EC4207 --date "2026-11-02 10:30" --dry-run
folio attendance set EC4207/09-08 absent --dry-run
# 아직 없는 회차의 결석은 회차와 함께 만든다
folio session add EC4207 --date "2026-11-11 10:30" --attendance absent --dry-run

# 시험
folio exam add EC4207 기말고사 --start "2026-12-14 10:00" --end "2026-12-14 12:00" --dry-run
folio exam scope EC4207/중간고사 --unit 트리 --unit 매칭 --dry-run
folio exam plan add EC4207/중간고사 --day 2026-10-19 "매칭 문제 풀기" --dry-run

# 점수
folio score add EC4207 --component 과제 --title HW2 --score 8 --max 10 --dry-run

# 인정학기와 지난 과목. 모든 과목에 폴더가 있고, 인정학기 과목은 _Credited/<출처>에 둔다
folio semester add 2024 credited --source "군 복무" --credited-hours 9 --dry-run
folio transcript add "영재고 AP" "일반물리학 및 연습 II" --code GS --number 1102 --mode pass_fail --dry-run

# 복습
folio review record EC4207/매칭 good --start "2026-10-28 20:00" --end "2026-10-28 20:40" --dry-run
# 건너뛰기는 review skip. 단원을 열어 본 시간이 있을 때만 --start와 --end를 준다
folio review skip EC4207/매칭 --dry-run
```

## Folio 노트 형식

노트는 마크다운이다. 명령 이름은 MCP 도구에서 공백이 `_`가 된다(`note figure add` → `note_figure_add`).

### 수식, 콜아웃, 목차
- 수식은 `$…$`, `$$…$$`. 문법은 노트의 `math`(기본 TeX). 블록 하나만 다르면 ```` ```asciimath ```` 펜스.
- 콜아웃: `> [!종류] 제목` 다음 줄부터 `> 본문`. `[!종류]-`는 접힌 채, `[!종류]+`는 펼친 채 접을 수 있다.
  종류: definition theorem lemma corollary proof example counterexample remark note tip warning important question solution summary abstract info danger. definition·theorem·lemma·corollary·example·counterexample은 번호가 붙는다(제목에 `1.2`를 쓰면 그 번호).
- 한 줄에 홀로 쓴 `[TOC]`는 목차.

### 링크
- 노트 `[[note:<ID>|이름]]`, 제목 `[[note:<ID>#제목|이름]]`, 블록 `[[note:<ID>#^블록|이름]]`(블록 ID는 문단 끝의 ` ^id`). `![[…]]`는 그 부분을 끼워 보인다.
- 자료의 쪽 `[[material:<ID>#page=N|파일 이름]]`. 그 밖은 종류 이름 그대로: `[[exam:<ID>|중간고사]]`, `session`, `unit`, `assignment`.
- ID는 `note list`, `material list` 같은 목록의 `--json`에서 읽는다.

### 도식
```` ```mermaid ```` 펜스는 앱이 노트 색으로 그린다. 색과 테마를 적지 않는다. mermaid로 안 되는 그림만 SVG로 그린다.

### 그림(SVG)
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

### 위젯
- `note widget add <과목> --html <파일>`이 `.folio/widgets/<ID>.html`을 쓰고 ID를 돌려준다. 노트에는
  ```` ```cb-widget ```` 펜스 안에 `{"id": "<ID>", "height": 320}`. 고칠 때는 `note widget show`의 `hash`를 `note widget write --expect`에.
- HTML 파일 하나가 격리된 frame에서 돈다. 인라인 `<script>`와 `<style>`만 되고, 네트워크·CDN·바깥 파일, 링크와 페이지 이동, 저장(상태는 다시 열면 처음부터)은 안 된다. 이미지는 `data:`/`blob:`.
- 노트 색이 CSS 변수로 미리 들어 있고 라이트·다크를 따라간다: `--text --text-2 --text-3 --line --line-soft --fill --code-fill --card --accent --accent-ink`, `--c-definition --c-theorem --c-example --c-warning --c-danger --c-neutral`. 색은 이 변수로만 쓴다. 바탕은 투명, `body`는 여백 0, 14px 시스템 글꼴.
- 높이는 내용을 따라 자라고 위젯 안은 스크롤되지 않는다. `height`는 처음 높이다. `100vh`처럼 frame을 따르는 높이를 쓰면 `height`가 그대로 남는다. 폭은 노트 열(390~720pt)이니 고정 폭 대신 폭에 맞추고, 넓은 것은 가로 스크롤.

### 그려 보기
쓰기 전에 `note figure render <과목> --text <SVG>`, `note widget render <과목> --text <HTML>`로 라이트·다크, 폭 480·900에서 그린 그림을 본다(이미 쓴 것은 이름이나 ID로). 겹친 글자, 잘린 부분, 다크에서 사라진 색, 위젯의 콘솔 오류를 고친 뒤 쓴다.

## 졸업 요건과 학사편람

- `folio requirement check --json`은 졸업 요건 화면의 알림(학사편람과 다른 분류, 이중 계산 상한 초과, 두 과정에 함께 셀 수 없는 과목, 분류 없는 과목)을 준다. 정할 것이 있으면 종료 코드 4다. `--only handbook|shared|unallowed|unassigned`로 판정을 골라 볼 수 있다.
- `folio requirement check <과목>`은 그 과목의 분류, 들은 해 편람의 분류, 이중 계산 여부를 보여 준다. 아직 듣지 않은 강의 코드(`HS2734`)를 주면 학사편람 분류 표에서 찾는다.
- 새 학사편람이 나오면(매년 한 번) 그해 분류 표를 넣는다.
  1. 편람 PDF에서 인문사회의 HUS, PPE처럼 표로만 가릴 수 있는 분류의 과목 코드 표를 찾는다. 사용자가 들었거나 들을 과목 코드부터 옮기고, 편람 전체를 옮기지 않아도 된다.
  2. `{"year": 2027, "source": "<편람 파일 이름과 쪽>", "areas": {"HS2734": "PPE"}}` 형식의 JSON으로 저장한다. 값은 `folio catalog show`의 분류 이름과 같아야 한다. 실제 학업 데이터라 저장소에 넣지 않는다.
  3. `folio import handbook <파일> --dry-run`으로 바뀌는 분류 제안을 사용자에게 보여 주고, 승인받으면 `--accept`를 붙여 적용한다. 같은 해 표는 새 표로 바뀐다.
- 과목은 들은 해의 편람으로만 가리므로 지난 해 표는 고치지 않는다. 졸업 요건 표와 이중 계산 상한(복수전공 9, 부전공 0)은 학번 기준이라 다시 넣을 일이 드물다. 학칙이 바뀌었을 때만 `folio import requirements --dry-run`으로 보여 주고 승인받아 고친다.

## 명령 찾기

- `folio help <하고 싶은 일>`: 자연어로 명령을 찾는다. 맞는 명령, 관련 옵션, 예시를 순위대로 보여 준다. `--json`도 된다.

```sh
folio help 과제 마감 바꾸기
folio help 단원 순서 바꾸기 --json
```

- `folio help`, `folio <대상> --help`: 사람이 읽는 도움말과 예시.
- `folio help --json`: 모든 명령, 인자, 옵션을 JSON으로.
- `folio actions --schema`: 모든 액션의 입력 형식(JSON Schema). 항목을 가리키는 필드는 UUID와 이름을 모두 받는다.
- `folio run <액션> --input '<JSON>'`: 액션 하나를 JSON 입력으로 실행한다. 명령 옵션으로 표현하기 어려운 입력에 쓴다. 바꾸는 액션(`set`, `rename`, `policy`, `wrap-up`)에는 바꿀 필드만 준다. 빠진 필드는 그대로이고 `null`이면 지운다.

```sh
folio run assignment add --input '{"course":"EC4207","title":"HW 5","due":"2026-11-18T23:59:00+09:00"}' --dry-run
folio run assignment set --input '{"course":"EC4207","assignment":"HW3","memo":"3번 질문함"}' --dry-run
```
