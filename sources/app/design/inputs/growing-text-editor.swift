import FolioDomain
import SwiftUI

// `TextField(axis: .vertical)`를 쓰지 않는다. Mac에서는 그 Return이 줄을 바꾸지 않고 입력을 끝내는데, 선택지와 규칙은
// 한 줄에 하나씩 쓰기 때문이다. 드래그 손잡이도 쓰지 않는데, 터치로는 끌 수단이 없기 때문이다.
struct GrowingTextEditor: View {
    @Binding var text: String
    var size: CGFloat = Theme.Typeface.bodySize
    var lines: ClosedRange<Int> = 3...12
    var room: CGFloat?
    @State private var width: CGFloat = 0

    var body: some View {
        let height = Self.height(of: text, size: size, width: width, lines: lines, room: room)
        TextEditor(text: $text)
            .font(.system(size: size))
            .scrollContentBackground(.hidden)
            // 스크롤할 때만 막대를 보인다. 그때는 텍스트 입력이 막대를 지켜야 한다(둘러싼 페이드 스크롤 영역이 안쪽
            // 전체의 막대를 숨긴다). 그런데 Mac 편집기는 막대 폭만큼 자리를 비워 두고 여기서 잰 폭보다 좁게 줄바꿈해서,
            // 늘 보이면 상자가 한 줄 모자랐다.
            .scrollIndicators(height.scrolls ? .automatic : .never)
            .frame(height: height.points)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
    }

    // 편집기의 text view와 같은 방식으로 TextKit에 배치시킨다. 숨긴 SwiftUI `Text`로 재면 긴 URL을 편집기와 다른
    // 자리에서 끊어 한 줄이 모자랐고, 상자에 들어가야 할 마지막 줄이 스크롤되어 밀려났다.
    static func height(of text: String, size: CGFloat, width: CGFloat, lines: ClosedRange<Int>, room: CGFloat? = nil) -> (
        points: CGFloat, scrolls: Bool
    ) {
        let font = PlatformFont.systemFont(ofSize: size)
        let layout = NSLayoutManager()
        #if os(macOS)
        let line = layout.defaultLineHeight(for: font)
        #else
        let line = font.lineHeight
        #endif
        var used = line * CGFloat(lines.lowerBound)
        if width > 0 {
            let storage = NSTextStorage(string: text, attributes: [.font: font])
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            // used rect는 끝 줄바꿈 뒤의 빈 줄까지 센다. 편집기의 캐럿이 그 줄에 놓인다.
            used = layout.usedRect(for: container).height
        }
        let fit = room.map { Int(($0 - 2 * inset) / line) } ?? lines.upperBound
        let cap = line * CGFloat(max(lines.lowerBound, min(lines.upperBound, fit)))
        return (min(max(used, line * CGFloat(lines.lowerBound)), cap).rounded(.up) + 2 * inset, used > cap)
    }

    // UITextView는 글을 위아래 가장자리에서 8pt 띄우고, Mac의 text view는 가장자리에 붙인다.
    #if os(iOS)
    private static let inset: CGFloat = 8
    #else
    private static let inset: CGFloat = 0
    #endif
}
