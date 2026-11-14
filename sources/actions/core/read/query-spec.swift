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
    // 명령줄에서 `--lines`를 받는다. 한 줄에 하나씩 쓰고 첫 칸에 다른 명령에 넘길 참조를 둔다.
    public var lines: Bool
    // 성적을 보이므로 읽기 전에 성적 잠금을 푼다.
    public var grades: Bool
    public var fields: [FieldSpec]

    public init(
        command: String, summary: String, discussion: String = "", examples: [String] = [], phrases: [String] = [], generated: Bool = true,
        manualReason: String? = nil, panel: Bool = false, lines: Bool = false, grades: Bool = false, fields: [FieldSpec] = []
    ) {
        (self.command, self.summary, self.discussion, self.examples, self.phrases) = (command, summary, discussion, examples, phrases)
        (self.generated, self.manualReason, self.panel, self.lines, self.grades) = (generated, manualReason, panel, lines, grades)
        self.fields = fields
    }
}
