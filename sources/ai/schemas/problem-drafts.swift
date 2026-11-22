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

        public init(
            number: String, parent: String? = nil, points: Double? = nil, page: Int? = nil, text: String, format: String = "written",
            options: [String] = [], answer: String? = nil, units: [String] = [], solution: String? = nil, solutionPage: Int? = nil,
            lecturePages: [LecturePageRef]? = nil
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
                })
        }
    }

    public var problems: [Draft]

    static let draft = Schema.object([
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
    ])

    public static let schema = Schema.object(["problems": Schema.array(draft)])
}
