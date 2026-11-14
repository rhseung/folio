import Foundation

// MARK: Exam

public enum ExamMenuCommand: ItemCommand {
    case open
    case summary
    case addFiles
    case edit, share, remove

    public var group: MenuGroup {
        switch self {
        case .open, .summary: .open
        case .addFiles: .start
        case .edit: .edit
        case .share: .share
        case .remove: .remove
        }
    }
}

extension CourseFile {
    public func commands(for exam: Exam, host: MenuHost) -> [ExamMenuCommand] {
        var commands: [ExamMenuCommand] = host.opensItem ? [.open] : []
        commands.append(.summary)
        if exam.folder != nil { commands.append(.addFiles) }
        commands += [.edit, .share, .remove]
        return commands.inMenuOrder()
    }
}

// MARK: Exam plan item

public enum PlanItemMenuCommand: ItemCommand {
    case done(Bool)
    case remove

    public var group: MenuGroup {
        switch self {
        case .done: .state
        case .remove: .remove
        }
    }
}

extension ExamPlanItem {
    public static func commands(done: Bool) -> [PlanItemMenuCommand] { [.done(done), .remove] }
}

// MARK: Assignment

public enum AssignmentMenuCommand: ItemCommand {
    case open
    case addFiles
    case status(AssignmentStatus)
    case edit, share
    case showInFinder
    case remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .addFiles: .start
        case .status: .state
        case .edit: .edit
        case .share, .showInFinder: .share
        case .remove: .remove
        }
    }
}

extension CourseFile {
    public func commands(for assignment: Assignment, host: MenuHost, revealable: Bool) -> [AssignmentMenuCommand] {
        var commands: [AssignmentMenuCommand] = host.opensItem ? [.open] : []
        commands += [.addFiles, .status(assignment.status), .edit, .share]
        if revealable { commands.append(.showInFinder) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}

// MARK: Unit

public enum UnitMenuCommand: ItemCommand {
    case open
    case review
    case skipToday
    case addCard
    case moveUp, moveDown
    case share, remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .review, .skipToday, .addCard: .start
        case .moveUp, .moveDown: .arrange
        case .share: .share
        case .remove: .remove
        }
    }
}

extension CourseFile {
    public func commands(for unit: Unit, host: MenuHost, dueToday: Bool) -> [UnitMenuCommand] {
        var commands: [UnitMenuCommand] = host.opensItem ? [.open] : []
        commands.append(.review)
        if dueToday { commands.append(.skipToday) }
        commands.append(.addCard)
        if host.orders {
            let siblings = units.filter { $0.parentId == unit.parentId }.sorted { $0.order < $1.order }
            if siblings.first?.id != unit.id { commands.append(.moveUp) }
            if siblings.last?.id != unit.id { commands.append(.moveDown) }
        }
        commands += [.share, .remove]
        return commands.inMenuOrder()
    }
}

// MARK: Note

public enum NoteMenuCommand: ItemCommand {
    case open
    case openPDF
    case build
    case review(ClassReview)
    case edit
    case move
    case share, showInFinder
    case remove

    public var group: MenuGroup {
        switch self {
        case .open, .openPDF: .open
        case .build: .start
        case .review: .state
        case .edit: .edit
        case .move: .arrange
        case .share, .showInFinder: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, builtPDF: Bool, builds: Bool, review: ClassReview?, finder: Bool) -> [NoteMenuCommand] {
        var commands: [NoteMenuCommand] = host.opensItem ? [.open] : []
        if builtPDF { commands.append(.openPDF) }
        if builds { commands.append(.build) }
        if let review, review == .writing || review == .written { commands.append(.review(review)) }
        commands += [.edit, .move, .share]
        if finder { commands.append(.showInFinder) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}

// MARK: Material

public enum MaterialMenuCommand: ItemCommand {
    case open
    case openWithDefault
    case openInEditor
    case openPDF(UUID)
    case edit
    case move
    case unlink(MenuHost)
    case share, showInFinder
    case remove
    case relink, untrack

    public var group: MenuGroup {
        switch self {
        case .open, .openWithDefault, .openInEditor, .openPDF: .open
        case .edit, .relink: .edit
        case .move, .unlink: .arrange
        case .share, .showInFinder: .share
        case .remove, .untrack: .remove
        }
    }
}

extension CourseFile {
    public func commands(for material: Material, host: MenuHost, pdf: UUID?, mac: Bool) -> [MaterialMenuCommand] {
        if material.status == .missing { return [.relink, .untrack] }
        var commands: [MaterialMenuCommand] = []
        // 폴더는 Finder로만 열 수 있고, iPadOS에는 폴더를 넘길 곳이 없다.
        if host.opensItem && (mac || !material.isFolder) { commands.append(.open) }
        if mac && !material.isFolder { commands.append(.openWithDefault) }
        if mac && material.isFolder { commands.append(.openInEditor) }
        if let pdf { commands.append(.openPDF(pdf)) }
        commands += [.edit, .move]
        switch host {
        case .exam(let exam) where material.examIds.contains(exam): commands.append(.unlink(host))
        case .unit(let unit) where material.unitIds.contains(unit): commands.append(.unlink(host))
        default: break
        }
        if !material.isFolder { commands.append(.share) }
        if mac { commands.append(.showInFinder) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}

// MARK: Course and semester

public enum CourseMenuCommand: ItemCommand {
    case open
    case record
    case edit
    case moveUp, moveDown
    case share, showInFinder

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .record: .start
        case .edit: .edit
        case .moveUp, .moveDown: .arrange
        case .share, .showInFinder: .share
        }
    }

    public static func commands(host: MenuHost, recordable: Bool, order: (index: Int, count: Int)?, finder: Bool) -> [CourseMenuCommand] {
        var commands: [CourseMenuCommand] = host.opensItem ? [.open] : []
        if recordable { commands.append(.record) }
        commands.append(.edit)
        if host.orders, let order {
            if order.index > 0 { commands.append(.moveUp) }
            if order.index < order.count - 1 { commands.append(.moveDown) }
        }
        commands.append(.share)
        if finder { commands.append(.showInFinder) }
        return commands.inMenuOrder()
    }
}

public enum SemesterMenuCommand: ItemCommand {
    case open
    case addCourse
    case fold(open: Bool)
    case share

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .addCourse: .start
        case .fold: .arrange
        case .share: .share
        }
    }

    public static func commands(host: MenuHost, addsCourse: Bool, folded: Bool?) -> [SemesterMenuCommand] {
        var commands: [SemesterMenuCommand] = host.opensItem ? [.open] : []
        if addsCourse { commands.append(.addCourse) }
        if host.orders, let folded { commands.append(.fold(open: !folded)) }
        commands.append(.share)
        return commands.inMenuOrder()
    }
}

// MARK: Grades

public enum ComponentMenuCommand: ItemCommand {
    case addScore, edit, moveUp, moveDown, remove

