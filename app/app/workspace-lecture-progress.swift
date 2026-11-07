import FolioDomain
import Foundation
import PDFKit

/// A class whose recording just stopped, to be asked to wrap up. The window that stopped it takes it
/// (`ClassWrapUpPrompt`), so a second window doesn't ask again.
struct ClassWrapUpAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    /// The pages the class's recordings stayed on, which fill the end of each file's range.
    let viewed: [SessionMaterial]
}

extension Workspace {
    /// Asked at once, before the audio is compressed: that takes a while, and the class has only just ended. Not asked
    /// of a class wrapped up already with nothing missing: a second recording of it has nothing to add.
    func askWrapUp(after recording: Recording, course id: UUID) {
        guard let file = course(id)?.file, let session = file.sessions.first(where: { $0.id == recording.sessionId }), !session.isCancelled,
              !(session.isWrappedUp && file.wrapUpGaps(of: session, recorded: true).isEmpty) else { return }
        wrapUpAsk = ClassWrapUpAsk(course: id, session: session.id, viewed: file.viewedPages(of: session, including: recording))
    }

    /// A PDF's page count, downloaded first if iCloud holds only a placeholder. Nil for anything else.
    func pageCount(of material: FolioDomain.Material, course id: UUID) async -> Int? {
        guard !material.isFolder, MaterialFormat(path: material.path) == .pdf, let url = try? await download(material, course: id) else { return nil }
        return await Task.detached { PDFDocument(url: url)?.pageCount }.value
    }
}
