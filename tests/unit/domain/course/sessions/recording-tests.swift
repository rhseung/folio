import FolioDomain
import Foundation
import Testing

struct RecordingTests {
    @Test func fileNamesAreNumberedWhenTaken() {
        #expect(Recording.file(named: "3주차-1", taken: []) == "Recordings/3주차-1.m4a")
        #expect(Recording.file(named: "3주차-1", taken: ["3주차-1.m4a", "3주차-1 2.m4a"]) == "Recordings/3주차-1 3.m4a")
    }

    @Test func transcriptSitsBesideTheAudio() {
        let r = Recording(device: UUID(), at: .now, sessionId: nil, file: "Recordings/3주차-1 2.m4a")
        #expect(r.transcriptFile == "Recordings/3주차-1 2.transcript.json")
    }

    @Test func captionsCutOffByACrashDoNotReachTheEnd() {
        let t = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 4, text: "a"), .init(start: 5, end: 600, text: "b")])
        #expect(t.reaches(600))
        #expect(t.reaches(660))
        #expect(!t.reaches(661))
        #expect(!LectureTranscript(locale: "ko-KR").reaches(0))
    }

    @Test func anEmptyTranscriptNeverWipesCaptions() {
        let heard = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 4, text: "a")])
        let empty = LectureTranscript(locale: "ko-KR")
        #expect(!empty.replaces(heard))
        #expect(empty.replaces(nil))
        #expect(empty.replaces(empty))
        #expect(heard.replaces(heard))
    }

    @Test func lineAtTimeIsTheLastStartedLine() {
        let t = LectureTranscript(
            locale: "ko_KR",
            lines: [.init(start: 0, end: 4, text: "a"), .init(start: 5, end: 9, text: "b"), .init(start: 12, end: 15, text: "c")])
        #expect(t.lineIndex(at: -1) == nil)
        #expect(t.lineIndex(at: 0) == 0)
        #expect(t.lineIndex(at: 4.5) == 0)
        #expect(t.lineIndex(at: 5) == 1)
        #expect(t.lineIndex(at: 100) == 2)
        #expect(LectureTranscript(locale: "ko_KR").lineIndex(at: 3) == nil)
    }

    @Test func onlyAudioWithATranscriptIsTrimmable() {
        var gone = Recording(device: UUID(), at: .now, sessionId: nil, file: "Recordings/1주차-1.m4a")
        gone.audioTrashedAt = .now
        let heard = Recording(device: UUID(), at: .now, sessionId: nil, file: "Recordings/1주차-2.m4a")
        let silent = Recording(device: UUID(), at: .now, sessionId: nil, file: "Recordings/2주차-1.m4a")
        let kept = RecordingRetention.trimmable([gone, heard, silent]) { $0.id != silent.id }
        #expect(kept.map(\.id) == [heard.id])
        #expect(!gone.hasAudio && heard.hasAudio)
    }

    @Test func aSemesterIsOverAfterItsEndOrOnceTheNextOneStarts() {
        func day(_ m: Int, _ d: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: d)! }
        var spring = Semester(device: UUID(), at: .now, year: 2026, term: .spring)
        var fall = Semester(device: UUID(), at: .now, year: 2026, term: .fall)
        fall.start = day(9, 1)
        spring.end = day(6, 19)

        #expect(!spring.isOver(on: day(6, 19), among: [spring, fall]))
        #expect(spring.isOver(on: day(6, 20), among: [spring, fall]))

        // No end date: over only once a later semester has begun.
        spring.end = nil
        #expect(!spring.isOver(on: day(8, 31), among: [spring, fall]))
        #expect(spring.isOver(on: day(9, 1), among: [spring, fall]))
        #expect(!fall.isOver(on: day(12, 31), among: [spring, fall]))
    }
}