    public var group: MenuGroup {
        switch self {
        case .addScore: .start
        case .edit: .edit
        case .moveUp, .moveDown: .arrange
        case .remove: .remove
        }
    }

    public static func commands(addsScore: Bool, index: Int, count: Int) -> [ComponentMenuCommand] {
        var commands: [ComponentMenuCommand] = addsScore ? [.addScore] : []
        commands.append(.edit)
        if index > 0 { commands.append(.moveUp) }
        if index < count - 1 { commands.append(.moveDown) }
        commands.append(.remove)
        return commands
    }
}

public enum ScoreMenuCommand: ItemCommand {
    case counts(Bool)
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .counts: .state
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static func commands(excused: Bool) -> [ScoreMenuCommand] { [.counts(!excused), .edit, .remove] }
}

// MARK: Quiz

public enum CardMenuCommand: ItemCommand {
    case solveWrong
    case edit, share, remove

    public var group: MenuGroup {
        switch self {
        case .solveWrong: .start
        case .edit: .edit
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(solvesWrong: Bool) -> [CardMenuCommand] {
        (solvesWrong ? [.solveWrong] : []) + [.edit, .share, .remove]
    }
}

public enum ProblemSetMenuCommand: ItemCommand {
    case openSheet, openSolution, share, remove

    public var group: MenuGroup {
        switch self {
        case .openSheet, .openSolution: .open
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(hasSheet: Bool, hasSolution: Bool) -> [ProblemSetMenuCommand] {
        (hasSheet ? [.openSheet] : []) + (hasSolution ? [.openSolution] : []) + [.share, .remove]
    }
}

public enum ProblemMenuCommand: ItemCommand {
    case openSheet
    case record
    case units

    public var group: MenuGroup {
        switch self {
        case .openSheet: .open
        case .record: .start
        case .units: .state
        }
    }

    public static func commands(hasSheet: Bool, hasUnits: Bool) -> [ProblemMenuCommand] {
        (hasSheet ? [.openSheet] : []) + [.record] + (hasUnits ? [.units] : [])
    }
}

// MARK: Recording

public enum RecordingMenuCommand: ItemCommand {
    case open
    case transcribe
    case share
    case copyTranscript
    case remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .transcribe: .start
        case .share, .copyTranscript: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, transcribes: Bool, hasTranscript: Bool) -> [RecordingMenuCommand] {
        var commands: [RecordingMenuCommand] = host.opensItem ? [.open] : []
        if transcribes { commands.append(.transcribe) }
        commands.append(.share)
        if hasTranscript { commands.append(.copyTranscript) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}

// MARK: People, codes, requirements

public enum PersonMenuCommand: ItemCommand {
    case open, mail, share, remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .mail: .start
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, hasMail: Bool) -> [PersonMenuCommand] {
        (host.opensItem ? [.open] : []) + (hasMail ? [.mail] : []) + [.share, .remove]
    }
}

public enum CodeMenuCommand: ItemCommand {
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static var commands: [CodeMenuCommand] { [.edit, .remove] }
}

public enum RequirementMenuCommand: ItemCommand {
    case showCourses
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .showCourses: .open
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static var commands: [RequirementMenuCommand] { [.showCourses, .edit, .remove] }
}
