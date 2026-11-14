import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

// 자료의 `hash`는 마지막 추적 때의 값이라 다른 기기에서 바꾼 뒤에는 맞지 않으므로, 글 자료의 JSON에는 지금 파일과
// `material write --expect`가 비교할 해시를 함께 싣는다.
struct ShownMaterial: Encodable {
    var material: Material
    var text: String?

    private enum Keys: String, CodingKey { case format, language, text, contentHash }

    func encode(to encoder: Encoder) throws {
        try material.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        if let format = material.format {
            try c.encode(format.name, forKey: .format)
            if case .code(let language) = format { try c.encode(language, forKey: .language) }
        }
        if let text {
            try c.encode(text, forKey: .text)
            try c.encode(contentHash(text), forKey: .contentHash)
        }
    }

    static func label(_ format: MaterialFormat) -> String {
        if case .code(let language) = format { return "\(format.name) (\(language))" }
        return format.name
    }
}
