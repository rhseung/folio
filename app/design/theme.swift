import FolioDomain
import SwiftUI

/// The only place colors, spacing, radii and type sizes are defined. Screens use these and nothing else.
/// Content surfaces are paper-like; glass is left to the system chrome (sidebar, toolbar) and floating controls.
enum Theme {
    enum Palette {
        /// Behind the cards; the content area reads as a quiet surface, not a sheet of paper.
        static let page = Color(light: 0xF2F1EE, dark: 0x1B1A19)
        /// Dims the window behind a floating palette so the palette holds focus.
        static let scrim = Color.black.opacity(0.35)
        static let card = Swatch.card.color
        static let column = Color(light: 0xE9E7E2, dark: 0x21201E)
        static let window = Color(light: 0xF7F6F3, dark: 0x22211F)
        static let fill = Swatch.fill.color
        static let line = Swatch.line.color
        static let lineSoft = Swatch.lineSoft.color
        /// Dashed outlines of rows not made yet: a plain line vanishes against the page in light mode.
        static let lineStrong = Color(light: 0xBCB7AC, dark: 0x5A5752)
        static let text = Swatch.text.color
        static let textSecondary = Swatch.textSecondary.color
        static let textTertiary = Swatch.textTertiary.color

        /// Text and symbols on a filled accent or tone color.
        static let onFill = Color.white

        /// A guide line on the window frame (the sidebar's term line): ink laid thin like the selection, since a solid
        /// gray sat as a dark groove on the dark frame.
        static let chromeLine = Color(light: 0x2E2C28, dark: 0xE8E5E0, lightOpacity: 0.14, darkOpacity: 0.20)
        /// The chosen sidebar row outside a course: ink laid thin over the frame, so it reads on any wallpaper behind it.
        static let sidebarSelection = Color(light: 0x2E2C28, dark: 0xE8E5E0, lightOpacity: 0.08, darkOpacity: 0.10)
        /// Icons on the window frame (sidebar, toolbar, breadcrumb). Darker than `textSecondary` in light: the frame's
        /// vibrancy lifts symbols, and the secondary gray came out faint on a light wallpaper.
        static let chromeIcon = Color(light: 0x2E2C28, dark: 0xE8E5E0)
        /// Quiet text on the window frame (add rows, the search field's placeholder and key). The page's tertiary gray
        /// vanished into a light wallpaper showing through the frame, so light keeps it dark and lets weight and size
        /// carry the quiet.
        static let chromeText = Color(light: 0x4A4741, dark: 0xADA9A2)
        /// Over the window material, a faint layer that mutes the wallpaper's hue: white in light, the page's warm dark in
        /// dark. Kept thin because a strong white over the regular material read as milk.
        static let frameTint = Color(light: 0xFFFFFF, dark: 0x1B1A19, lightOpacity: 0.40, darkOpacity: 0.36)

        static let warning = Color(light: 0x8A4B00, dark: 0xF0B46A)
        static let warningFill = Color(light: 0xFBE9D0, dark: 0x3A2C18)
        /// Head of a notice card: in dark the plain fill sinks into the card below it, so it steps up.
        static let warningBanner = Color(light: 0xFBE9D0, dark: 0x54401F)
        static let danger = Color(light: 0x9C3A1E, dark: 0xF08A70)
        static let dangerFill = Color(light: 0xFBE4DD, dark: 0x3A201A)
        static let success = Color(light: 0x1E7D4F, dark: 0x5FCF98)

        /// Behind the words the quick add reads as a date, as Todoist marks them while typing.
        static let highlightFill = Color(light: 0xC2DAF7, dark: 0x2F5C9E)
    }

    /// Chart series in fixed order, checked with the dataviz palette validator against the card surface in both
    /// appearances (CVD ΔE ≥ 21, contrast ≥ 3:1). Series 1 is the default single hue.
    enum Series {
        static let one = Color(light: 0x4A6CB2, dark: 0x6A8BD0)
        static let two = Color(light: 0xEB6834, dark: 0xD95926)
        /// Series 1's lightness partner for a second measure drawn as another mark type (bars and a line).
        /// Fails the categorical lightness band by design; it passes CVD ΔE ≥ 19 against `one`, and the mark tells them apart too.
        static let oneCompanion = Color(light: 0x1B3363, dark: 0xB3C9F2)
    }

    enum Opacity {
        /// A tone or accent laid behind text of the same color: `Chip`, `DdayChip`, a picked toggle, `CourseAccent.tint`.
        static let tint = 0.12
        /// The projected part of a bar, lighter than what is already earned.
        static let projected = 0.28
        /// The text color washed over the window frame for a field or a track (`toolbarField()`, compact `Segmented`):
        /// see-through like the frame, where a solid fill stood alone on the material.
        static let wash = 0.06
        /// Under a frame control the pointer is over, and while it is pressed (`.toolbar` buttons).
        static let hover = 0.08
        static let pressed = 0.14
        /// The edge of a washed field, which without it washed out on a light wallpaper.
        static let edge = 0.12
        /// The fill inside a chosen row's line icon (`LineIcon(filled:)`).
        static let innerFill = 0.24
        /// Today's course wash at the page's top (`TodayWash`), and the class under way within it. Each accent is
        /// already tuned per appearance, so one value reads in both.
        static let courseWash = 0.24
        static let courseWashFocus = 0.40
    }

