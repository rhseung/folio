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
        /// The wash behind the page a PDF is on, in its page strip. `fill` in light; in dark `fill` sat a shade off the
        /// strip and the white page drew the eye from it, so it is lifted to read at a glance, still a grey so it never
        /// passes for the course's line or the picked ring.
        static let currentPage = Color(light: Swatch.fill.light, dark: 0x4A4743)
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
        /// The chosen sidebar row's icon: the system accent, so it follows the accent picked in System Settings.
        static let chromeSelected = Color.accentColor
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
        /// The app icon's colors (app/resources/AppIcon.icon), for the mark the first run draws: its top bar in ink,
        /// the two below in coral, on white or, in dark, near black.
        static let markInk = Color(light: 0x2B2B30, dark: 0xF2F0EC)
        static let markCoral = Color(light: 0xFF7A59, dark: 0xFF8F73)
        static let markBack = Color(light: 0xFFFFFF, dark: 0x1D1D1D)
        static let success = Color(light: 0x1E7D4F, dark: 0x5FCF98)
        /// Neutral news, neither good nor a warning: a release's new features beside its fixes (green) and changes (amber).
        static let info = Color(light: 0x1D4A8A, dark: 0x8DB8F2)
        static let infoFill = Color(light: 0xE3EEFB, dark: 0x1C2C42)

        /// What the quick add line read, behind the words in the line and on the chip under it for the same value, so
        /// the two read as a pair: the deadline and its repeat in blue, the assignment folder in sand; the course takes
        /// its own accent (`CourseAccent.read`). The folder's sand is off the course presets' hues: in violet it sat beside
        /// the first preset's course as one more of the same. Fills only, no outline: an outlined word read as unfinished. Solid
        /// enough to stand on the popover's glass, which a tint-strength chip blended into.
        static let readDue = Color(light: 0xC2DAF7, dark: 0x2F5C9E)
        static let readDueInk = Color(light: 0x1D4A8A, dark: 0xDCE9FC)
        static let readFolder = Color(light: 0xE8D5AE, dark: 0x544631)
        static let readFolderInk = Color(light: 0x5A4417, dark: 0xF0DEB8)
    }

    /// Chart series in fixed order, checked with the dataviz palette validator against the card surface in both
    /// appearances (CVD ΔE ≥ 21, contrast ≥ 3:1). Series 1 is the default single hue.
    enum Series {
        static let one = Color(light: 0x3B5BDB, dark: 0x6489FE)
        static let two = Color(light: 0xE75534, dark: 0xEE5C3B)
        /// Series 1's lightness partner for a second measure drawn as another mark type (bars and a line).
        /// Fails the categorical lightness band by design; it passes CVD ΔE ≥ 19 against `one`, and the mark tells them apart too.
        static let oneCompanion = Color(light: 0x2A3F9E, dark: 0xBED0FE)
    }

    enum Opacity {
        /// A tone or accent laid behind text of the same color: `Chip`, `DdayChip`, a picked toggle, `CourseAccent.tint`.
        static let tint = 0.12
        /// An accent capsule that can lie on the course's own tint (a class card's trailing row, under the live card's
        /// elapsed fill). At `tint` it blended into that fill once the class was nearly over; at twice it stands apart
        /// both on the card and on the fill.
        static let onTint = 0.24
        /// A row laid on its tone's fill (Today's near deadlines): at half strength, so the chip on the row, which uses the
        /// full fill, still stands apart from it.
        static let toneRow = 0.5
        /// The projected part of a bar, lighter than what is already earned.
        static let projected = 0.28
        /// The text color washed over the window frame for a field or a track (`toolbarField()`, compact `Segmented`):
        /// see-through like the frame, where a solid fill stood alone on the material.
        static let wash = 0.06
        /// Under a frame control the pointer is over, and while it is pressed (`.toolbar` buttons).
        static let hover = 0.08
        static let pressed = 0.14
        /// A frame button that can't be pressed now (`.toolbar`, the recording capsule's mark and stop).
        static let disabled = 0.45
        /// Black over the page while a folded column is open over it (`ColumnSplit`): the page stays readable behind
        /// the glass, and reads as set aside.
        static let scrim = 0.16
        /// Black over a note while one of its pictures is open large in the preview: the picture alone holds the eye.
        static let figureScrim = 0.6
        /// The edge of a washed field, which without it washed out on a light wallpaper.
        static let edge = 0.12
        /// The fill inside a chosen row's line icon (`LineIcon(filled:)`).
        static let innerFill = 0.24
        /// The inside of every sidebar icon (`LineIcon(duotone:)`), below the chosen one's `innerFill`.
        static let duotone = 0.14
        /// What's over and kept only for reference: Today's ended classes, the sidebar's past terms.
        static let ended = 0.45
        /// The quieter part of a chip's ink (the days left on the deadline chip): the chip's own hue, lighter, since the
        /// page's secondary gray went muddy on a colored fill.
        static let secondaryInk = 0.7
        /// Today's course wash at the page's top (`TodayWash`). Each accent is already tuned per appearance, so one value
        /// reads in both.
        static let courseWash = 0.24
        /// The recording card's corner at a lecturer's full voice. Strong, since it lies on the course's own tint: at
        /// `projected` a speaking voice hardly showed.
        static let voiceGlow = 0.5
        /// A tone's own line around or through its fill: the class card's tucked-in exam, the exam marker's rule.
        static let toneEdge = 0.25
        /// The accent line around a class under way: strong enough to mark it, under the full accent of its buttons.
        static let liveEdge = 0.55
        /// A class the timetable holds but not saved: half a card laid over the page.
        static let planned = 0.5
        /// Every other zone of a lecture's section bar (#321), over `tint`: two neighbors of one color still read as two.
        static let zoneAlt = 0.18
        /// The zone picked on a section bar, above `onTint`, which the zone under the pointer takes.
        static let zonePicked = 0.3
        /// The wash under an open `DisclosureRow`'s rows.
        static let folded = 0.32
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
        /// A thumbnail column's current-page wash and a class's run of pages under it: one corner, so the wash sits in
        /// the run as one shape.
        static let strip: CGFloat = 12
    }

    enum Size {
        static let pageMaxWidth: CGFloat = 900
        /// Today's course wash: how far down it reaches, each course's glow radius in it, and the lone glow of the class
        /// under way, wider since it's the only one.
        static let washHeight: CGFloat = 480
        static let washReach: CGFloat = 220
        static let washReachFocus: CGFloat = 400
        static let courseColumn: CGFloat = 256
        /// The outline beside a note (#387), and the most its popover takes where the note has no room for it.
        static let noteOutline: CGFloat = 224
        static let noteOutlinePopover = CGSize(width: 280, height: 400)
        static let sidebar: CGFloat = 216
        static let claudePanel: CGFloat = 380
        /// The round button a page's floating panel opens from (a course's Claude), at the content's bottom trailing corner.
        static let fab: CGFloat = 44
        /// How far the content panel sits in from the window's right and bottom edges (and its left, sidebar folded).
        static let panelInset: CGFloat = 4
        /// A pane of a tab of several (#62) never narrower: below it, the pane pressed longest ago folds into a strip.
        static let paneMin: CGFloat = 360
        /// A folded pane's strip, a finger's width on the iPad.
        #if os(iOS)
        static let paneStrip: CGFloat = 44
        #else
        static let paneStrip: CGFloat = 40
        #endif
        static let dot: CGFloat = 8
        /// The app's mark beside its name in the first run's step list, and alone on its welcome.
        static let appMark: CGFloat = 24
        static let appMarkLarge: CGFloat = 64
        /// The first run's steps read at this width at most, centered in the panel.
        static let firstRunColumn: CGFloat = 560
        /// Below this the first run drops its step list for one column with dots, as on an iPhone.
        static let firstRunNarrow: CGFloat = 640
        /// The icon square of a choice card (the folder step's 새로 시작 and 기존 폴더).
        static let optionTile: CGFloat = 40
        static let radio: CGFloat = 20
        /// The box a lecture's page is fitted into in its thumbnail column, whatever its shape: a 16:9 slide fills it,
        /// a 4:3 one is as tall and narrower. Wide for slides, which most lectures are.
        static let pageThumbnail = CGSize(width: 152, height: 84)
        static let rowHeight: CGFloat = 44
        /// The least a finger can hit on each side, whatever the drawn size (`TouchTarget`).
        static let touchTarget: CGFloat = 44
        static let tile: CGFloat = 22
        static let toolbarButton: CGFloat = 32
        /// The window's top row on the Mac, which the toolbar's capsules sit in the middle of (`TitleRow`).
        static let toolbarRow: CGFloat = 48
        /// The window's search field, after the tabs: wide enough for "검색 ⌘K", the tabs taking the row's room.
        static let searchField: CGFloat = 120
        /// The longest name on a tab behind the front one, which shows where it is in full.
        static let tabName: CGFloat = 120
        /// The Mac window. Narrower than `windowMin`, the three columns squeeze a page's figures into slivers. A new
        /// window takes `windowShare` of its screen's visible area, up to `windowIdeal` on a large display
        /// (`WindowSize`): a fixed default wider than a laptop screen made macOS stretch it edge to edge.
        static let windowMin = CGSize(width: 1120, height: 640)
        static let windowIdeal = CGSize(width: 1440, height: 900)
        static let windowShare = 0.9
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
        static let bodyLarge = Font.system(size: bodyLargeSize)
        /// For the quick add field's AppKit text view, which takes a size rather than a `Font`.
        static let bodyLargeSize = CGFloat(15)
        static let body = Font.system(size: bodySize)
        /// For text measured with the platform font (`GrowingTextEditor`).
        static let bodySize = CGFloat(13)
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
        static let toolbar = Font.system(size: toolbarSize)
        /// `toolbar`'s point size, for measuring a toolbar symbol's ink (`TabBar.plusInk`).
        static let toolbarSize: CGFloat = 15 // design: one-off. A type size, which the grid leaves out.
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
    /// Behind code in notes: `fill` reads heavy in light mode behind many lines of it.
    static let codeFill = Swatch(light: 0xF5F4F0, dark: 0x33312E)
    static let line = Swatch(light: 0xD9D5CC, dark: 0x3A3835)
    static let lineSoft = Swatch(light: 0xE2DED6, dark: 0x302E2B)
    static let text = Swatch(light: 0x1F1E1C, dark: 0xEEEDEA)
    static let textSecondary = Swatch(light: 0x56524C, dark: 0xBAB6AF)
    static let textTertiary = Swatch(light: 0x7A766F, dark: 0x8F8A83)
}

