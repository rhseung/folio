import FolioDomain
import Foundation

public protocol WholeFile: Codable {
    static func current(in ctx: ActionContext) throws -> Self
}

extension Settings: WholeFile {
    public static func current(in ctx: ActionContext) throws -> Settings { try ctx.settings() }
}

extension Catalog: WholeFile {
    public static func current(in ctx: ActionContext) throws -> Catalog { try ctx.catalog() }
}
