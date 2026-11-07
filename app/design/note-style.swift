import Foundation

/// Theme colors and `NoteLook`'s sizes as CSS variables for note pages (web/src/note.css names no color of its own and
/// takes the column, type sizes and gaps from these), plus the bundled stylesheet and scripts built into resources/web
/// by `mise run build-web` (Xcode copies them to the bundle root).
enum NoteStyle {
    static func variables(accent: CourseAccent) -> String {
        func block(_ pick: (UInt32, UInt32) -> UInt32) -> String {
            let swatches: [(String, Swatch)] = [
                ("text", .text), ("text-2", .textSecondary), ("text-3", .textTertiary), ("line", .line),
                ("line-soft", .lineSoft), ("fill", .fill), ("code-fill", .codeFill), ("card", .card),
            ]
            // Callout kinds borrow the course presets, so a theorem is violet in every course.
            let presets = Dictionary(uniqueKeysWithValues: CourseAccent.presets.map { ($0.name, $0.accent) })
            let callouts: [(String, CourseAccent)] = [
                ("c-definition", presets["blue"]!), ("c-theorem", presets["violet"]!), ("c-example", presets["green"]!),
                ("c-warning", presets["orange"]!), ("c-danger", presets["red"]!), ("c-neutral", .gray), ("c-type", presets["teal"]!), ("c-decorator", presets["pink"]!), ("c-property", presets["red"]!),
            ]
            let pairs = swatches.map { ($0.0, pick($0.1.light, $0.1.dark)) }
                + callouts.map { ($0.0, pick($0.1.light, $0.1.dark)) }
                + [("accent", pick(accent.light, accent.dark)), ("accent-ink", pick(accent.inkLight, accent.inkDark))]
            return pairs.map { String(format: "--%@:#%06X;", $0.0, $0.1) }.joined()
        }
        return ":root{\(block { l, _ in l })}@media (prefers-color-scheme: dark){:root{\(block { _, d in d })}}" + sizes
    }

    static let sizes: String = {
        let values: [(String, CGFloat)] = [
            ("measure", NoteLook.measure), ("margin", NoteLook.margin), ("body", NoteLook.body), ("paragraph-gap", NoteLook.paragraphGap),
            ("block-gap", NoteLook.blockGap), ("radius", NoteLook.radius), ("code-size", NoteLook.codeSize), ("label-size", NoteLook.labelSize),
        ] + NoteLook.headingSizes.enumerated().map { ("h\($0.offset + 1)", $0.element) }
            + [("fade", Theme.Space.xl)]
        return ":root{" + values.map { String(format: "--%@:%gpx;", $0.0, Double($0.1)) }.joined() + "}"
    }()

    static func resource(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    static let css = resource("note.css")
    static let reader = resource("reader.js")
}
