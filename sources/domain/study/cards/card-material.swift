import Foundation

// Claude가 카드를 만들 때 읽는 재료다. 정리 노트는 노트 본문이고, 렉처 쪽과 교재는 단원에 나눠 둔 쪽 구간이다.
public enum CardMaterial: String, Codable, Sendable, CaseIterable {
    case note, lecture, textbook
}

extension CourseFile {
    // 단원들과 그 하위 단원에 나눠 둔 쪽 구간 가운데 이 재료에 드는 것이다. 교재 폴더의 파일이면 교재이고 그 밖의 파일은 렉처다.
    // 정리 노트는 쪽 구간이 아니라 노트 본문이 재료라서 비어 있다.
    public func cardPages(_ material: CardMaterial, units: [UUID]) -> [LecturePages] {
        guard material != .note else { return [] }
        let covered = units.reduce(into: Set<UUID>()) { $0.formUnion(UnitTree.subtree(of: $1, in: self.units)) }
        let ranges = UnitTree.outline(self.units).map(\.unit).filter { covered.contains($0.id) }.flatMap(\.lecturePages)
        return ranges.compactMap { range in
            guard let file = materials.first(where: { $0.id == range.materialId }) else { return nil }
            guard (MaterialRole(path: file.path) == .textbook) == (material == .textbook) else { return nil }
            return LecturePages(path: file.path, first: range.pages.lowerBound, last: range.pages.upperBound, materialId: file.id)
        }
    }
}