    enum Space {
        /// A title and the detail line under it.
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        /// An icon and its word, chips in a row.
        static let tight: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        /// Between the blocks of a page.
        static let section: CGFloat = 28
        static let xxl: CGFloat = 32
    }

    /// Padding of the shapes that repeat across screens, so a new one sits like the old ones.
    enum Inset {
        /// `CardRow`, the `NoticeCard` banner.
        static let row = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        /// A row in a list column with no card around it (notes, people, recent sessions).
        static let listRow = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        /// A caption-sized option that lights in the accent when on, and `Segmented`'s options.
        static let toggle = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        /// `Chip`, `DdayChip`.
        static let tag = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        /// Capsule controls: `.chip()`, `.pill()`, `SearchField`.
        static let control = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        /// A `StatStrip` cell.
        static let stat = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        /// Inside a card that is one thing (a tile, a panel) rather than rows.
        static let panel: CGFloat = 14
    }

    enum Radius {
        /// Legend swatches and other marks a few points wide.
        static let mark: CGFloat = 2
        /// Key caps and thumbnails inside a row.
        static let small: CGFloat = 4
        static let tile: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let floating: CGFloat = 16
    }

    enum Size {
        static let pageMaxWidth: CGFloat = 900
        /// Today's course wash: how far down it reaches, each course's glow radius in it, and the lone glow of the class
        /// under way, wider since it's the only one.
        static let washHeight: CGFloat = 480
        static let washReach: CGFloat = 220
        static let washReachFocus: CGFloat = 400
        static let courseColumn: CGFloat = 256
        static let sidebar: CGFloat = 216
        static let claudePanel: CGFloat = 380
        /// The round button a page's floating panel opens from (a course's Claude), at the content's bottom trailing corner.
        static let fab: CGFloat = 44
        /// How far the content panel sits in from the window's right and bottom edges (and its left, sidebar folded).
        static let panelInset: CGFloat = 4
        static let dot: CGFloat = 8
        static let rowHeight: CGFloat = 44
        static let tile: CGFloat = 22
        static let toolbarButton: CGFloat = 32
        /// The window's search field, centered in the toolbar row.
        static let searchField: CGFloat = 320
    }

    enum Typeface {
        static let pageTitle = Font.system(size: 28, weight: .bold)
        static let columnTitle = Font.system(size: 19, weight: .bold)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let figure = Font.system(size: 26, weight: .bold).monospacedDigit()
        static let figureCompact = Font.system(size: 22, weight: .bold).monospacedDigit()
        /// A day of the month or a letter grade leading a row.
        static let figureMedium = Font.system(size: 17, weight: .bold)
        static let figureSmall = Font.system(size: 16, weight: .semibold).monospacedDigit()
        /// Text the user reads or writes at length: a quiz prompt, the quick add field.
        static let bodyLarge = Font.system(size: 15)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 12)
        /// File names and paths.
        static let mono = Font.system(size: 12, design: .monospaced)
        static let label = Font.system(size: 11, weight: .semibold)
    }

    /// SF Symbols sized by role. A symbol beside text takes the text's font instead.
    enum Glyph {
        /// ✕ and ✓ inside a chip or a cell.
        static let tiny = Font.system(size: 8, weight: .bold)
        /// Disclosure chevrons and the ⌃⌄ of a menu chip.
        static let small = Font.system(size: 10, weight: .bold)
        /// A + or ✓ standing alone in a row.
        static let regular = Font.system(size: 11, weight: .semibold)
        /// Round check buttons.
        static let check = Font.system(size: 16)
        /// A window toolbar button.
        static let toolbar = Font.system(size: 15)
        /// A `LineIcon`: every list and sidebar symbol at one size, so their strokes match.
        static let line = Font.system(size: lineSize)
        /// `line`'s point size, for icons drawn by hand to match its symbols (`FolderIcon`).
        static let lineSize: CGFloat = 16
        /// A line icon beside a column's title, a size up so it holds its own next to the bold title. It keeps the
        /// list's 22pt slot, so the title still lines up with the rows' words below.
        static let lineTitle = Font.system(size: 20)
        /// The floating action button's symbol.
        static let fab = Font.system(size: 18, weight: .semibold)
        /// A panel's send button or empty-state symbol.
        static let large = Font.system(size: 22)
    }
}

/// A light and dark pair kept as hex, for the colors note pages also need as CSS (`NoteStyle`).
struct Swatch {
    let light: UInt32, dark: UInt32

    var color: Color { Color(light: light, dark: dark) }

