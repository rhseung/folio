import Foundation

// 파일 이름(`11-03(화)`)과 빠른 추가, 반복 규칙이 읽고 쓰는 요일 글자다. 화면 언어와 상관없는 데이터라 카탈로그에 두지 않는다.
public enum WeekdayLetters {
    // ISO 8601 요일 차례다. 0번이 월요일이다.
    public static let all = ["월", "화", "수", "목", "금", "토", "일"]

    public static func letter(_ isoWeekday: Int) -> String { all[(isoWeekday - 1 + 7) % 7] }

    public static func isoWeekday(_ letter: String) -> Int? { all.firstIndex(of: letter).map { $0 + 1 } }
}
