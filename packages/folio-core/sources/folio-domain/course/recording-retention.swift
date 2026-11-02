import Foundation

/// Which recordings' audio can go once their semester is over (#199). Only the audio goes; a recording
/// without a transcript keeps it, since removing it would leave nothing of the lecture.
public enum RecordingRetention {
    public static func trimmable(_ recordings: [Recording], transcribed: (Recording) -> Bool) -> [Recording] {
        recordings.filter { $0.hasAudio && transcribed($0) }
    }
}

extension Semester {
    /// Past its end date. A semester imported without one is over once a later one has started.
    public func isOver(on today: LocalDate, among semesters: [Semester]) -> Bool {
        if let end { return end < today }
        return semesters.contains { $0.order > order && ($0.start.map { $0 <= today } ?? false) }
    }
}
