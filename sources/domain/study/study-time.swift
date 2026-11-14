import Foundation

public enum StudyTime {
    public static func perDay(_ sessions: [StudySessionEvent], settings: Settings, calendar: Calendar) -> [LocalDate: TimeInterval] {
        var merged: [(start: Date, end: Date)] = []
        for s in sessions.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, s.start <= last.end {
                merged[merged.count - 1].end = max(last.end, s.end)
            } else {
                merged.append((s.start, s.end))
            }
        }
        var result: [LocalDate: TimeInterval] = [:]
        for m in merged { result[settings.studyDay(of: m.start, calendar: calendar), default: 0] += m.end.timeIntervalSince(m.start) }
        return result
    }

    public static func label(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 60
            ? String(localized: .studyTimeMinutes(minutes))
            : minutes % 60 == 0
                ? String(localized: .studyTimeHours(minutes / 60))
                : String(localized: .studyTimeHoursMinutes(minutes / 60, minutes % 60))
    }
}
