import Foundation

public enum LMS {
    public static let base = URL(string: "https://lms.gist.ac.kr")!
    // LMS 페이지의 날짜는 시간대를 적지 않은 한국 시각이다.
    public static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    public static func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
}
