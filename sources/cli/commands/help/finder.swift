import ArgumentParser
import FolioActions
import Foundation
import GRDB

enum Finder {
    struct Entry {
        var path: [String]
        var abstract: String
        var help: String
        var examples: [String]
    }

    struct Match: Encodable {
        var command: String
        var abstract: String
        var options: [String]
        var examples: [String]
        var score: Double
    }

    static let synonyms: [(String, [String])] = [
        ("할 일", ["assignment", "plan"]), ("할일", ["assignment", "plan"]), ("과제", ["assignment"]), ("숙제", ["assignment"]),
        ("마감", ["assignment", "due"]), ("제출", ["assignment", "status"]),
        ("시험", ["exam"]), ("중간", ["exam"]), ("기말", ["exam"]), ("범위", ["scope"]), ("공부 계획", ["plan"]), ("계획", ["plan"]),
        ("회차", ["session"]), ("수업", ["session"]), ("강의", ["session"]), ("휴강", ["session", "set"]), ("보강", ["session", "add"]),
        ("출석", ["attendance"]), ("결석", ["attendance"]), ("지각", ["attendance"]), ("공결", ["attendance"]),
        ("단원", ["unit"]), ("챕터", ["unit"]), ("연결", ["link"]),
        ("점수", ["score"]), ("성적 항목", ["component"]), ("비율", ["component"]), ("성적표", ["transcript"]), ("학점", ["gpa", "transcript"]),
        ("평점", ["gpa"]), ("졸업", ["requirement"]), ("잠금 해제", ["unlock"]), ("잠금 풀", ["unlock"]), ("잠그", ["lock"]),
        ("노트", ["note"]), ("메모", ["note"]), ("자료", ["material"]), ("파일", ["material"]), ("pdf", ["material"]),
        ("복습", ["review"]), ("카드", ["quiz"]), ("퀴즈 카드", ["quiz"]), ("문제", ["problem-set"]),
        ("학기", ["semester"]), ("과목", ["course"]), ("교수", ["catalog"]), ("설정", ["settings"]),
        ("백업", ["backup"]), ("되돌", ["undo", "restore"]), ("검색", ["search"]), ("찾", ["search"]), ("오늘", ["today"]),
        ("가져오", ["import"]), ("노션", ["import", "notion"]), ("캘린더", ["import", "calendar"]), ("점검", ["check"]), ("정리 도구", ["cleanup"]),
        ("추가", ["add"]), ("만들", ["add"]), ("생성", ["add"]), ("등록", ["add", "track"]), ("새", ["add"]), ("넣", ["add"]),
        ("바꾸", ["set"]), ("바꿔", ["set"]), ("수정", ["set"]), ("변경", ["set"]), ("고치", ["set"]), ("고쳐", ["set"]), ("이름", ["set", "rename"]),
        ("지우", ["rm"]), ("지워", ["rm"]), ("삭제", ["rm"]), ("제거", ["rm"]), ("없애", ["rm"]),
        ("보기", ["show", "list"]), ("보여", ["show", "list"]), ("확인", ["show", "list"]), ("조회", ["show", "list"]), ("목록", ["list"]),
        ("기록", ["record", "add"]), ("옮기", ["move"]), ("순서", ["move"]),
    ]

    static let phrases: [String: [String]] = written.merging(
        Actions.all.map { ($0.spec.command, $0.spec.phrases) }.filter { !$0.1.isEmpty },
        uniquingKeysWith: { a, b in a + b.filter { !a.contains($0) } })

