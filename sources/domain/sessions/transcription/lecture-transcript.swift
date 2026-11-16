import Foundation

public struct LectureTranscript: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var text: String

        public init(start: TimeInterval, end: TimeInterval, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var schemaVersion = 1
    public var locale: String
    public var lines: [Line]
    public var context: TranscriptionContext?

    public init(locale: String, lines: [Line] = [], context: TranscriptionContext? = nil) {
        self.locale = locale
        self.lines = lines
        self.context = context
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        locale = try c.decode(String.self, forKey: .locale)
        lines = try c.decode([Line].self, forKey: .lines)
        // 새 판이 이 판이 못 읽는 꼴로 쓴 맥락은 보조 정보일 뿐이므로 무시하고 줄만 읽는다.
        context = try? c.decodeIfPresent(TranscriptionContext.self, forKey: .context)
    }

    public func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }

    // 충돌로 끊긴 자막은 오디오보다 한참 먼저 끝난다. 마지막 문장을 아직 해독하는 동안 몇 초마다 저장하기 때문이다.
    // 침묵으로 이어진 강의도 이 검사에 걸려 다시 듣게 되지만, 시간만 더 든다.
    public func reaches(_ duration: TimeInterval) -> Bool {
        guard let last = lines.last else { return false }
        return last.end >= duration - Self.tailAllowance
    }

    static let tailAllowance: TimeInterval = 60

    // 아무것도 듣지 못한(조용한 방이거나 모든 줄이 군말인) 받아쓰기가 기존 자막을 지우면 안 된다. 옛 파일을 기록한
    // 곳이 없어서 되찾을 수 없기 때문이다.
    public func replaces(_ existing: LectureTranscript?) -> Bool {
        !lines.isEmpty || existing?.lines.isEmpty != false
    }
}
