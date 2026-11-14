import FolioDomain
import Foundation

public struct QuerySpec: Codable, Sendable, Equatable {
    public var command: String
    public var summary: String
    public var discussion: String
    public var examples: [String]
    public var phrases: [String]
    public var generated: Bool
    public var manualReason: String?
    // Claude 패널(`folio mcp --propose`)에 도구로 연다.
    public var panel: Bool
    public var fields: [FieldSpec]

    public init(
        command: String, summary: String, discussion: String = "", examples: [String] = [], phrases: [String] = [], generated: Bool = true,
        manualReason: String? = nil, panel: Bool = false, fields: [FieldSpec] = []
    ) {
        (self.command, self.summary, self.discussion, self.examples, self.phrases) = (command, summary, discussion, examples, phrases)
        (self.generated, self.manualReason, self.panel, self.fields) = (generated, manualReason, panel, fields)
    }
}
