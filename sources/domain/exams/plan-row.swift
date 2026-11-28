import FolioCore
import Foundation

// 계획의 한 줄이다. 정리 노트 하나가 한 줄이고 그날 할 단계가 그 줄의 칩이다. 단계마다 한 줄이면 하루가 노트 수의 세 배로 길어진다.
public struct PlanRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        // 과목의 오답을 다시 푼 진행이다. 저장하는 항목이 아니라 풀이 기록에서 계산한 줄이다.
        case wrong(PlanProgress)
        case makeNote(unit: UUID)
        case note(UUID)
        case mock
        case custom

        public var isMakeNote: Bool { if case .makeNote = self { true } else { false } }
        public var isNote: Bool { if case .note = self { true } else { false } }

        // 오늘의 차례다. 어제 오답을 고친 뒤에 새 것을 하고, 정리 노트가 있어야 그 노트를 공부한다.
        var rank: Int {
            switch self {
            case .wrong: 0
            case .makeNote: 1
            case .note: 2
            case .mock: 3
            case .custom: 4
            }
        }
    }

    public struct Step: Sendable, Equatable, Identifiable {
        public var item: UUID
        public var stage: PlanStage?
        public var progress: PlanProgress
        public var id: UUID { item }
        public var isDone: Bool { progress.isDone }

        public init(item: UUID, stage: PlanStage?, progress: PlanProgress) {
            self.item = item
            self.stage = stage
            self.progress = progress
        }
    }

    public var id: String
    public var courseId: UUID
    public var examId: UUID?
    public var kind: Kind
    public var title: String
    // 정리 노트를 만들 단원의 이름이다. 다른 줄은 제목이 대상을 말한다.
    public var subject: String?
    public var day: LocalDate
    // 밀린 줄이 원래 있던 날이다.
    public var lateFrom: LocalDate?
    public var steps: [Step]

    public init(
        id: String, courseId: UUID, examId: UUID?, kind: Kind, title: String, subject: String?, day: LocalDate, lateFrom: LocalDate?,
        steps: [Step]
    ) {
        self.id = id
        self.courseId = courseId
        self.examId = examId
        self.kind = kind
        self.title = title
        self.subject = subject
        self.day = day
        self.lateFrom = lateFrom
        self.steps = steps
    }

    public var isLate: Bool { lateFrom != nil }
    public var isDone: Bool {
        if case .wrong(let progress) = kind { return progress.isDone }
        return !steps.isEmpty && steps.allSatisfy(\.isDone)
    }

    // 미루기, 앞당기기, 날짜 고르기가 옮기는 항목이다. 끝낸 단계는 그날에 두고, 하다 만 단계는 한 만큼 찬 채로 옮긴다.
    public var open: [UUID] { steps.filter { !$0.isDone }.map(\.item) }

    public var doneSteps: Int { steps.count(where: \.isDone) }

    // 단계를 누르면 여는 곳이다. 모의고사와 어제 오답은 풀기를 열므로 여기서 정하지 않는다.
    public func link(for stage: PlanStage?) -> AppLink? {
        switch kind {
        case .note(let note):
            // 증명과 문제풀이는 문제집으로 푼다. 줄의 이름을 누르면 노트를 연다.
            if let stage, stage != .read { return .course(courseId, page: .problems) }
            return AppLink(.note, note)
        case .makeNote(let unit): return AppLink(.unit, unit)
        case .wrong, .mock, .custom: return nil
        }
    }

    public func commands(today: LocalDate) -> [PlanItemMenuCommand] {
        guard examId != nil else { return [] }
        var commands: [PlanItemMenuCommand] = []
        if !open.isEmpty {
            if day > today { commands.append(.advance) }
            commands += [.postpone, .pickDay]
        }
        commands += [.done(isDone), .remove]
        return commands.inMenuOrder()
    }
}
