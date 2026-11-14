import FolioDomain
import FolioStorage
import Foundation

@Query(
    "recording transcript", "녹음 받아쓰기 읽기: 회차나 녹음 파일로 가리키고 시간 구간으로 자른다",
    discussion: """
        한 번에 \(ReadingLimit.transcript)자(강의 20분쯤)까지 준다. 넘으면 잘라서 다음에 읽을 --from을 알려 준다. 줄마다 시각(12:30)이 붙어서 \
        folio link recording … --time으로 그 자리를 가리킬 수 있다.
        """,
    examples: ["folio recording transcript EC4207/10-26", "folio recording transcript EC4207/10-26 --from 10:00 --to 20:00"],
    phrases: ["받아쓰기", "녹음 내용", "녹음 읽기", "수업에서 뭐라고", "강의 녹음"], panel: true)
public struct RecordingTranscript {
    @Arg public var course: Course.ID
    /// 회차 또는 파일 이름
    @Arg public var recording: Recording.ID
    /// 이 시각부터(12:30, 1:02:03, 초)
    public var from: String?
    /// 이 시각까지
    public var to: String?

    public struct Line: Encodable {
        public var at: String
        public var text: String
    }

    public struct Shown: Encodable {
        public var recording: String
        public var session: String?
        public var duration: String
        public var lines: [Line]
        public var next: String?
    }

    public func read(_ ctx: ReadContext) throws -> Shown {
        let file = try ctx.file(course)
        guard let rec = file.recordings.first(where: { $0.id == recording }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(ItemKind.recording.noun)))
        }
        let start = try from.map(Self.seconds), end = try to.map(Self.seconds)
        guard let transcript = try ctx.store(course).transcript(of: rec), !transcript.lines.isEmpty else {
            throw ActionError.notFound(String(localized: .errorTranscriptNone(rec.file)))
        }
        let (lines, next) = transcript.window(from: start, to: end)
        let clock = { (t: TimeInterval) in AppLink.clock(Int(t)) }
        let session = rec.sessionId.flatMap { id in file.sessions.first { $0.id == id } }.map {
            file.reference(of: $0, calendar: ctx.calendar)
        }
        return Shown(
            recording: rec.file, session: session, duration: clock(rec.duration),
            lines: lines.map { Line(at: clock($0.start), text: $0.text) }, next: next.map(clock))
    }

    // 시각은 앱 링크의 `#t=` 앵커와 같은 꼴로 읽는다.
    public static func seconds(_ written: String) throws -> TimeInterval {
        let link = AppLink(string: "folio://recording/\(UUID().uuidString)#t=\(written.trimmingCharacters(in: .whitespaces))")
        guard case .time(let s)? = link?.anchor else { throw ActionError.input(String(localized: .errorTranscriptBadTime(written))) }
        return TimeInterval(s)
    }
}
