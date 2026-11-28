import FolioCore
import FolioDomain
import Foundation
import Testing

struct CardMaterialTests {
    @Test func pagesSplitIntoLectureAndTextbookByFolder() {
        var course = PlanCourse()
        let slides = Material(device: course.device, at: course.made, path: "Lectures/05_Matchings.pdf", status: .classified)
        let book = Material(device: course.device, at: course.made, path: "Textbooks/West.pdf", status: .classified)
        course.hall.lecturePages = [
            UnitPages(materialId: slides.id, firstPage: 9, lastPage: 13), UnitPages(materialId: book.id, firstPage: 220, lastPage: 228),
        ]
        course.paths.lecturePages = [UnitPages(materialId: slides.id, firstPage: 14, lastPage: 20)]
        course.coloring.lecturePages = [UnitPages(materialId: UUID(), firstPage: 1, lastPage: 2)]
        var file = course.file
        file.materials = [slides, book]

        #expect(file.cardPages(.note, units: [course.hall.id]).isEmpty)
        #expect(
            file.cardPages(.lecture, units: [course.hall.id]) == [
                LecturePages(path: slides.path, first: 9, last: 13, materialId: slides.id)
            ])
        #expect(
            file.cardPages(.textbook, units: [course.hall.id]) == [
                LecturePages(path: book.path, first: 220, last: 228, materialId: book.id)
            ])
        // 상위 단원에 이은 노트는 하위 단원의 구간까지 읽는다. 없는 파일의 구간은 뺀다.
        #expect(file.cardPages(.lecture, units: [course.matching.id]).map(\.first) == [9, 14])
        #expect(file.cardPages(.lecture, units: [course.coloring.id]).isEmpty)
    }
}
