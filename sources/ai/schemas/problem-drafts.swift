import FolioCore
import FolioDomain
import Foundation

public struct ProblemDrafts: StructuredResult, Equatable {
    public struct LecturePageRef: Codable, Sendable, Equatable {
        public var lecture: String
        public var page: Int

        public init(lecture: String, page: Int) {
            self.lecture = lecture
            self.page = page
        }
    }

    // 쪽의 왼쪽 위를 원점으로 한 폭과 높이의 비율이다.
    public struct RegionRef: Codable, Sendable, Equatable {
        public var page: Int
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(page: Int, x: Double, y: Double, width: Double, height: Double) {
            self.page = page
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var region: ProblemRegion? { ProblemRegion(page: page, x: x, y: y, width: width, height: height) }
    }

    // 소문제들이 함께 딸린 지문이다. 소문제의 `parent`가 `number`다.
    public struct GroupDraft: Codable, Sendable, Equatable {
        public var number: String
        public var title: String?
        public var parent: String?
        public var page: Int?
        public var text: String
        public var region: RegionRef?
        public var figures: [RegionRef]

        public init(
            number: String, title: String? = nil, parent: String? = nil, page: Int? = nil, text: String, region: RegionRef? = nil,
            figures: [RegionRef] = []
        ) {
            self.number = number
            self.title = title
            self.parent = parent
            self.page = page
            self.text = text
            self.region = region
            self.figures = figures
        }

        var group: ProblemGroup {
            ProblemGroup(
                number: number, title: title.flatMap { $0.isEmpty ? nil : $0 }, parent: parent, page: page, text: text,
                region: region?.region, figures: figures.compactMap(\.region))
        }
    }

    public struct Draft: Codable, Sendable, Equatable {
        public var number: String
        public var parent: String?
        public var points: Double?
        public var page: Int?
        public var text: String
        public var format: String
        public var options: [String]
        public var answer: String?
        public var units: [String]
        public var solution: String?
        public var solutionPage: Int?
        // 문제지를 뽑을 때만 채운다. Claude 문제지의 답에는 없다.
        public var lecturePages: [LecturePageRef]?
        // 문제지를 뽑을 때만 채운다. Claude가 쓴 문제지에는 그림이 없다.
        public var region: RegionRef?
        public var figures: [RegionRef]?
        // 문제집 PDF의 칸 크기(half, full)다. 문제지를 뽑을 때만 채운다.
        public var size: String?

        public init(
            number: String, parent: String? = nil, points: Double? = nil, page: Int? = nil, text: String, format: String = "written",
            options: [String] = [], answer: String? = nil, units: [String] = [], solution: String? = nil, solutionPage: Int? = nil,
            lecturePages: [LecturePageRef]? = nil, region: RegionRef? = nil, figures: [RegionRef]? = nil, size: String? = nil
        ) {
            self.number = number
            self.parent = parent
            self.points = points
            self.page = page
            self.text = text
            self.format = format
            self.options = options
            self.answer = answer
            self.units = units
            self.solution = solution
            self.solutionPage = solutionPage
            self.lecturePages = lecturePages
            self.region = region
            self.figures = figures
            self.size = size
        }

        // 단원은 제목으로, 렉처는 프롬프트에 적은 이름(`lectures`의 키)으로 받는다. 없는 제목과 이름은 버린다. Claude가 지어내도
        // 과목에 없는 연결이 생기지 않게 하기 위해서다.
        public func problem(units outline: [FolioDomain.Unit], lectures: [String: UUID] = [:]) -> Problem {
            let format = ProblemFormat(rawValue: format) ?? .written
            let ids = units.compactMap { title in outline.first { $0.title == title }?.id }.reduce(into: [UUID]()) { found, id in
                if !found.contains(id) { found.append(id) }
            }
            return Problem(
                number: number, parent: parent, points: points, page: page, text: text, format: format,
                options: format == .trueFalse ? Problem.trueFalseOptions : format == .choice ? options : [],
                answer: answer.flatMap { $0.isEmpty ? nil : $0 }, unitIds: ids,
                solution: solution.flatMap { $0.isEmpty ? nil : $0 }, solutionPage: solutionPage,
                lecturePages: (lecturePages ?? []).compactMap { ref in
                    lectures[ref.lecture].map { ProblemPage(materialId: $0, page: ref.page) }
                }, region: region?.region, figures: (figures ?? []).compactMap(\.region), size: size.flatMap(ProblemSize.init(rawValue:)))
        }
    }

    public var problems: [Draft]
    public var groups: [GroupDraft]?

    public init(problems: [Draft], groups: [GroupDraft]? = nil) {
        self.problems = problems
        self.groups = groups
    }

    static let properties: [String: JSONValue] = [
        "number": Schema.string,
        "parent": Schema.nullable(Schema.string),
        "points": Schema.nullable(Schema.number),
        "page": Schema.nullable(Schema.integer),
        "text": Schema.string,
        "format": Schema.enumeration(ProblemFormat.allCases.map(\.rawValue)),
        "options": Schema.array(Schema.string),
        "answer": Schema.nullable(Schema.string),
        "units": Schema.array(Schema.string),
        "solution": Schema.nullable(Schema.string),
        "solutionPage": Schema.nullable(Schema.integer),
        "lecturePages": Schema.array(Schema.object(["lecture": Schema.string, "page": Schema.integer])),
    ]

    static let draft = Schema.object(properties)

    static let region = Schema.object([
        "page": Schema.integer, "x": Schema.number, "y": Schema.number, "width": Schema.number, "height": Schema.number,
    ])

    // 문제지에서 뽑을 때만 칸과 그림, 지문을 받는다. Claude가 쓰는 문제지(`ProblemSheetDraft`)는 `draft`를 그대로 쓴다.
    static let sheetDraft = Schema.object(
        properties.merging([
            "region": Schema.nullable(region), "figures": Schema.array(region),
            "size": Schema.nullable(Schema.enumeration(ProblemSize.allCases.map(\.rawValue))),
        ]) { a, _ in a })

    static let group = Schema.object([
        "number": Schema.string, "title": Schema.nullable(Schema.string), "parent": Schema.nullable(Schema.string),
        "page": Schema.nullable(Schema.integer), "text": Schema.string, "region": Schema.nullable(region),
        "figures": Schema.array(region),
    ])

    public static let schema = Schema.object(["problems": Schema.array(sheetDraft), "groups": Schema.array(group)])
}
