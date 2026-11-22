import FolioDomain
import Foundation
import PDFKit

extension CourseStore {
    public func lectureText(_ pages: [LecturePages]) -> String {
        pages.compactMap { range -> String? in
            guard let data = try? CoordinatedFile.read(fileURL(range.path)), let document = PDFDocument(data: data) else { return nil }
            let count = document.pageCount
            let first = max(1, range.first ?? 1), last = min(count, range.last ?? count)
            guard first <= last else { return nil }
            return (first...last).compactMap { document.page(at: $0 - 1)?.string }.joined(separator: "\n")
        }
        .joined(separator: "\n")
    }
}

extension CourseStore {
    public func transcriptionContext(_ file: CourseFile, session: Session, recording: Recording?) -> TranscriptionContext {
        let context = file.transcriptionContext(for: session, recording: recording)
        return context.reading(lectureText(context.slides))
    }
}

extension CourseStore {
    // 쪽 제목을 읽으려고 PDF를 열므로 main actor 밖에서 부른다. 열지 못한 렉처는 뺀다.
    public func lectureOutline(_ file: CourseFile) -> LectureOutline {
        let wanted = LectureOutline.pages(of: file.units)
        let lectures = file.materials.filter { wanted[$0.id] != nil }.sorted { $0.path < $1.path }.compactMap {
            m -> LectureOutline.Lecture? in
            guard let pdf = PDFPages.open(fileURL(m.path)) else { return nil }
            let pages = (wanted[m.id] ?? []).prefix(ReadingLimit.titles).filter { $0 >= 1 && $0 <= pdf.pageCount }.map { n in
                LectureOutline.Page(number: n, title: pdf.page(at: n - 1).flatMap { PDFPages.text(of: $0, number: n).title })
            }
            return LectureOutline.Lecture(materialId: m.id, name: (m.path as NSString).lastPathComponent, pages: pages)
        }
        return LectureOutline(lectures: lectures)
    }
}
