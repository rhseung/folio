import Foundation

public enum Term: String, CaseIterable, Codable, Sendable {
    case spring, summer, fall, winter
    case credited

    public var folderNumber: Int? {
        switch self {
        case .spring: 1
        case .summer: 2
        case .fall: 3
        case .winter: 4
        case .credited: nil
        }
    }
}

extension Term {
    public static let ordered: [Term] = [.spring, .summer, .fall, .winter]

    // 정규 학기는 넉 달, 계절 학기는 두 달쯤이다. 학기를 만들 때 끝 날짜의 처음 값으로만 쓰고 사용자가 고친다.
    public var months: Int {
        switch self {
        case .spring, .fall: 4
        case .summer, .winter, .credited: 2
        }
    }

    // 가장 최근 학기 다음 학기다. 학기가 없으면 지금 날짜가 든 해의 가을학기로 시작한다.
    public static func next(after newest: (year: Int, term: Term)?, now: Date, calendar: Calendar) -> (year: Int, term: Term) {
        guard let newest, let i = ordered.firstIndex(of: newest.term) else {
            return (calendar.component(.year, from: now), .fall)
        }
        return i + 1 < ordered.count ? (newest.year, ordered[i + 1]) : (newest.year + 1, ordered[0])
    }
}
