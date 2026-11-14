import FolioDomain
import Foundation

// 정렬한 키와 pretty printing은 iCloud와 git의 diff를 작게 하고, 소수 초까지 쓴 ISO 8601 날짜는 같은 초 안의 이벤트
// 순서를 지킨다.
enum JSONFormat {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.formatted(dateStyle))
        }
        return e
    }()

    static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = encoder.dateEncodingStrategy
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? dateStyle.parse(string) { return date }
            return try Date.ISO8601FormatStyle().parse(string)
        }
        return d
    }()

    static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
