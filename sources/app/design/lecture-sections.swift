import FolioDomain
import SwiftUI

extension PageRangeField.Section {
    static func list(_ file: CourseFile, material: UUID, pageCount: Int?) -> [Self] {
        let titles = Dictionary(file.units.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        return file.lectureZones(of: material, pageCount: pageCount).map { zone in
            Self(title: zone.units.first.flatMap { titles[$0] } ?? "", pages: zone.pages)
        }
    }
}
