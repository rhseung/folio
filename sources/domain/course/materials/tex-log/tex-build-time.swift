import Foundation

// 지금 시각이 아니라 달력 날짜의 자정을 `SOURCE_DATE_EPOCH`로 쓴다. 그래야 같은 날 바뀌지 않은 글을 다시 빌드하면
// 같은 바이트가 나와서 iCloud가 새로 동기화할 것이 없다.
public enum TexBuildTime {
    public static func sourceDateEpoch(at now: Date, calendar: Calendar) -> Int {
        Int(calendar.startOfDay(for: now).timeIntervalSince1970)
    }
}
