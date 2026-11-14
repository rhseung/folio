import FolioDomain
import FolioLMS
import Foundation
import Observation

struct FixedLMS: LMSSource {
    var snapshot: LMSSnapshot

    func verify(_ login: LMSCredentials) throws {}
    func read(attachments: @escaping @Sendable (LMSSnapshot) -> [LMSAssignment]) throws -> LMSSnapshot { snapshot }
    func download(_ file: LMSFile, into folder: URL) throws -> URL? { nil }
    func download(_ attachment: LMSAttachment, into folder: URL) throws -> URL? { nil }
}
