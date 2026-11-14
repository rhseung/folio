import Foundation

// 받을 수 있는 파일인지는 페이지를 열어야 안다. 허용된 파일은 원본으로 리디렉션되고, 나머지는 Coursemos
// 뷰어만 보이므로 링크로 남긴다.
public struct LMSFile: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var classroom: Int
    public var title: String
    public var week: String?

    public init(id: Int, classroom: Int, title: String, week: String? = nil) {
        self.id = id
        self.classroom = classroom
        self.title = title
        self.week = week
    }

    public var key: LMSKey { .init(kind: .file, id: id) }
    public var url: URL { LMS.url("/mod/ubfile/view.php?id=\(id)") }

    public func lectureName(_ downloaded: String) -> String {
        guard downloaded.first?.isNumber == false, let week, let number = Int(week.prefix { $0.isNumber }) else { return downloaded }
        return String(format: "%02d_", number) + downloaded
    }
}
