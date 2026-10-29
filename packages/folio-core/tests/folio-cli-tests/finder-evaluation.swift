@testable import FolioCLI
import Foundation
import FoundationModels
import Testing

/// `folio help <자연어>` measured on fixed requests. Prints top-1, top-3 and MRR; run with `swift test --filter
/// FinderEvaluation` after changing phrases or synonyms, with FOLIO_EVAL_MODEL=1 to add the on-device rerank. The scores assert nothing, so a worse run never fails CI.
/// Chosen over the old hand-weighted matcher (held-out top-1 22%), BM25 alone (17%) and with synonyms only (30%);
/// the on-device rerank adds about 14 points but costs ~0.8 s and needs Apple Intelligence, so it stays here.
struct FinderEvaluation {
    /// Requests and the commands that answer them. Mixed on purpose: the synonym table's own words, paraphrases,
    /// casual speech, English words, and typos.
    static let cases: [(String, [String])] = [
        ("과제 마감 바꾸기", ["assignment set"]), ("할 일 추가", ["assignment add", "exam plan add"]), ("결석 표시", ["attendance set"]),
        ("노트 만들어 줘", ["note add", "session note"]), ("중간고사 범위 넣기", ["exam scope"]), ("점수 기록", ["score add"]),
        ("카드 지우기", ["quiz rm"]), ("백업 되돌리기", ["backup restore"]), ("단원 순서 바꾸기", ["unit move"]),
        ("과제 제출했어", ["assignment status"]), ("회차 휴강", ["session set"]),
        // Paraphrase and casual speech.
        ("숙제 언제까지야", ["assignment show", "assignment list"]), ("HW3 기한 연장됐어", ["assignment set"]),
        ("오늘 뭐 해야 돼", ["today"]), ("이번 학기 학점", ["transcript show", "gpa"]), ("내 평점 얼마야", ["gpa"]),
        ("졸업까지 몇 학점 남았지", ["requirement show"]), ("오늘 수업 빠졌어", ["attendance set"]), ("지각했어", ["attendance set"]),
        ("보강 수업 생겼어", ["session add"]), ("강의자료 pdf 수업에 연결", ["material link"]), ("파일 이름 바꾸기", ["material mv"]),
        ("새 파일 등록", ["material track"]), ("다운받은 pdf 과목에 넣기", ["material import"]), ("복습했어", ["review record"]),
        ("이 단원 복습 안 해도 돼", ["review skip"]), ("퀴즈 맞았어", ["quiz record"]), ("문제 풀었어", ["problem-set record"]),
        ("시험 날짜 바꾸기", ["exam set"]), ("기말고사 추가", ["exam add"]), ("시험 공부 계획 세우기", ["exam plan add"]),
        ("계획 하나 끝냈어", ["exam plan-check"]), ("성적 비율 바꾸기", ["component set"]), ("퀴즈 최저 점수 하나 빼기", ["component policy"]),
        ("과목 색 바꾸기", ["course set"]), ("교수님 이름 넣기", ["course set"]), ("새 학기 만들기", ["semester add"]),
        ("과목 추가", ["course add"]), ("노트 내용 고치기", ["note write"]), ("행렬식 정리 어디 있지", ["search"]),
        ("폴더 정리", ["cleanup plan"]), ("폴더 구조 검사", ["check"]), ("노션에서 가져오기", ["import notion"]),
        ("캘린더 시험 일정 가져오기", ["import exams"]), ("하루 시작 시간 설정", ["settings set"]), ("성적 보이게 해줘", ["unlock"]),
        ("단원 이름 바꾸기", ["unit set"]), ("강의 회차 목록", ["session list"]),
        // English words and typos.
        ("score 고치기", ["score set"]), ("assignment 지워", ["assignment rm"]), ("과재 추가", ["assignment add"]), ("슈업 목록", ["session list"]),
    ]

    /// Written after `Finder.phrases`, in words chosen to differ from them, so phrases fitted to `cases` can't flatter a method here.
    static let heldOut: [(String, [String])] = [
        ("레포트 내는 날 미뤄졌어", ["assignment set"]), ("과제 다 냈음", ["assignment status"]), ("어제 수업 못 감", ["attendance set"]),
        ("다음 주 월요일 보충수업 잡혔어", ["session add"]), ("이번 주 목요일 수업 없대", ["session set"]), ("중간 범위가 3장까지래", ["exam scope"]),
        ("퀴즈 몇 점 맞았는지 적기", ["score add"]), ("실험 보고서 점수 틀리게 넣었어", ["score set"]), ("기말 몇 시에 어디서 봐", ["exam show"]),
        ("시험 언제 있지", ["exam list"]), ("챕터 하나 새로", ["unit add"]), ("강의 슬라이드 새로 올라온 거 등록", ["material track"]),
        ("책 pdf 다른 폴더로 옮기기", ["material mv"]), ("이 카드 틀렸어", ["quiz record"]), ("연습문제 3번 못 풀었어", ["problem-set record"]),
        ("공부한 거 기록", ["review record"]), ("전체 성적 보여줘", ["transcript list"]), ("전공 평점", ["gpa"]),
        ("복수전공 추가", ["requirement set"]), ("개강일 바꾸기", ["semester set"]), ("학점 3으로 수정", ["course set"]),
        ("알림 시간 바꾸기", ["settings set"]), ("그래프 이론 필기 어디", ["search"]),
    ]

    typealias Method = (String) async throws -> [String]

