import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    public func run<T: StructuredResult>(_ task: ClaudeTask, _ type: T.Type, system: [ContentBlock], messages: [Message]) async throws -> T
    {
        try await structured(task, as: type, schema: T.schema, system: system, messages: messages)
    }
}
