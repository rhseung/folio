import Testing

@testable import FolioDev

struct VersionLiteralTests {
    static let source = """
        // 버전은 이 한 곳에서만 정한다. "9.9.9" 같은 글은 주석이다.
        public enum FolioVersion {
            public static let build = "1.1.1"
            public static let marketing = "0.4.2" // 다음 릴리스
        }
        """

    @Test func readsTheMarketingLiteralOnly() {
        #expect(VersionLiteral.read(Self.source) == "0.4.2")
        #expect(VersionLiteral.read("enum Other { static let marketing = \"1.0.0\" }") == nil)
    }

    @Test func replacesTheLiteralAndKeepsTheRest() throws {
        let raised = try #require(VersionLiteral.replacing(Self.source, with: "0.5.0"))
        #expect(VersionLiteral.read(raised) == "0.5.0")
        #expect(raised == Self.source.replacingOccurrences(of: "\"0.4.2\"", with: "\"0.5.0\""))
    }
}
