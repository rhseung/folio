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

    @Test func lineAtTimeIsTheLastStartedLine() {
        let t = LectureTranscript(locale: "ko_KR", lines: [.init(start: 0, end: 4, text: "a"), .init(start: 5, end: 9, text: "b"), .init(start: 12, end: 15, text: "c")])
        #expect(t.lineIndex(at: -1) == nil)
        #expect(t.lineIndex(at: 0) == 0)
        #expect(t.lineIndex(at: 4.5) == 0)
        #expect(t.lineIndex(at: 5) == 1)
        #expect(t.lineIndex(at: 100) == 2)
        #expect(LectureTranscript(locale: "ko_KR").lineIndex(at: 3) == nil)
    }
}
