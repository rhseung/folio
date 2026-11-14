import Foundation

// sources/web/src/note.css는 자기 색을 두지 않고, 열 폭과 글자 크기와 간격을 이 변수에서 받는다. 번들 stylesheet와
// script는 `mise run build-web`이 resources/web에 만들고, Xcode가 번들 루트로 복사한다.
enum NoteStyle {
    static func variables(accent: CourseAccent) -> String {
        func block(_ pick: (UInt32, UInt32) -> UInt32) -> String {
            let swatches: [(String, Swatch)] = [
                ("text", .text), ("text-2", .textSecondary), ("text-3", .textTertiary), ("line", .line),
                ("line-soft", .lineSoft), ("fill", .fill), ("code-fill", .codeFill), ("card", .card),
            ]
            let presets = Dictionary(uniqueKeysWithValues: CourseAccent.presets.map { ($0.name, $0.accent) })
            let callouts: [(String, CourseAccent)] = [
                ("c-definition", presets["blue"]!), ("c-theorem", presets["violet"]!), ("c-example", presets["green"]!),
                ("c-warning", presets["orange"]!), ("c-danger", presets["red"]!), ("c-neutral", .gray), ("c-type", presets["teal"]!),
                ("c-decorator", presets["pink"]!), ("c-property", presets["red"]!),
            ]
            let pairs =
                swatches.map { ($0.0, pick($0.1.light, $0.1.dark)) }
                + callouts.map { ($0.0, pick($0.1.light, $0.1.dark)) }
                + [("accent", pick(accent.light, accent.dark)), ("accent-ink", pick(accent.inkLight, accent.inkDark))]
            return pairs.map { String(format: "--%@:#%06X;", $0.0, $0.1) }.joined()
        }
        return ":root{\(block { l, _ in l })}@media (prefers-color-scheme: dark){:root{\(block { _, d in d })}}" + sizes
    }

    static let sizes: String = {
        let values: [(String, CGFloat)] =
            [
                ("measure", NoteLook.measure), ("margin", NoteLook.margin), ("body", NoteLook.body),
                ("paragraph-gap", NoteLook.paragraphGap),
                ("block-gap", NoteLook.blockGap), ("radius", NoteLook.radius), ("code-size", NoteLook.codeSize),
                ("label-size", NoteLook.labelSize),
                ("break-dot", NoteLook.breakDot), ("break-pitch", NoteLook.breakDotPitch), ("break-space", NoteLook.breakSpace),
            ] + NoteLook.headingSizes.enumerated().map { ("h\($0.offset + 1)", $0.element) }
            + [("fade", Theme.Space.xl)]
            + [("control", Theme.Size.toolbarButton), ("touch", Theme.Size.fab), ("gap", Theme.Space.s), ("glass-blur", Theme.Space.l)]
        let label = String(localized: .notesOutlineTitle).replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return ":root{" + values.map { String(format: "--%@:%gpx;", $0.0, Double($0.1)) }.joined()
            + String(format: "--scrim:rgb(0 0 0 / %g);", Theme.Opacity.figureScrim) + "--toc-label:\"\(label)\";}"
    }()

    static func resource(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    static let css = resource("note.css")
    static let reader = resource("reader.js")
}