    /// Written before the second round of phrase work and kept out of it: its failures are never read to fit phrases,
    /// so its score is the honest one. Add a fresh set before the next round rather than tuning to this one.
    static let fresh: [(String, [String])] = [
        ("수학 숙제 하나 더 생겼어", ["assignment add"]), ("HW2 채점 끝났대", ["assignment status"]),
        ("출석 처리 잘못됐어 출석으로 바꿔", ["attendance set"]), ("3주차 2번째 수업 지워", ["session rm"]), ("이번 수업 필기 열어줘", ["session note"]),
        ("트리 단원을 그래프 단원 밑으로", ["unit move"]), ("중간고사 장소 바뀜", ["exam set"]), ("기말 범위에서 매칭 빼줘", ["exam scope"]),
        ("시험 대비 노트 만들기", ["exam summary"]), ("과제 목록 보여줘", ["assignment list"]), ("과제 비중 20퍼로", ["component set"]),
        ("중간 몇 점이었지", ["score list"]), ("B+ 받았어 성적 넣어", ["course set"]), ("지난 학기 성적표", ["transcript show"]),
        ("졸업 요건 채웠나", ["requirement show"]), ("이번 주 복습 할 거", ["today"]), ("카드 새로 만들자", ["quiz add"]),
        ("강의자료 목록", ["material list"]), ("필요 없는 파일 추적 끄기", ["material untrack"]), ("노트 지워줘", ["note rm"]),
        ("다음 학기 등록", ["semester add"]), ("과목 이름 잘못 썼어", ["course rename"]), ("복습 간격 늘리기", ["settings set"]),
        ("오늘 백업 해둬", ["backup create"]), ("폴더 이상한 데 없나", ["check"]),
    ]

    @Test func compareMethods() async throws {
        let shipped: Method = { Finder.find($0, limit: 10).map { $0.command.replacing("folio ", with: "") } }
        var methods: [(String, Method)] = [("BM25+이럴 때 (folio help)", shipped)]
        // A model call per request takes a minute and a half in all, too slow for every test run.
        if ProcessInfo.processInfo.environment["FOLIO_EVAL_MODEL"] != nil, SystemLanguageModel.default.isAvailable { methods.append(("+기기 안 모델 재정렬", Rerank(Finder.entries(), first: shipped).search)) }
        for (title, cases) in [("기존 케이스", Self.cases), ("1차 새 케이스", Self.heldOut), ("2차 새 케이스 (다듬기에 안 씀)", Self.fresh)] {
            try await measure(title, cases, methods)
        }
    }

    @Test func everyCommandHasPhrases() {
        let paths = Set(Finder.entries().map { $0.path.joined(separator: " ") })
        #expect(paths.subtracting(Finder.phrases.keys).sorted() == [], "add 이럴 때 phrases in Finder.phrases")
        #expect(Set(Finder.phrases.keys).subtracting(paths).sorted() == [], "phrases for a command that no longer exists")
    }

    func measure(_ title: String, _ cases: [(String, [String])], _ methods: [(String, Method)]) async throws {
        var report = ["방법                   1위   3위 안   MRR"]
        var misses: [String] = []
        for (name, method) in methods {
            var top1 = 0, top3 = 0, rr = 0.0
            for (request, answers) in cases {
                let ranked = try await method(request)
                let rank = ranked.firstIndex { answers.contains($0) }
                if rank == 0 { top1 += 1 }
                if let rank, rank < 3 { top3 += 1 }
                rr += rank.map { 1 / Double($0 + 1) } ?? 0
                if rank != 0 { misses.append("\(name) | \(request) → \(ranked.prefix(3).joined(separator: ", ")) (정답 \(answers[0]))") }
            }
            let n = Double(cases.count)
            report.append(name.padding(toLength: 22, withPad: " ", startingAt: 0)
                          + String(format: " %3.0f%%   %3.0f%%   %.2f", Double(top1) / n * 100, Double(top3) / n * 100, rr / n))
        }
        print((["", "\(title) \(cases.count)개"] + report + ["", "1위를 놓친 요청"] + misses).joined(separator: "\n"))
    }
}

/// Apple's on-device model reorders the first method's top ten; it can only pick among them, so a command the first
/// method missed stays missed. Greedy sampling, so a run is repeatable.
struct Rerank {
    let abstracts: [String: String]
    let first: FinderEvaluation.Method

    init(_ entries: [Finder.Entry], first: @escaping FinderEvaluation.Method) {
        abstracts = Dictionary(entries.map { ($0.path.joined(separator: " "), $0.abstract) }) { a, _ in a }
        self.first = first
    }

    @Generable struct Ranking {
        @Guide(description: "요청을 처리하는 후보의 번호. 가장 맞는 것부터 최대 3개")
        var numbers: [Int]
    }

    func search(_ request: String) async throws -> [String] {
        let candidates = try await first(request)
        guard candidates.count > 1 else { return candidates }
        let list = candidates.enumerated().map { "\($0.offset + 1). folio \($0.element) — \(abstracts[$0.element] ?? "")" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            학생이 수업, 과제, 시험, 성적을 관리하는 명령줄 도구 folio의 명령을 고른다. \
            사용자의 요청을 실제로 처리하는 명령을 후보 중에서 고른다. 요청의 동사(했어, 바꾸기, 보여줘)가 무엇을 하려는지 본다.
            """)
        let picked = try await session.respond(to: "요청: \(request)\n\n후보:\n\(list)", generating: Ranking.self,
                                               options: GenerationOptions(sampling: .greedy)).content.numbers
        let chosen = picked.compactMap { candidates.indices.contains($0 - 1) ? candidates[$0 - 1] : nil }
        var seen = Set<String>()
        return (chosen + candidates).filter { seen.insert($0).inserted }
    }
}