    private static let written: [String: [String]] = [
        "today": ["오늘 할 일", "오늘 일정", "지금 뭐 해야", "하루 요약"],
        "add": ["빠른 추가", "한 줄로 추가", "금요일까지 과제", "말로 과제 추가"],
        "session list": ["수업 목록", "강의 목록", "회차 보기", "몇 주차"], "session show": ["수업 하나 보기", "회차 자세히"],
        "session rm": ["수업 지우기", "회차 삭제"], "unit list": ["단원 목록", "챕터 목록", "진도"], "unit show": ["단원 보기"],
        "unit move": ["단원 순서", "단원 옮기기", "하위 단원으로"],
        "exam list": ["시험 목록", "시험 언제"], "exam show": ["몇 시", "어디서", "시험 장소 보기", "시험 범위 보기", "시험 정보", "시험 시간과 장소"],
        "exam scope": ["시험 범위", "범위 넣기", "출제 범위"],
        "exam plan rm": ["공부 계획 삭제"],
        "exam plan-check": ["계획 끝냈", "계획 다 했", "계획 완료", "공부 다 함", "계획 체크"], "assignment list": ["과제 목록", "숙제 뭐 남았지", "할 일 목록"],
        "assignment show": ["과제 자세히", "과제 마감 언제", "과제 점수"],
        "score list": ["점수 보기", "받은 점수"],
        "component list": ["성적 비율 보기", "평가 항목"], "component move": ["항목 순서"],
        "component policy": ["최저 점수 빼기", "하나 빼", "최저 점수 제외", "결석 감점", "성적 규칙", "드롭"],
        "transcript list": ["전체 성적표", "모든 성적"], "transcript show": ["이번 학기 성적", "학기 성적표"],
        "requirement show": ["졸업 요건", "졸업까지 남은 학점", "이수 현황"],
        "requirement check": ["분류 확인", "졸업 요건 점검"], "gpa": ["평점", "학점 평균", "누적 학점"],
        "unlock": ["성적 보이게", "성적 보여", "성적 보기", "성적 잠금 풀기", "가린 성적"], "lock": ["성적 숨기기", "성적 가리기"],
        "quiz list": ["퀴즈 카드 보기", "암기 카드"],
        "problem-set list": ["문제 목록", "연습 문제"],
        "material list": ["자료 목록", "강의자료 보기", "파일 목록"], "material show": ["자료 정보"],
        "material read": ["자료 읽기", "pdf 읽기", "슬라이드 읽기", "렉처 읽기", "몇 쪽 내용", "쪽 그림", "교재 읽기"],
        "recording transcript": ["받아쓰기", "녹음 내용", "녹음 읽기", "수업에서 뭐라고", "강의 녹음"],
        "note list": ["노트 목록"], "note show": ["노트 보기", "노트 읽기"], "note images": ["노트 그림", "손필기 사진", "노트 사진", "필기 사진 보기"],
        "note format": ["노트 형식", "노트 문법", "콜아웃 쓰는 법", "다크 모드 색"], "note figure list": ["그림 목록", "SVG 목록"],
        "note figure show": ["그림 원문", "SVG 보기"], "note figure render": ["그림 그려 보기", "SVG 미리 보기", "다크 모드로 보기"],
        "note widget list": ["위젯 목록"], "note widget show": ["위젯 원문", "위젯 HTML 보기"],
        "note widget render": ["위젯 그려 보기", "위젯 미리 보기", "위젯 오류"],
        "search": ["어디", "찾아", "찾기", "어디 있지", "검색", "내용 찾기"],
        "link": ["링크 만들기", "링크 복사", "앱 링크", "folio 링크", "주소"], "open": ["앱에서 열기", "앱으로 열기", "화면 열기"],
        "semester list": ["학기 목록"], "semester show": ["이번 학기 정보", "개강일"],
        "course list": ["과목 목록", "수강 과목"], "course show": ["과목 정보", "과목 시간표"],
        "catalog show": ["카탈로그", "과목 코드 목록", "교수 목록"],
        "settings show": ["설정 보기"],
        "check": ["폴더 검사", "구조 확인", "문제 있나"], "cleanup plan": ["폴더 정리", "파일 정리 계획"], "backup list": ["백업 목록"],
        "actions": ["액션 목록", "커버리지 검사"], "run": ["JSON 입력으로 실행", "에이전트 실행"], "mcp": ["MCP 서버", "MCP 도구", "Claude 데스크톱에 연결"],
        "skill": ["에이전트 스킬", "스킬 설치"], "completion": ["자동 완성", "탭 완성"],
    ]

    static let allEntries = entries()

