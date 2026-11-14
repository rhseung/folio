import FolioDomain
import Foundation

public struct FieldSpec: Codable, Sendable, Equatable {
    public enum Role: Codable, Sendable, Equatable {
        case argument
        case option
        case off(String)
        case new
        case hidden
    }

    public var name: String
    public var help: String
    public var role: Role
    public var type: String
    public var ref: String?
    public var optional: Bool
    public var many: Bool
    public var patch: Bool
    public var defaultValue: String?
    public var cliName: String?
    public var file: String?
    public var filePerItem: Bool
    public var folder: Bool
    public var parsed: String?
    public var parsedForm: String?

    public init(
        name: String, help: String = "", role: Role = .option, type: String, ref: String? = nil, optional: Bool = false, many: Bool = false,
        patch: Bool = false, defaultValue: String? = nil, cliName: String? = nil, file: String? = nil, filePerItem: Bool = false,
        folder: Bool = false,
        parsed: String? = nil, parsedForm: String? = nil
    ) {
        (self.name, self.help, self.role, self.type, self.ref) = (name, help, role, type, ref)
        (self.optional, self.many, self.patch, self.defaultValue) = (optional, many, patch, defaultValue)
        (self.cliName, self.file, self.filePerItem, self.folder) = (cliName, file, filePerItem, folder)
        (self.parsed, self.parsedForm) = (parsed, parsedForm)
    }
}
