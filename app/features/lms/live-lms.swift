import FolioDomain
import FolioLMS
import Foundation
import Observation

struct LiveLMS: LMSSource {
    let client: LMSClient

    func verify(_ login: LMSCredentials) async throws {
        try await LMSClient(credentials: { login }).login()
    }

    func read(attachments: @escaping @Sendable (LMSSnapshot) -> [LMSAssignment]) async throws -> LMSSnapshot {
        try await LMSSync.read(client, at: .now, attachments: attachments)
    }

    func download(_ file: LMSFile, into folder: URL) async throws -> URL? { try await client.download(file, into: folder) }

    func download(_ attachment: LMSAttachment, into folder: URL) async throws -> URL? {
        try await client.download(attachment, into: folder)
    }
}
