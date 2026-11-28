---
name: folio
description: Folio 데이터(과목, 회차, 출석, 단원, 시험, 과제, 점수, 노트, 자료, 문제, 카드, 오답)를 읽거나 바꿀 때 쓴다. GIST 폴더의 course.json, transcript.json, 노트, 로그를 직접 고치지 않고 명령줄 도구 folio를 거친다. "과제 추가해 줘", "노트 만들어 줘", "이번 주 결석 표시", "중간고사 범위 넣어 줘", "점수 기록", "이 과목 HUS야 PPE야?", "새 학사편람 나왔어" 같은 요청에 쓴다.
---

# folio

Folio의 모든 데이터 변경은 `folio` 명령으로 한다. `course.json`이나 노트 파일을 직접 고치면 앱이 지키는 규칙(양방향 연결, 폴더 생성, 기기별 로그, 원자적 쓰기, 모르는 필드 보존)이 빠진다.

## 실행

- `folio`가 PATH에 없으면 Folio 저장소에서 `mise run install-cli`로 설치하거나 `mise run cli -- <명령>`으로 실행한다.
- GIST 폴더는 `--gist <경로>`, `FOLIO_GIST`, 앱이 연 폴더 순으로 정한다.
- 사용자의 실제 학업 자료다. 사용자가 시킨 것만 바꾼다. Folio를 개발하는 중이면 `mise run fixture -- <임시 폴더>`로 만든 가짜 폴더를 쓴다.
- 결과는 `--json`으로 읽는다. 쓰기 명령의 JSON은 `{action, dryRun, made, changes, notes}`다.
- 셸이 없는 클라이언트는 `folio mcp`를 붙인다(`claude mcp add folio -- folio mcp`). 도구 이름은 명령의 공백을 `_`로 바꾼 것이고(`exam_add`), 입력은 `folio run`과 같다. 목록에 없는 일은 `action_search`로 찾아 `action_run`으로 실행한다. 아래 안전 규칙은 MCP에도 같다. 앱의 Claude 패널이 붙이는 `folio mcp --propose`에서는 쓰기가 제안으로 쌓이고, 읽은 결과에 `proposed`가 붙은 항목은 아직 승인 전이다.

## 안전

1. 쓰기 전에 `--dry-run`으로 바뀔 것을 보고 사용자에게 보여 준다.
2. 이동, 이름 변경, 삭제, 여러 항목을 한 번에 바꾸는 명령(`folio run` 포함)은 확인이 필요하다. 터미널이 아니면 종료 코드 5로 멈춘다. 사용자가 승인한 뒤에만 `--yes`를 붙여 다시 실행한다.
3. 종료 코드 3은 대상을 못 찾았거나 여러 개에 맞은 경우다. 오류에 나온 후보 중 하나를 사용자에게 확인한다.
4. 노트의 일부를 고치거나 덧붙일 때는 `note edit`에 원문(`--old`, 노트에 꼭 한 번 나와야 한다)과 새 글(`--new`) 또는 붙일 글(`--append`)만 준다. 노트 전체를 새로 쓸 때만 `note write`에 `note show --json`의 `hash`를 `--expect`로 넘긴다. 그사이 바뀌었으면 종료 코드 6이니 다시 읽고 고친다.
5. `set` 명령에서 값을 지우려면 `none`을 준다(`--due none`). 항목 인자는 빼지 않는다. 터미널이 아니면 고를 수 없어 종료 코드 2로 끝난다.
6. 성적, GPA, 점수는 잠겨 있다. `gpa`, `transcript`, `score list`는 사용자의 Mac에 Touch ID 창을 띄우고, 풀지 않으면 종료 코드 5다. 다른 명령의 성적 칸은 `••`로 나온다. 사용자가 성적을 물었을 때만 쓰고, 성적을 여러 번 읽는 긴 작업이면 처음에 `folio unlock --for 1h`로 한 번 승인받는다.

