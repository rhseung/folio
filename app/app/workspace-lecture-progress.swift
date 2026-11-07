import FolioDomain
import Foundation
import PDFKit

/// A class whose recording just stopped, to be asked how far it went. The window that stopped it takes it
/// (`SessionProgressPrompt`), so a second window doesn't ask again.
struct SessionProgressAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    /// The pages the class's recordings stayed on, which fill the end of each file's range.
    let viewed: [SessionMaterial]
}

extension Workspace {
    /// Asked at once, before the audio is compressed: that takes a while, and the class has only just ended. Only a
    /// course with lecture files has progress to ask about.
    func askProgress(after recording: Recording, course id: UUID) {
        guard let file = course(id)?.file, let session = file.sessions.first(where: { $0.id == recording.sessionId }),
              !file.lectureFiles.isEmpty else { return }
        progressAsk = SessionProgressAsk(course: id, session: session.id, viewed: file.viewedPages(of: session, including: recording))
    }

    /// A PDF's page count, downloaded first if iCloud holds only a placeholder. Nil for anything else.
    func pageCount(of material: FolioDomain.Material, course id: UUID) async -> Int? {
        guard !material.isFolder, MaterialFormat(path: material.path) == .pdf, let url = try? await download(material, course: id) else { return nil }
        return await Task.detached { PDFDocument(url: url)?.pageCount }.value
    }
}
