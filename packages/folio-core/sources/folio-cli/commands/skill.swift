import ArgumentParser
import Foundation

/// The binary holds the only
/// copy so an agent outside the repository can install it; the repository's `.claude/skills/folio/SKILL.md` is a test-
/// checked copy of this text.
enum Skill {
    static let text = #"""
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
- 셸 없이 MCP만 쓰는 클라이언트는 `folio mcp`를 MCP 서버로 붙인다(`claude mcp add folio -- folio mcp`). 도구 이름은 명령의 공백을 `_`로 바꾼 것이고(`exam add` → `exam_add`), 입력은 `folio run`과 같다. 위 안전 규칙은 MCP 도구에도 같다.

## 안전

1. 쓰기 전에 먼저 `--dry-run`으로 바뀔 것을 보고, 사용자에게 보여 준다.
2. 이동, 이름 변경, 삭제, 여러 항목을 한 번에 바꾸는 명령은 확인이 필요하다. 터미널이 아니면 종료 코드 5로 멈춘다. `folio run`도 무언가를 지우거나 옮기면 같은 확인을 받는다. 사용자가 승인한 뒤에만 `--yes`를 붙여 다시 실행한다.
3. 종료 코드 3은 대상을 못 찾았거나 여러 개에 맞은 경우다. 오류에 나온 후보 중 하나를 사용자에게 확인하고 다시 실행한다.
4. 노트를 고쳐 쓸 때는 `note show --json`의 `hash`를 `note write --expect`에 넘긴다. 그사이 앱이나 다른 기기에서 바뀌었으면 종료 코드 6으로 멈추니, 다시 읽고 고친다.
5. `set` 명령에서 값을 지우려면 `none`을 준다(`--due none`). 항목 인자는 빼지 않는다. 터미널이 아니면 고를 수 없어 종료 코드 2로 끝난다.
6. 성적, GPA, 점수는 잠겨 있다. `gpa`, `transcript`, `score list`는 잠겨 있으면 사용자의 Mac에 Touch ID 창을 띄우고, 사용자가 풀지 않으면 종료 코드 5로 멈춘다. 다른 명령의 성적 칸은 `••`로 나온다. 사용자가 성적을 물었을 때만 이 명령을 쓴다. 성적을 여러 번 읽는 긴 작업이면 처음에 `folio unlock --for 1h`로 한 번 승인받는다.

## 가리키기

과목은 강의 코드(`EC4207`), 폴더 이름, 과목 이름, UUID로 가리킨다. 과목 안의 항목은 `<과목>/<항목>`이다. 회차는 `9주차-1`, 시험과 과제와 단원은 제목, 노트와 자료는 경로나 파일 이름이다. 정확히 맞는 이름이 없으면 포함하는 이름을 찾는다.

## 자주 하는 일

```sh
# 읽기
folio session list EC4207 --json
folio assignment list EC4207 --json
folio exam show EC4207/중간고사 --json
folio unit list EC4207 --json

# 과제
folio assignment add EC4207 "HW 4" --due "2026-11-11 23:59" --dry-run
folio assignment status EC4207/HW3 submitted --dry-run

# 노트
folio note add EC4207 "매칭 정리" --kind topic --dry-run
folio note link "EC4207/매칭 정리" --kind topic --unit 매칭 --dry-run

# 회차와 출석
folio session add EC4207 --date "2026-11-02 10:30" --dry-run
folio attendance set EC4207/2주차-1 absent --dry-run

# 시험
folio exam add EC4207 기말고사 --kind final --start "2026-12-14 10:00" --end "2026-12-14 12:00" --dry-run
folio exam scope EC4207/중간고사 --unit 트리 --unit 매칭 --dry-run
folio exam plan add EC4207/중간고사 --day 2026-10-19 "매칭 문제 풀기" --dry-run

# 점수
folio score add EC4207 --component 과제 --title HW2 --score 8 --max 10 --dry-run

# 인정학기와 폴더 없는 과목
folio semester add 2024 credited --credited-hours 9 --dry-run
folio transcript add "2024 credited" "군 복무 인정" --credits 9 --mode pass_fail --dry-run

# 복습
folio review record EC4207/매칭 good --start "2026-10-28 20:00" --end "2026-10-28 20:40" --dry-run
```

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
- `folio run <액션> --input '<JSON>'`: 액션 하나를 JSON 입력으로 실행한다. 명령 옵션으로 표현하기 어려운 입력에 쓴다.

```sh
folio run assignment add --input '{"course":"EC4207","title":"HW 5","due":"2026-11-18T23:59:00+09:00"}' --dry-run
```
"""#

    /// What goes on disk: the literal drops the newline before its closing delimiter.
    static var file: String { text + "\n" }
}

struct SkillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "skill", abstract: "에이전트 스킬(SKILL.md) 보기와 설치", discussion: """
        Claude Code, Codex 같은 에이전트가 folio를 쓰는 법을 담은 SKILL.md다. 대부분의 에이전트가 같은 형식을 읽는다.

        예시:
          folio skill                              SKILL.md 내용 보기
          folio skill --install ~/.claude/skills   Claude Code에 설치
          folio skill --install ~/.agents/skills --dry-run
        """)
    @OptionGroup var g: GlobalOptions
    @Option(help: ArgumentHelp("이 스킬 폴더 아래 folio/SKILL.md로 설치", valueName: "dir"), completion: .directory) var install: String?

    func run() throws {
        guard let install else { return say(Skill.text) }
        let url = URL(filePath: (install as NSString).expandingTildeInPath, directoryHint: .isDirectory).appending(path: "folio/SKILL.md")
        let old = try? String(contentsOf: url, encoding: .utf8)
        if old == Skill.file {
            return g.json ? try printJSON(["path": url.path, "status": "unchanged"]) : say("✓".styled(.green) + " 이미 최신입니다: \(url.path)")
        }
        if old != nil, !g.dryRun { try ask("\(url.path)를 새 내용으로 바꿉니다.", g) }
        if !g.dryRun {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Skill.file.utf8).write(to: url, options: .atomic)
        }
        let status = g.dryRun ? "dry-run" : old == nil ? "installed" : "updated"
        if g.json { return try printJSON(["path": url.path, "status": status]) }
        say((g.dryRun ? "미리보기".styled(.bold) + " · " : "✓".styled(.green) + " ") + (old == nil ? "설치" : "갱신") + ": \(url.path)")
    }
}