## 가리키기

과목은 강의 코드(`EC4207`), 폴더 이름, 과목 이름, UUID로, 과목 안의 항목은 `<과목>/<항목>`으로 가리킨다. 회차는 날짜(`11-03`, `11/3`, `2026-11-03`, 하루에 둘이면 `11-03 14:00`)나 그 수업의 단원, 시험과 과제와 단원은 제목, 노트와 자료는 경로나 파일 이름이다. 정확히 맞는 이름이 없으면 포함하는 이름을 찾는다.

답에서 항목을 가리킬 때는 `folio link <종류> <항목>`이 주는 `folio://` 링크를 붙인다(`--page 12`, `--heading 정의`, `--time 12:30`). 노트에는 `[글](링크)`, `.tex`에는 `\href{링크}{글}`로 넣는다. `folio open`은 사용자가 열어 달라고 할 때만 쓴다.

## 자료 읽기

읽기 명령은 한 번에 주는 양에 상한이 있고, 넘으면 다음 범위(`next`)를 알려 준다. 질문에 필요한 만큼만 이어 읽는다.

- `folio material read <과목>/<자료> --titles --json`으로 쪽 제목과 목차를 먼저 훑고, 필요한 쪽만 `--pages 9-12`로 읽는다. 글이 적거나 그림, 수식, 스캔인 쪽만 `--images`로 본다. 터미널에서는 그림을 `--out <GIST 폴더 밖 폴더>`에 쓴다.
- `folio recording transcript <과목>/<회차> --from 10:00 --to 20:00 --json`은 받아쓰기를 구간으로 자른다. 줄의 시각은 `folio link recording --time`에 넘긴다.
- `folio note images <과목>/<노트> --json`은 노트의 그림을 준다(`--file <이름>`으로 하나).

## 알아 둘 것

```sh
# 사용자가 적은 한 줄을 앱의 빠른 추가처럼 읽는다. 못 읽으면 쓰지 않는다
folio add "그래프 HW5 금 23:59" --dry-run
# 단원 노트의 종류 값은 예전 이름 그대로 topic이다
folio note add EC4207 "매칭 정리" --kind topic --dry-run
# 밀린 회차를 복습 노트 하나로 복습했을 때. 하나를 뗄 때는 note unlink-session
folio note link-sessions "EC4207/10-26(월) 정리" 10-26 10-28 --dry-run
# 아직 없는 회차의 결석은 회차와 함께 만든다
folio session add EC4207 --date "2026-11-11 10:30" --attendance absent --dry-run
# 노트의 일부만 고친다. --old는 노트에 꼭 한 번 나와야 한다
folio note edit EC4207/09-08 --old "non-adjacent" --new "서로 이웃하지 않는" --dry-run
# 인정학기 과목은 _Credited/<출처>에 두므로 학기에 출처가 있어야 한다
folio semester add 2024 credited --source "군 복무" --credited-hours 9 --dry-run
folio transcript add "영재고 AP" "일반물리학 및 연습 II" --code GS --number 1102 --mode pass_fail --dry-run
# 문제를 풀면 풀이 기록을 남긴다. 틀린 이유는 틀렸거나 부분 점수일 때만 남는다
folio problem solve "EC4207/Exercise 1" 3a wrong --reason concept --dry-run
# 자료에서 뽑은 문제는 묶음으로 바로 만들지 않고 `folio problem-set propose <과목>/<자료> --file <문제 JSON>`으로 제안해
# 둔다. 사용자가 앱의 문제 페이지에서 검토하고 받는다. 그림은 문제의 figures에 쪽과 칸(왼쪽 위 기준 0–1 비율)으로 적고,
# 소문제들이 함께 딸린 지문과 그 그림은 --groups <지문 JSON>으로 준다. 글은 LaTeX 본문 원문(\textbf, enumerate, $…$)이고 그림을
# 글로 풀어 쓰지 않는다
# 어느 단원이 준비됐고 어떤 오답이 남았는지는 공부 상태로 본다. 판정을 고칠 때는 --json의 attempts에서 ID를 찾는다
folio study show EC4207 --dry-run
# 시험 공부 계획은 시험 범위의 정리 노트(topic)를 공부 기간에 이름 순서로 놓는다. 항목은 "<노트> <단계>"(정독, 증명, 문제풀이)이고
# exam show로 본다. 기간을 바꾸면 다시 놓이고, 끝낸 항목과 사용자가 옮긴 항목은 그대로다
folio exam plan make EC4207/기말고사 --start 2026-11-28 --end 2026-12-04 --dry-run
# 미루기는 그 항목만 다음 날로 옮기고, 앞당기기는 오늘로 가져온다. 끝낸 항목은 plan-check로 표시한다
folio exam plan postpone EC4207/기말고사 "교재 3장 다시 읽기" --dry-run
```

