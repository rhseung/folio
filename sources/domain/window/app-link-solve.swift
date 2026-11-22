import FolioCore
import Foundation

extension AppLink {
    // 풀기 화면(`folio://course/<ID>/solve?…`)이 풀 문제를 고르는 값이다. 주소에 담아야 창의 기록으로 돌아왔을 때 같은 문제를 같은
    // 모드로 다시 연다. 모두 비면 과목 전체에서 고르기부터 시작한다.
    public struct Solve: Hashable, Sendable {
        // 풀기를 열 때마다 새로 받는 값이다. 같은 단원을 다시 풀면 새 풀기이고, 기록으로 돌아오면 그 풀기의 답과 판정을 다시 보인다.
        public var run: UUID?
        public var units: [UUID]
        public var set: UUID?
        public var problems: [UUID]
        // 계획 항목에서 열면 풀기를 끝낼 때 그 항목을 체크한다.
        public var plan: UUID?
        public var mode: SolveMode?
        // 계획의 섞어 풀기와 모의시험은 섞은 순서로 열고 단원 표시를 가린다.
        public var shuffled: Bool
        public var minutes: Int?

        public init(
            run: UUID? = nil, units: [UUID] = [], set: UUID? = nil, problems: [UUID] = [], plan: UUID? = nil, mode: SolveMode? = nil,
            shuffled: Bool = false, minutes: Int? = nil
        ) {
            self.run = run
            self.units = units
            self.set = set
            self.problems = problems
            self.plan = plan
            self.mode = mode
            self.shuffled = shuffled
            self.minutes = minutes
        }

        // 순서를 고정해 같은 풀기가 늘 같은 주소가 되게 한다. 창의 기록은 주소로 걸음을 가른다.
        var query: String {
            var items: [String] = []
            func ids(_ name: String, _ list: [UUID]) {
                if !list.isEmpty { items.append(name + "=" + list.map(\.uuidString).joined(separator: ",")) }
            }
            if let run { items.append("run=\(run.uuidString)") }
            ids("units", units)
            if let set { items.append("set=\(set.uuidString)") }
            ids("problems", problems)
            if let plan { items.append("plan=\(plan.uuidString)") }
            if let mode { items.append("mode=\(mode.rawValue)") }
            if shuffled { items.append("shuffled=1") }
            if let minutes { items.append("minutes=\(minutes)") }
            return items.joined(separator: "&")
        }

        // 모르는 키와 읽지 못한 값은 버린다. 손으로 고친 주소도 열 수 있게 하기 위해서다.
        init(query: Substring) {
            self.init()
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let value = parts[1]
                let list = value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                switch parts[0] {
                case "run": run = UUID(uuidString: value)
                case "units": units = list
                case "set": set = UUID(uuidString: value)
                case "problems": problems = list
                case "plan": plan = UUID(uuidString: value)
                case "mode": mode = SolveMode(rawValue: value)
                case "shuffled": shuffled = value == "1"
                case "minutes": minutes = Int(value).flatMap { $0 > 0 ? $0 : nil }
                default: continue
                }
            }
        }
    }

    public static func solve(_ course: UUID, _ solve: Solve) -> AppLink {
        AppLink(kind: .course, id: course, page: .solve, solve: solve, anchor: nil)
    }
}