/// A course's accent: one of the presets, named in `course.json`. Courses without one get a stable preset by position,
/// and a `#RRGGBB` from before colors were limited to the presets reads as the nearest one (`CourseColor`).
struct CourseAccent: Hashable {
    let light: UInt32, dark: UInt32
    /// Text on a light tint of the accent; darker than `color` so it stays readable (4.5:1 on the tint over card and page).
    let inkLight: UInt32, inkDark: UInt32
    /// Behind white words (a `.prominent` button): `color` darkened to 4.5:1 against white. The ink can't fill, since in
    /// dark it is the pale shade text on a tint needs, and white on it washed out.
    let fillLight: UInt32, fillDark: UInt32

    var color: Color { Color(light: light, dark: dark) }
    var ink: Color { Color(light: inkLight, dark: inkDark) }
    var fill: Color { Color(light: fillLight, dark: fillDark) }
    var tint: Color { color.opacity(Theme.Opacity.tint) }
    /// The course as the quick add line read it (`Palette.readDue`): twice the tint, which faded into the popover.
    var read: Color { color.opacity(Theme.Opacity.onTint) }

    /// Where no course is in view (a paused recording, a proof callout). Not a course preset; `graphite` is.
    static let gray = CourseAccent(light: 0x706C66, dark: 0x9A98A8, inkLight: 0x4A4741, inkDark: 0xC9C7D6, fillLight: 0x706C66, fillDark: 0x747287)

