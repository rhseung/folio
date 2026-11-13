import FolioDomain
import Foundation
import PDFKit

extension CourseStore {
    /// A missing or unreadable file reads as nothing: hints are a help, never a reason to fail a transcription.
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
    /// Slow: it reads the slides' PDFs for terms.
    public func transcriptionContext(_ file: CourseFile, session: Session, recording: Recording?) -> TranscriptionContext {
        let context = file.transcriptionContext(for: session, recording: recording)
        return context.reading(lectureText(context.slides))
    }
}
