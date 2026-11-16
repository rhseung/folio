import FolioCore
import Foundation

// 보고는 사용자가 다른 곳(세션, 이슈)에 넘기는 파일이 된다. 그래서 파일 이름과 과목 이름이 들어갈 수 있는 자리를 지운다.
public enum DiagnosticRedaction {
    // Objective-C 예외의 완성된 문구와 그 인자에는 앱이 넘긴 값(노트 경로, 과목 이름)이 그대로 들어간다. 형식 문자열과
    // 예외 이름은 코드에 적힌 글이라 남긴다.
    static let droppedKeys: Set = ["composedMessage", "arguments"]  // strings: data, MetricKit JSON keys

    // 경로에는 띄어쓰기가 들어가므로(`EC4207 그래프 이론/Notes`) 경로가 시작한 곳부터 그 줄 끝까지 지운다. 낱말 가운데의
    // `/`(`1/2`)는 경로로 보지 않는다.
    // swiftlint:disable:next force_try
    static let path = try! NSRegularExpression(
        pattern: #"(^|[\s'"(=:\[<])(?:file://|~/|/)\S[^\n]*"#, options: [.anchorsMatchLines])
    static let placeholder = "<path>"  // strings: data, written into exported reports

    public static func redact(_ value: JSONValue) -> JSONValue {
        switch value {
        case .string(let text): .string(redact(text))
        case .array(let items): .array(items.map(redact))
        case .object(let fields):
            .object(fields.filter { !droppedKeys.contains($0.key) }.mapValues(redact))
        case .null, .bool, .number: value
        }
    }

    public static func redact(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return path.stringByReplacingMatches(in: text, range: range, withTemplate: "$1" + placeholder)
    }
}
