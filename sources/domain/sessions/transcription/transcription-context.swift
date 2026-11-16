import Foundation

public struct TranscriptionContext: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case recording
        case session
        case tagged
        case week
    }

    public var source: Source?
    public var slides: [LecturePages]
    public var topics: [String]
    public var terms: [String]

    public init(source: Source?, slides: [LecturePages], topics: [String], terms: [String] = []) {
        self.source = source
        self.slides = slides
        self.topics = topics
        self.terms = terms
    }

    // 새 판이 더한 출처는 받아쓰기 전체를 실패시키지 않고 알 수 없는 값으로 읽는다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap(Source.init(rawValue:))
        slides = try c.decodeIfPresent([LecturePages].self, forKey: .slides) ?? []
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
    }

    public func reading(_ slides: String) -> TranscriptionContext {
        var read = self
        read.terms = LectureTerms.terms(in: slides)
        return read
    }

    public func hints(course title: String) -> TranscriptionHints {
        var seen = Set<String>()
        return TranscriptionHints(title: title, terms: (topics + terms).filter { seen.insert($0.lowercased()).inserted })
    }

    public func differs(from current: TranscriptionContext) -> Bool {
        func key(_ s: LecturePages) -> String { "\(s.materialId?.uuidString ?? s.path) \(s.first ?? 0) \(s.last ?? 0)" }
        return source != current.source || slides.map(key) != current.slides.map(key) || topics != current.topics
    }
}
