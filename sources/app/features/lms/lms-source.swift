import FolioDomain
import FolioLMS
import Foundation
import Observation

protocol LMSSource: Sendable {
    func verify(_ login: LMSCredentials) async throws
    func read(attachments: @escaping @Sendable (LMSSnapshot) -> [LMSAssignment]) async throws -> LMSSnapshot
    func download(_ file: LMSFile, into folder: URL) async throws -> URL?
    func download(_ attachment: LMSAttachment, into folder: URL) async throws -> URL?
}
