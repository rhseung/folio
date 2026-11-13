import FolioDomain
import Foundation
import PDFKit

struct ClassWrapUpAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    let viewed: [SessionMaterial]
}

extension Workspace {
    func askWrapUp(after recording: Recording, course id: UUID) {
        guard let file = course(id)?.file, let session = file.sessions.first(where: { $0.id == recording.sessionId }), !session.isCancelled,
            !(session.isWrappedUp && file.wrapUpGaps(of: session, recorded: true).isEmpty)
        else { return }
        wrapUpAsk = ClassWrapUpAsk(course: id, session: session.id, viewed: file.viewedPages(of: session, including: recording))
    }

    func pageCount(of material: FolioDomain.Material, course id: UUID) async -> Int? {
        guard !material.isFolder, MaterialFormat(path: material.path) == .pdf, let url = try? await download(material, course: id) else {
            return nil
        }
        return await Task.detached { PDFDocument(url: url)?.pageCount }.value
    }
}
