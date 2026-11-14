import Foundation

extension CourseFile {
    public func commands(for exam: Exam, host: MenuHost) -> [ExamMenuCommand] {
        var commands: [ExamMenuCommand] = host.opensItem ? [.open] : []
        commands.append(.summary)
        if exam.folder != nil { commands.append(.addFiles) }
        commands += [.edit, .share, .remove]
        return commands.inMenuOrder()
    }
}

extension ExamPlanItem {
    public static func commands(done: Bool) -> [PlanItemMenuCommand] { [.done(done), .remove] }
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
