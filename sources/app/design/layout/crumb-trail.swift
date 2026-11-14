import FolioDomain
import SwiftUI

@MainActor @Observable final class CrumbTrail {
    private var levels: [Int: (owner: UUID, crumb: Crumb)] = [:]
    var crumbs: [Crumb] { levels.keys.sorted().compactMap { levels[$0]?.crumb } }

    func set(_ crumb: Crumb, level: Int, owner: UUID) { levels[level] = (owner, crumb) }
    // 페이지를 바꾸면 새 페이지가 옛 페이지가 사라지기 전에 나타나므로, 자기가 둔 단계만 지운다.
    func clear(level: Int, owner: UUID) { if levels[level]?.owner == owner { levels[level] = nil } }

    private(set) var column: ColumnCommand?
    @ObservationIgnored private var columnOwner: UUID?

    func setColumn(_ command: ColumnCommand, owner: UUID) {
        columnOwner = owner
        column = command
    }

    func clearColumn(owner: UUID) {
        guard columnOwner == owner else { return }
        columnOwner = nil
        column = nil
    }

    private(set) var outline: OutlineCommand?
    @ObservationIgnored private var outlineOwner: UUID?

    func setOutline(_ command: OutlineCommand, owner: UUID) {
        outlineOwner = owner
        outline = command
    }

    func clearOutline(owner: UUID) {
        guard outlineOwner == owner else { return }
        outlineOwner = nil
        outline = nil
    }
}
