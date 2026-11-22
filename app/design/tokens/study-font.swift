import CoreText
import SwiftUI

// 문제와 카드 글의 글꼴이다. KaTeX의 본문 글꼴(Computer Modern 모양)이라 수식 그림과 글이 한 장의 문제지처럼 보인다. 한글은
// 이 글꼴에 없어서 Mac은 명조로 잇는다. iPad에는 명조가 없어 시스템 글꼴로 잇는다.
enum StudyFont {
    static let family = "KaTeX_Main"

    // 앱 묶음의 ttf를 처음 쓸 때 한 번 등록한다. 등록하지 못하면 시스템의 serif 글꼴로 그린다.
    private static let registered: Bool = {
        let urls = ["regular", "italic", "bold", "bold-italic"].compactMap {
            Bundle.main.url(forResource: "katex-main-\($0)", withExtension: "ttf")
        }
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        return !urls.isEmpty
    }()

    static func font(size: CGFloat) -> Font {
        guard registered else { return .system(size: size, design: .serif) }
        var attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
        #if os(macOS)
        attributes[kCTFontCascadeListAttribute] = [CTFontDescriptorCreateWithNameAndSize("AppleMyungjo" as CFString, size)]
        #endif
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}