노트를 쓰거나 그림(SVG), 위젯을 넣기 전에 `folio note format`으로 노트 형식(수식, 콜아웃, 링크, 도식, 그림, 위젯, 그려 보기)을 읽는다. 그림은 LaTeX 교과서의 그림처럼 그린다. 그림에는 라벨만 두고 설명은 노트 본문에 쓰며, 수식은 `$…$`로, 색은 그림 스타일의 클래스(`ink`, `p-blue` …)로만 칠한다. 그림과 위젯의 화살표 촉은 직접 그리지 않고 `marker-end="url(#m-ink)"`처럼 선과 같은 색의 스타일 촉을 쓴다. 위젯 HTML에는 `<title>`로 이름을 붙인다.

## 졸업 요건과 학사편람

- `folio requirement check --json`은 졸업 요건 화면의 알림을 주고, 정할 것이 있으면 종료 코드 4다. `folio requirement check <과목 또는 강의 코드>`는 그 과목의 분류와 이중 계산 여부를 보여 준다.
- 새 학사편람이 나오면(매년 한 번) 그해 분류 표를 넣는다.
  1. 편람 PDF에서 HUS, PPE처럼 표로만 가릴 수 있는 분류의 과목 코드 표를 찾아, 사용자가 들었거나 들을 과목 코드부터 옮긴다.
  2. `{"year": 2027, "source": "<편람 파일 이름과 쪽>", "areas": {"HS2734": "PPE"}}` 형식의 JSON으로 저장한다. 값은 `folio catalog show`의 분류 이름과 같아야 한다. 실제 학업 데이터라 저장소에 넣지 않는다.
  3. `folio import handbook <파일> --dry-run`을 사용자에게 보여 주고, 승인받으면 `--accept`로 적용한다. 같은 해 표는 새 표로 바뀐다.
- 과목은 들은 해의 편람으로만 가리므로 지난 해 표는 고치지 않는다. 졸업 요건 표와 이중 계산 상한은 학번 기준이라, 학칙이 바뀌었을 때만 `folio import requirements --dry-run`으로 보여 주고 승인받아 고친다.

## 명령 찾기

- `folio help <하고 싶은 일>`(`--json`)이 맞는 명령, 옵션, 예시를 순위대로 보여 준다. `folio <대상> --help`는 사람이 읽는 도움말이다.
- `folio help --json`은 모든 명령, `folio actions --schema`는 모든 액션의 입력 형식(JSON Schema)이다.
- `folio run <액션> --input '<JSON>'`은 옵션으로 쓰기 어려운 입력에 쓴다. 바꾸는 액션(`set`, `rename`, `policy`, `wrap-up`)에는 바꿀 필드만 주고, `null`이면 지운다.

```sh
folio help 과제 마감 바꾸기
folio help 단원 순서 바꾸기 --json
folio run assignment set --input '{"course":"EC4207","assignment":"HW3","memo":"3번 질문함"}' --dry-run
```