    static let card = Swatch(light: 0xFFFFFF, dark: 0x272624)
    static let fill = Swatch(light: 0xEDEBE6, dark: 0x33312E)
    static let line = Swatch(light: 0xD9D5CC, dark: 0x3A3835)
    static let lineSoft = Swatch(light: 0xE2DED6, dark: 0x302E2B)
    static let text = Swatch(light: 0x1F1E1C, dark: 0xEEEDEA)
    static let textSecondary = Swatch(light: 0x56524C, dark: 0xBAB6AF)
    static let textTertiary = Swatch(light: 0x7A766F, dark: 0x8F8A83)
}

/// A course's accent. `course.json` stores a `#RRGGBB` from the color picker or, in older files, a preset name;
/// courses without one get a stable preset by position.
struct CourseAccent: Hashable {
    let light: UInt32, dark: UInt32
    /// Text on a light tint of the accent; darker than `color` so it stays readable.
    let inkLight: UInt32, inkDark: UInt32

    var color: Color { Color(light: light, dark: dark) }
    var ink: Color { Color(light: inkLight, dark: inkDark) }
    var tint: Color { color.opacity(Theme.Opacity.tint) }

    /// A picked color shows as picked in both appearances; only the ink shifts toward black or white.
    init(hex: UInt32) {
        self.init(light: hex, dark: hex, inkLight: Self.mix(hex, 0x000000, 0.45), inkDark: Self.mix(hex, 0xFFFFFF, 0.55))
    }

    init(light: UInt32, dark: UInt32, inkLight: UInt32, inkDark: UInt32) {
        self.light = light
        self.dark = dark
        self.inkLight = inkLight
        self.inkDark = inkDark
    }

    static let gray = CourseAccent(light: 0x706C66, dark: 0x9A98A8, inkLight: 0x4A4741, inkDark: 0xC9C7D6)

    /// Gray is left out: it reads as "no color" next to the others.
    static let presets: [(name: String, accent: CourseAccent)] = [
        ("violet", .init(light: 0x6D5BD0, dark: 0x9D8CFF, inkLight: 0x3D2F9E, inkDark: 0xC4BAFF)),
        ("blue", .init(light: 0x2F7FE0, dark: 0x5AA2FF, inkLight: 0x1D5FAE, inkDark: 0xA9CDFF)),
        ("orange", .init(light: 0xD9822B, dark: 0xF0A050, inkLight: 0x7A4510, inkDark: 0xF5BE86)),
        ("green", .init(light: 0x1F9D7A, dark: 0x3CC79C, inkLight: 0x13694F, inkDark: 0x7FE0C0)),
        ("pink", .init(light: 0xC2477A, dark: 0xF0709F, inkLight: 0x8E2A55, inkDark: 0xF5A3C1)),
        ("olive", .init(light: 0x8A8A3C, dark: 0xC9C25A, inkLight: 0x5C5C22, inkDark: 0xE0DA8A)),
        ("teal", .init(light: 0x1D8FA8, dark: 0x4CC3D9, inkLight: 0x125F70, inkDark: 0x8ADCEA)),
        ("red", .init(light: 0xC4473A, dark: 0xF07A6A, inkLight: 0x8A2A20, inkDark: 0xF5A79C)),
    ]

    /// Which preset an unset color falls back to is `CourseColor`'s, shared with the folio command.
    static func resolve(token stored: String, position: Int) -> CourseAccent {
        let token = CourseColor.token(stored, position: position)
        if let hex = hex(token) { return CourseAccent(hex: hex) }
        if token == "gray" { return .gray }
        return presets.first { $0.name == token }?.accent ?? presets[0].accent
    }

    static func hex(_ token: String) -> UInt32? {
        guard token.count == 7, token.first == "#" else { return nil }
        return UInt32(token.dropFirst(), radix: 16)
    }

    static func token(_ color: Color.Resolved) -> String {
        let byte = { (c: Float) in Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { sum, shift in
            let x = Double(a >> shift & 0xFF), y = Double(b >> shift & 0xFF)
            return sum | UInt32((x + (y - x) * t).rounded()) << shift
        }
    }
}

extension EnvironmentValues {
    @Entry var accent: CourseAccent = .gray
}

extension Color {
    /// A color that follows the light or dark appearance. Hex values keep the tokens readable against the design file.
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark, alpha: darkOpacity) : NSColor(hex: light, alpha: lightOpacity)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkOpacity) : UIColor(hex: light, alpha: lightOpacity)
        })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

extension Workspace {
    /// `token` previews a color before it is saved; nil uses the stored one.
    func accent(_ id: UUID, token: String? = nil) -> CourseAccent {
        guard let course = course(id) else { return .gray }
        let siblings = semester(of: course.file.course).map { courses(in: $0).map(\.id) } ?? []
        return CourseAccent.resolve(token: token ?? course.file.course.color, position: siblings.firstIndex(of: id) ?? 0)
    }
}