    /// The app icon's palette, plus olive and teal so a busy term still gets eight, and graphite for a course that should
    /// stay quiet. Light values must match `CourseColor.anchors`. Graphite takes the paper's warm gray, since a pure gray
    /// read cold beside it; its ink sits past the colored inks' 5.5:1 so that text on its tint reads as plain text.
    static let presets: [(name: String, accent: CourseAccent)] = [
        ("violet", .init(light: 0x8B7CF6, dark: 0xA49CFE, inkLight: 0x5B45BA, inkDark: 0xC2BFFF, fillLight: 0x705DF4, fillDark: 0x685AFD)),
        ("blue", .init(light: 0x3B5BDB, dark: 0x87A7FF, inkLight: 0x2D48C6, inkDark: 0xAEC5FF, fillLight: 0x3B5BDB, fillDark: 0x3067FF)),
        ("orange", .init(light: 0xE9A02C, dark: 0xFFB547, inkLight: 0x7E5101, inkDark: 0xFCC77F, fillLight: 0xA16911, fillDark: 0xA86400)),
        ("green", .init(light: 0x2D7A62, dark: 0x77BBA3, inkLight: 0x0C634C, inkDark: 0x93D4BC, fillLight: 0x2D7A62, fillDark: 0x407F69)),
        ("pink", .init(light: 0xFF3D7F, dark: 0xFF799B, inkLight: 0xAD004C, inkDark: 0xFFADBE, fillLight: 0xE8004F, fillDark: 0xE9003B)),
        ("olive", .init(light: 0x8A8A3C, dark: 0xC9C25A, inkLight: 0x5C5C22, inkDark: 0xE0DA8A, fillLight: 0x787834, fillDark: 0x7B7628)),
        ("teal", .init(light: 0x1D8FA8, dark: 0x4CC3D9, inkLight: 0x125F70, inkDark: 0x8ADCEA, fillLight: 0x1A7E94, fillDark: 0x1F7F91)),
        ("red", .init(light: 0xFF6B4A, dark: 0xFE8165, inkLight: 0xA92602, inkDark: 0xFEB19F, fillLight: 0xE02900, fillDark: 0xDF2A01)),
        ("graphite", .init(light: 0x6E6B66, dark: 0xA8A49E, inkLight: 0x46433E, inkDark: 0xD2CEC8, fillLight: 0x6E6B66, fillDark: 0x79746C)),
    ]

    /// Which preset an unset color falls back to is `CourseColor`'s, shared with the folio command.
    static func resolve(token stored: String, position: Int) -> CourseAccent {
        let token = CourseColor.token(stored, position: position)
        return presets.first { $0.name == token }?.accent ?? presets[0].accent
    }
}

extension EnvironmentValues {
    @Entry var accent: CourseAccent = .gray
}

extension View {
    /// The one way a course's colour reaches a view: `\.accent` for what reads the course (dots, fills, the main
    /// button) and the tint for the ghost buttons, which read `.tint`. Set apart, a sheet given only the accent drew its
    /// main button in the course's colour and its ghost buttons in the system's. `.gray`, no course, leaves the tint to
    /// the system.
    func courseAccent(_ accent: CourseAccent) -> some View {
        environment(\.accent, accent).tint(accent == .gray ? nil : accent.ink)
    }
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
