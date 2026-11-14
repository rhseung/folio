import FolioDomain
import FolioStorage
import Foundation

@Query(
    "material show", "자료 하나의 자세한 내용",
    examples: ["folio material show EC4207/Lectures/05_Matchings.pdf", "folio material show EC4207/05_Matchings.pdf"],
    phrases: ["자료 정보"], panel: true)
public struct MaterialShow {
    @Arg public var course: Course.ID
    /// 경로 또는 파일 이름
    @Arg public var material: Material.ID

    // 자료의 `hash`는 마지막 추적 때의 값이라 다른 기기에서 바꾼 뒤에는 맞지 않으므로, 글 자료의 JSON에는 지금 파일과
    // `material write --expect`가 비교할 해시를 함께 싣는다.
    public struct Shown: Encodable {
        public var material: Material
        public var text: String?

        public func encode(to encoder: Encoder) throws {
            try material.encode(to: encoder)
            var c = encoder.container(keyedBy: Keys.self)
            if let format = material.format {
                try c.encode(format.name, forKey: .format)
                if case .code(let language) = format { try c.encode(language, forKey: .language) }
            }
            if let text {
                try c.encode(text, forKey: .text)
                try c.encode(ContentHash.of(text), forKey: .contentHash)
            }
        }
    }

    public func read(_ ctx: ReadContext) throws -> Shown {
        guard let m = try ctx.file(course).materials.first(where: { $0.id == material }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(ItemKind.material.noun)))
        }
        return Shown(material: m, text: m.isText ? try? ctx.store(course).readText(m.path) : nil)
    }
}

extension MaterialShow.Shown {
    private enum Keys: String, CodingKey { case format, language, text, contentHash }
}