    static func entries(_ type: ParsableCommand.Type = Folio.self, path: [String] = []) -> [Entry] {
        let config = type.configuration
        // key path 대신 클로저를 쓴다. 이 메타타입의 key path는 컴파일러(SILGen)를 멈추게 한다.
        let subs = config.subcommands + config.groupedSubcommands.flatMap { $0.subcommands }
        if subs.isEmpty {
            let help = Folio.helpMessage(for: type)
            let examples = config.discussion.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("folio ") }.map { $0.replacing(/\s{2,}\S.*$/, with: "") }
            return [Entry(path: path, abstract: config.abstract, help: help, examples: examples)]
        }
        var seen: Set<String> = []
        return subs.filter { seen.insert($0._commandName).inserted }.flatMap { entries($0, path: path + [$0._commandName]) }
    }

    // BM25(SQLite FTS5)로 명령의 경로, 요약, 구절, 도움말을 10 : 5 : 8 : 1로 가중한다. 요청의 낱말과 동의어를 OR로 잇고,
    // 낱말은 접두어로 맞으므로 `과제`가 `과제를`을 찾는다.
    static func find(_ request: String, limit: Int = 5) -> [Match] {
        let text = request.lowercased().precomposedStringWithCanonicalMapping
        let words = text.split(whereSeparator: \.isWhitespace).map { w in
            String(w).replacing(/(으로|하기|하고|해줘|하는|어요|에요|을|를|이|가|은|는|에|의|로|해|기|어|아|음|대|래|야|지|냐|줘|요)$/, with: "")
        }.filter { !$0.isEmpty }
        let terms = Set(words + synonyms.filter { text.contains($0.0) }.flatMap(\.1))
        guard !terms.isEmpty else { return [] }
        let entries = allEntries
        let query = terms.sorted().map { "\"" + $0.replacing("\"", with: "\"\"") + "\"*" }.joined(separator: " OR ")
        let ranked: [(Int, Double)]
        do {
            let db = try DatabaseQueue()
            ranked = try db.write { db in
                try db.execute(sql: "CREATE VIRTUAL TABLE c USING fts5(path, abstract, phrases, body, tokenize='unicode61')")
                for e in entries {
                    let path = e.path.joined(separator: " ")
                    try db.execute(
                        sql: "INSERT INTO c VALUES (?, ?, ?, ?)",
                        arguments: [
                            path, e.abstract, (phrases[path] ?? []).joined(separator: " · "),
                            e.help + "\n" + e.examples.joined(separator: "\n"),
                        ])
                }
                // 같은 요청이 늘 같은 목록을 내도록 동점은 앞선 명령이 이긴다.
                return try Row.fetchAll(
                    db, sql: "SELECT rowid, bm25(c, 10.0, 5.0, 8.0, 1.0) AS s FROM c WHERE c MATCH ? ORDER BY s, rowid LIMIT ?",
                    arguments: [query, limit]
                ).map { ($0["rowid"] as Int, $0["s"] as Double) }
            }
        } catch {
            return []
        }
        return ranked.map { rowid, s in
            let e = entries[rowid - 1]
            var options: [String] = []
            for line in e.help.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                let l = line.lowercased()
                guard words.contains(where: { $0.count >= 2 && l.contains($0) }) || terms.contains(where: { l.contains("--\($0)") }) else {
                    continue
                }
                let option = line.trimmingCharacters(in: .whitespaces).replacing(/\s{2,}/, with: "  ")
                if !options.contains(option) { options.append(option) }
            }
            return Match(
                command: (["folio"] + e.path).joined(separator: " "), abstract: e.abstract, options: Array(options.prefix(3)),
                examples: Array(e.examples.prefix(2)), score: (-s * 100).rounded() / 100)
        }
    }

    static func print(_ request: String, json: Bool) throws {
        let matches = find(request)
        if json { return try printJSON(matches) }
        guard !matches.isEmpty else {
            warn("✗".styled(.red) + " " + String(localized: .finderNoMatch(request)))
            warn(String(localized: .finderNoMatchHint).styled(.dim))
            throw ExitCode(Exit.notFound.rawValue)
        }
        say(String(localized: .finderMatches(request)).styled(.bold))
        for m in matches {
            say("")
            say("  " + m.command.styled(.bold) + "  " + m.abstract.styled(.dim))
            for o in m.options { say("      " + o) }
            for x in m.examples { say("      " + x.styled(.green)) }
        }
        say("")
        say(String(localized: .finderMore).styled(.dim))
    }
}
