import FolioDomain
import Foundation

public struct LectureSectionDrafts: StructuredResult, Equatable {
    public struct Draft: Codable, Sendable, Equatable {
        public var title: String
        public var firstPage: Int
        public var unit: String?
        public var skip: Bool?

        public init(title: String, firstPage: Int, unit: String? = nil, skip: Bool? = nil) {
            self.title = title
            self.firstPage = firstPage
            self.unit = unit
            self.skip = skip
        }
    }

    public var sections: [Draft]

    public static let schema = Schema.object([
        "sections": Schema.array(
            Schema.object([
                "title": Schema.string,
                "firstPage": Schema.integer,
                "unit": Schema.nullable(Schema.string),
                "skip": Schema.boolean,
            ]))
    ])
}
