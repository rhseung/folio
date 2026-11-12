import Foundation

// The menus of every item kind but the class, which `session-menu.swift` holds (#403). Each kind lists what its menu can
// hold and which of those the data allows here; the app only names and does them. Rows for what the item doesn't have
// are left out rather than greyed, and rarely changed values stay in the item's sheet.

// MARK: Exam

public enum ExamMenuCommand: ItemCommand {
    case open
    /// The summary note: opened when it exists, made from its template when not. Which of the two is a note file's
    /// fact, so the app names the row.
    case summary
    /// Files into the exam's folder, as dropping them on its card does.
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
    /// Files can be added only once the exam has a folder to take them.
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
    /// The one state an item has, checked once done.
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
    /// No sheet: an item is a day and a title, typed again rather than edited.
    public static func commands(done: Bool) -> [PlanItemMenuCommand] { [.done(done), .remove] }
}

// MARK: Assignment

public enum AssignmentMenuCommand: ItemCommand {
    case open
    case addFiles
    /// 상태 ▸, holding the status checked now.
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
    /// `revealable`: the platform has a Finder and the assignment's folder is on disk.
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
    /// Only for a unit whose review is due on the study day.
    case skipToday
    /// 카드 추가 ▸: by hand, or made by Claude.
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
    /// The unit's page is its editor (name, parent, links), so there's no 편집… row. Moving it among its siblings is
    /// offered where the units are listed in order, and only the ways it can go.
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
    /// The PDF a `.tex` note was built into.
    case openPDF
    case build
    /// A review note's one check row, 작성 완료, holding the value it toggles from.
    case review(ClassReview)
    case edit
    /// 옮기기 ▸: the other folders under `Notes`, then a new one.
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

    /// `builds`: a `.tex` note on a platform that runs TeX. `review`: the state of the class the note reviews, if it
    /// is a review note. `finder`: the platform has one.
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
    /// A folder opens in Finder on the Mac.
    case open
    case openWithDefault
    /// 편집기로 열기 ▸, for a folder (a code assignment's project).
    case openInEditor
    /// The PDF a `.tex` file is built into, shown as one row with it.
    case openPDF(UUID)
    case edit
    /// 옮기기 ▸: the other places of the course folder it may go.
    case move
    /// Letting go of the exam or unit whose screen lists it.
    case unlink(MenuHost)
    case share, showInFinder
    case remove
    /// A tracked file no longer on disk: pointing it at another, or untracking it.
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
    /// `pdf`: the `.tex` file's built PDF. `mac`: the platform has Finder and other apps to hand a file to. A missing
    /// file has only the two ways out of it.
    public func commands(for material: Material, host: MenuHost, pdf: UUID?, mac: Bool) -> [MaterialMenuCommand] {
        if material.status == .missing { return [.relink, .untrack] }
        var commands: [MaterialMenuCommand] = []
        // A folder opens nowhere but Finder; iPadOS has none to hand it to.
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
    /// While one of the course's classes is under way.
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

    /// No delete: a course folder holds a semester's files, and leaving it is done in Finder. `order` is where the
    /// course stands among the ones it is listed with, for the sidebar's moves.
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
    /// The sidebar's fold, holding whether it is open now.
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

    /// The semester's page is its editor, so there's no 편집…; a course can be added only where `addsCourse` says.
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
    /// 반영: checked while the score counts toward the grade.
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
    /// On the statistics screen: drilling the card's unit's wrong answers.
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

    /// No sheet: a set is made once from its PDF. The set opens at the problems page, so it can be shared.
    public static func commands(hasSheet: Bool, hasSolution: Bool) -> [ProblemSetMenuCommand] {
        (hasSheet ? [.openSheet] : []) + (hasSolution ? [.openSolution] : []) + [.share, .remove]
    }
}

public enum ProblemMenuCommand: ItemCommand {
    /// The problem sheet, at the problem's page when it has one.
    case openSheet
    /// 풀이 기록 ▸: adding an attempt, so not a state with a value checked.
    case record
    /// 단원 ▸: the units the problem belongs to, several checked.
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
    /// Transcribing again, which replaces the transcript.
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

    /// The person's page is their editor.
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
    /// The courses counted toward it, which a press on its figure shows too.
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
