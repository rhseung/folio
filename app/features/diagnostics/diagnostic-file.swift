import FolioDomain
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(export: DiagnosticExport) {
        data = (try? export.data()) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
