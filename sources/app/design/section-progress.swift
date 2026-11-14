import FolioDomain
import SwiftUI

struct SectionProgress: View {
    let file: CourseFile
    let material: UUID
    let range: ClosedRange<Int>
    var labeled = true

    var body: some View {
        let sections = PageRangeField.Section.list(file, material: material, pageCount: nil)
        HStack(spacing: Theme.Space.tight) {
            SectionStrip(sections: sections, pages: max(sections.last?.pages.upperBound ?? 0, range.upperBound), range: range)
            if labeled, let label = file.sectionLabel(of: material, pages: range) {
                Text(label).lineLimit(1).truncationMode(.tail)
            }
        }
    }
}
