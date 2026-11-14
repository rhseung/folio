import Foundation

extension Unit {
    var lectureMaterialIds: [UUID] {
        get { lecturePages.map(\.materialId) }
        set { lecturePages = lecturePages.filter { newValue.contains($0.materialId) } }
    }
}

extension CourseFile {
    public func unitPages(of material: UUID) -> [(unit: Unit, pages: ClosedRange<Int>)] {
        UnitTree.outline(units).flatMap { item in
            item.unit.lecturePages.filter { $0.materialId == material }.map { (item.unit, $0.pages) }
        }
    }

    public func isSplit(_ material: UUID) -> Bool {
        units.contains { $0.lecturePages.contains { $0.materialId == material } }
    }

    public func lectureZones(of material: UUID, pageCount: Int?) -> [LectureZone] {
        let held = unitPages(of: material)
        guard let reach = held.map(\.pages.upperBound).max() else { return [] }
        let end = pageCount ?? reach
        guard end > 0 else { return [] }

        var zones: [LectureZone] = []
        for page in 1...end {
            var here: [UUID] = []
            for (unit, pages) in held where pages.contains(page) && !here.contains(unit.id) { here.append(unit.id) }
            if let last = zones.last, last.units == here {
                zones[zones.count - 1].lastPage = page
            } else {
                zones.append(LectureZone(firstPage: page, lastPage: page, units: here))
            }
        }
        return zones
    }

    public func units(in material: UUID, meeting pages: ClosedRange<Int>) -> [Unit] {
        let met = unitPages(of: material).filter { $0.pages.overlaps(pages) }
        var seen: Set<UUID> = []
        // 안정 정렬이어야 같은 쪽에서 시작하는 단원이 목차 순서를 지킨다.
        return met.enumerated().sorted { ($0.element.pages.lowerBound, $0.offset) < ($1.element.pages.lowerBound, $1.offset) }
            .map(\.element.unit).filter { seen.insert($0.id).inserted }
    }

    public func splitProgress(of session: Session) -> (material: UUID, pages: ClosedRange<Int>)? {
        session.materials.lazy.compactMap { link in link.pages.flatMap { self.isSplit(link.materialId) ? (link.materialId, $0) : nil } }
            .first
    }

    public func pages(of unit: UUID, in material: UUID) -> ClosedRange<Int>? {
        let held = units.first { $0.id == unit }?.lecturePages.filter { $0.materialId == material } ?? []
        guard let lo = held.map(\.pages.lowerBound).min(), let hi = held.map(\.pages.upperBound).max() else { return nil }
        return lo...hi
    }

    public func sectionLabel(of material: UUID, pages: ClosedRange<Int>) -> String? {
        let reached = units(in: material, meeting: pages)
        guard let first = reached.first, let last = reached.last else { return nil }
        return first.id == last.id ? first.title : "\(first.title)–\(last.title)"
    }
}

extension CourseFile {
    public mutating func split(_ material: UUID, into cuts: [LectureCut], device: DeviceID, now: Date) {
        for i in units.indices where units[i].lecturePages.contains(where: { $0.materialId == material }) {
            units[i].lecturePages.removeAll { $0.materialId == material }
            units[i].touch(by: device, at: now)
        }

        for cut in cuts {
            if !units.contains(where: { $0.id == cut.unit }) {
                guard let title = cut.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
                let parent = cut.parent.flatMap { p in units.contains { $0.id == p } ? p : nil }
                units.append(
                    Unit(
                        id: cut.unit, device: device, at: now, title: title, order: UnitTree.nextOrder(under: parent, in: units),
                        parentId: parent))
            }
            guard let u = units.firstIndex(where: { $0.id == cut.unit }) else { continue }
            units[u].lecturePages.append(UnitPages(materialId: material, firstPage: cut.firstPage, lastPage: cut.lastPage))
            units[u].touch(by: device, at: now)
        }
    }
}
