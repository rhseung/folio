import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    func code(_ prefix: String) throws -> CourseCode {
        try pick(prefix, try ctx.catalog().codes, what: "강의 코드", names: { [$0.prefix] }, ref: \.prefix)
    }

    func person(_ name: String) throws -> Person {
        try pick(name, try ctx.catalog().people, what: "교수", names: { [$0.name] }, ref: \.name)
    }

    func category(_ name: String) throws -> FolioDomain.Category {
        try pick(name, try ctx.catalog().categories, what: "분류", names: { [$0.name] }, ref: \.name)
    }
}
