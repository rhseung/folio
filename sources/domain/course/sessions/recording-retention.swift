import Foundation

public enum RecordingRetention {
    public static func trimmable(_ recordings: [Recording], transcribed: (Recording) -> Bool) -> [Recording] {
        recordings.filter { $0.hasAudio && transcribed($0) }
    }
}

extension Semester {
    public func isOver(on today: LocalDate, among semesters: [Semester]) -> Bool {
        if let end { return end < today }
        return semesters.contains { $0.order > order && ($0.start.map { $0 <= today } ?? false) }
    }
}
