import FolioDomain
import SwiftUI

enum Theme {
    enum Palette {
        static let page = Color(light: 0xF2F1EE, dark: 0x1B1A19)
        static let scrim = Color.black.opacity(0.35)
        static let card = Swatch.card.color
        static let column = Color(light: 0xE9E7E2, dark: 0x21201E)
        static let window = Color(light: 0xF7F6F3, dark: 0x22211F)
        static let fill = Swatch.fill.color
        static let currentPage = Color(light: Swatch.fill.light, dark: 0x4A4743)
        static let line = Swatch.line.color
        static let lineSoft = Swatch.lineSoft.color
        static let lineStrong = Color(light: 0xBCB7AC, dark: 0x5A5752)
        static let text = Swatch.text.color
        static let textSecondary = Swatch.textSecondary.color
        static let textTertiary = Swatch.textTertiary.color

        static let onFill = Color.white

        static let chromeLine = Color(light: 0x2E2C28, dark: 0xE8E5E0, lightOpacity: 0.14, darkOpacity: 0.20)
        static let sidebarSelection = Color(light: 0x2E2C28, dark: 0xE8E5E0, lightOpacity: 0.08, darkOpacity: 0.10)
        static let chromeIcon = Color(light: 0x2E2C28, dark: 0xE8E5E0)
        static let chromeSelected = Color.accentColor
        static let chromeText = Color(light: 0x4A4741, dark: 0xADA9A2)
        static let frameTint = Color(light: 0xFFFFFF, dark: 0x1B1A19, lightOpacity: 0.40, darkOpacity: 0.36)
        static let frame = Color(light: 0xE6E4E0, dark: 0x111010)

        static let warning = Color(light: 0x8A4B00, dark: 0xF0B46A)
        static let warningFill = Color(light: 0xFBE9D0, dark: 0x3A2C18)
        static let warningBanner = Color(light: 0xFBE9D0, dark: 0x54401F)
        static let danger = Color(light: 0x9C3A1E, dark: 0xF08A70)
        static let dangerFill = Color(light: 0xFBE4DD, dark: 0x3A201A)
        // 앱 아이콘(app/resources/AppIcon.icon)의 색이다. 위 막대는 잉크색, 아래 두 막대는 코랄색이고, 바탕은 흰색이며
        // 다크에서는 검은색에 가깝다.
        static let markInk = Color(light: 0x2B2B30, dark: 0xF2F0EC)
        static let markCoral = Color(light: 0xFF7A59, dark: 0xFF8F73)
        static let markBack = Color(light: 0xFFFFFF, dark: 0x1D1D1D)
        static let success = Color(light: 0x1E7D4F, dark: 0x5FCF98)
        static let info = Color(light: 0x1D4A8A, dark: 0x8DB8F2)
        static let infoFill = Color(light: 0xE3EEFB, dark: 0x1C2C42)

        static let readDue = Color(light: 0xC2DAF7, dark: 0x2F5C9E)
        static let readDueInk = Color(light: 0x1D4A8A, dark: 0xDCE9FC)
        static let readFolder = Color(light: 0xE8D5AE, dark: 0x544631)
        static let readFolderInk = Color(light: 0x5A4417, dark: 0xF0DEB8)
    }

    // dataviz 팔레트 검사기로 두 모드의 카드 면에 대해 검사한 값이다(CVD ΔE ≥ 21, 대비 ≥ 3:1).
    enum Series {
        static let one = Color(light: 0x3B5BDB, dark: 0x6489FE)
        static let two = Color(light: 0xE75534, dark: 0xEE5C3B)
        // 범주형 명도 범위를 일부러 벗어난다. `one`과의 CVD ΔE는 19 이상이고, 표시 종류도 둘을 구분한다.
        static let oneCompanion = Color(light: 0x2A3F9E, dark: 0xBED0FE)
    }

    enum Opacity {
        static let tint = 0.12
        static let onTint = 0.24
        static let toneRow = 0.5
        static let projected = 0.28
        static let wash = 0.06
        static let hover = 0.08
        static let pressed = 0.14
        static let disabled = 0.45
        static let scrim = 0.16
        static let figureScrim = 0.6
        static let edge = 0.12
        static let innerFill = 0.24
        static let duotone = 0.14
        static let ended = 0.45
        static let secondaryInk = 0.7
        static let courseWash = 0.24
        static let voiceGlow = 0.5
        static let toneEdge = 0.25
        static let liveEdge = 0.55
        static let planned = 0.5
        static let zoneAlt = 0.18
        static let zonePicked = 0.3
        static let folded = 0.32
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let tight: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let section: CGFloat = 28
        static let xxl: CGFloat = 32
    }

    enum Inset {
        static let row = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        static let listRow = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        static let toggle = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        static let tag = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        static let control = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        static let stat = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        static let panel: CGFloat = 14
    }

    enum Radius {
        static let mark: CGFloat = 2
        static let small: CGFloat = 4
        static let tile: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        static let floating: CGFloat = 16
        static let strip: CGFloat = 12
    }

    enum Size {
        static let pageMaxWidth: CGFloat = 900
        static let washHeight: CGFloat = 480
        static let washReach: CGFloat = 220
        static let washReachFocus: CGFloat = 400
        static let courseColumn: CGFloat = 256
        static let noteOutline: CGFloat = 224
        static let noteOutlinePopover = CGSize(width: 280, height: 400)
        #if os(iOS)
        static let chromeScale: CGFloat = 36 / 32
        #else
        static let chromeScale: CGFloat = 1
        #endif
        static func chrome(_ mac: CGFloat) -> CGFloat { (mac * chromeScale / 2).rounded() * 2 }
        static let sidebar: CGFloat = chrome(216)
        static let sidebarRow: CGFloat = chrome(32)
        static let claudePanel: CGFloat = 380
        static let fab: CGFloat = 44
        static let panelInset: CGFloat = 4
        static let paneMin: CGFloat = 360
        #if os(iOS)
        static let paneStrip: CGFloat = 44
        #else
        static let paneStrip: CGFloat = 40
        #endif
        static let dot: CGFloat = 8
        static let appMark: CGFloat = 24
        static let appMarkLarge: CGFloat = 64
        static let firstRunColumn: CGFloat = 560
        static let firstRunNarrow: CGFloat = 640
        static let firstRunWindow = CGSize(width: 960, height: 600)
        static let optionTile: CGFloat = 40
        static let radio: CGFloat = 20
        static let pageThumbnail = CGSize(width: 152, height: 84)
        static let rowHeight: CGFloat = 44
        static let touchTarget: CGFloat = 44
        static let tile: CGFloat = 22
        static let toolbarButton: CGFloat = chrome(32)
        #if os(iOS)
        static let toolbarRow: CGFloat = toolbarButton + Space.xs * 2
        #else
        static let toolbarRow: CGFloat = 48
        #endif
        #if os(iOS)
        static let searchField: CGFloat = 160
        #else
        static let searchField: CGFloat = 120
        #endif
        static let tabName: CGFloat = 120
        // `windowMin`보다 좁으면 세 열이 페이지의 그림을 가늘게 눌렀다. 고정된 기본 크기가 노트북 화면보다 넓으면
        // macOS가 창을 화면 끝까지 늘였으므로, 새 창은 화면에서 보이는 영역의 `windowShare`만큼 차지하고 큰 화면에서는
        // `windowIdeal`까지만 커진다(`WindowSize`).
        static let windowMin = CGSize(width: 1120, height: 640)
        static let windowIdeal = CGSize(width: 1440, height: 900)
        static let windowShare = 0.9
    }

    enum Motion {
        static let quick = Animation.snappy(duration: 0.2)
        static let standard = Animation.snappy(duration: 0.25)
        static let settle = Animation.snappy(duration: 0.35)
        // `PaneGlide`는 칸 폭을 이 곡선으로 움직이고, `PaneRow`가 나머지를 애니메이션한다. 두 곳이 다른 타이밍을 쓰면
        // 칸의 가장자리가 이웃이 멈추기 전에 도착하므로 같은 값을 쓴다.
        static let paneSpring = Spring.smooth(duration: 0.34)
        static let pane = Animation.spring(paneSpring)
    }

    enum Typeface {
        static let pageTitle = Font.system(size: 28, weight: .bold)
        static let columnTitle = Font.system(size: 19, weight: .bold)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let figure = Font.system(size: 26, weight: .bold).monospacedDigit()
        static let figureCompact = Font.system(size: 22, weight: .bold).monospacedDigit()
        static let figureMedium = Font.system(size: 17, weight: .bold)
        static let figureSmall = Font.system(size: 16, weight: .semibold).monospacedDigit()
        static let bodyLarge = Font.system(size: bodyLargeSize)
        static let bodyLargeSize = CGFloat(15)
        static let body = Font.system(size: bodySize)
        static let bodySize = CGFloat(13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let sidebar = Font.system(size: (bodySize * Size.chromeScale).rounded())
        static let caption = Font.system(size: 12)
        static let mono = Font.system(size: 12, design: .monospaced)
        static let label = Font.system(size: 11, weight: .semibold)
    }

    enum Glyph {
        static let tiny = Font.system(size: 8, weight: .bold)
        static let small = Font.system(size: 10, weight: .bold)
        static let regular = Font.system(size: 11, weight: .semibold)
        static let check = Font.system(size: 16)
        static let toolbar = Font.system(size: toolbarSize)
        static let toolbarSize: CGFloat = 15  // design: one-off. A type size, which the grid leaves out.
        static let line = Font.system(size: lineSize)
        static let lineSize: CGFloat = 16
        static let lineTitle = Font.system(size: 20)
        static let fab = Font.system(size: 18, weight: .semibold)
        static let large = Font.system(size: 22)
    }
}

struct Swatch {
    let light: UInt32, dark: UInt32

    var color: Color { Color(light: light, dark: dark) }

    static let card = Swatch(light: 0xFFFFFF, dark: 0x272624)
    static let fill = Swatch(light: 0xEDEBE6, dark: 0x33312E)
    static let codeFill = Swatch(light: 0xF5F4F0, dark: 0x33312E)
    static let line = Swatch(light: 0xD9D5CC, dark: 0x3A3835)
    static let lineSoft = Swatch(light: 0xE2DED6, dark: 0x302E2B)
    static let text = Swatch(light: 0x1F1E1C, dark: 0xEEEDEA)
    static let textSecondary = Swatch(light: 0x56524C, dark: 0xBAB6AF)
    static let textTertiary = Swatch(light: 0x7A766F, dark: 0x8F8A83)
}

struct CourseAccent: Hashable {
    let light: UInt32, dark: UInt32
    // tint 위에서 읽히도록 `color`보다 어둡게 둔다(카드와 페이지 위의 tint에서 4.5:1).
    let inkLight: UInt32, inkDark: UInt32
    // 흰 글자 뒤에 깔도록 `color`를 흰색 대비 4.5:1까지 어둡게 한다. 다크에서 잉크는 tint 위의 글에 필요한 옅은 색이라
    // 흰 글자가 묻히므로, 잉크로는 채울 수 없다.
    let fillLight: UInt32, fillDark: UInt32

    var color: Color { Color(light: light, dark: dark) }
    var ink: Color { Color(light: inkLight, dark: inkDark) }
    var fill: Color { Color(light: fillLight, dark: fillDark) }
    var tint: Color { color.opacity(Theme.Opacity.tint) }
    var read: Color { color.opacity(Theme.Opacity.onTint) }

    static let gray = CourseAccent(
        light: 0x706C66, dark: 0x9A98A8, inkLight: 0x4A4741, inkDark: 0xC9C7D6, fillLight: 0x706C66, fillDark: 0x747287)

    // 라이트 값은 `CourseColor.anchors`와 같아야 한다.
    static let presets: [(name: String, accent: CourseAccent)] = [
        ("violet", .init(light: 0x8B7CF6, dark: 0xA49CFE, inkLight: 0x5B45BA, inkDark: 0xC2BFFF, fillLight: 0x705DF4, fillDark: 0x685AFD)),
        ("blue", .init(light: 0x3B5BDB, dark: 0x87A7FF, inkLight: 0x2D48C6, inkDark: 0xAEC5FF, fillLight: 0x3B5BDB, fillDark: 0x3067FF)),
        ("orange", .init(light: 0xE9A02C, dark: 0xFFB547, inkLight: 0x7E5101, inkDark: 0xFCC77F, fillLight: 0xA16911, fillDark: 0xA86400)),
        ("green", .init(light: 0x2D7A62, dark: 0x77BBA3, inkLight: 0x0C634C, inkDark: 0x93D4BC, fillLight: 0x2D7A62, fillDark: 0x407F69)),
        ("pink", .init(light: 0xFF3D7F, dark: 0xFF799B, inkLight: 0xAD004C, inkDark: 0xFFADBE, fillLight: 0xE8004F, fillDark: 0xE9003B)),
        ("olive", .init(light: 0x8A8A3C, dark: 0xC9C25A, inkLight: 0x5C5C22, inkDark: 0xE0DA8A, fillLight: 0x787834, fillDark: 0x7B7628)),
        ("teal", .init(light: 0x1D8FA8, dark: 0x4CC3D9, inkLight: 0x125F70, inkDark: 0x8ADCEA, fillLight: 0x1A7E94, fillDark: 0x1F7F91)),
        ("red", .init(light: 0xFF6B4A, dark: 0xFE8165, inkLight: 0xA92602, inkDark: 0xFEB19F, fillLight: 0xE02900, fillDark: 0xDF2A01)),
        (
            "graphite",
            .init(light: 0x6E6B66, dark: 0xA8A49E, inkLight: 0x46433E, inkDark: 0xD2CEC8, fillLight: 0x6E6B66, fillDark: 0x79746C)
        ),
    ]

    static func resolve(token stored: String, position: Int) -> CourseAccent {
        let token = CourseColor.token(stored, position: position)
        return presets.first { $0.name == token }?.accent ?? presets[0].accent
    }
}

extension EnvironmentValues {
    @Entry var accent: CourseAccent = .gray
}

extension View {
    // 과목 색이 뷰에 닿는 길은 이것 하나다. 과목을 읽는 것(점, 채움, 주 버튼)은 `\.accent`를, ghost 버튼은 `.tint`를
    // 읽는다. 둘을 따로 주면 accent만 받은 시트가 주 버튼은 과목 색으로, ghost 버튼은 시스템 색으로 그렸다. 과목이 없는
    // `.gray`는 tint를 시스템에 맡긴다.
    func courseAccent(_ accent: CourseAccent) -> some View {
        environment(\.accent, accent).tint(accent == .gray ? nil : accent.ink)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        #if os(macOS)
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: dark, alpha: darkOpacity) : NSColor(hex: light, alpha: lightOpacity)
            })
        #else
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkOpacity) : UIColor(hex: light, alpha: lightOpacity)
            })
        #endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
#endif

extension Workspace {
    func accent(_ id: UUID, token: String? = nil) -> CourseAccent {
        guard let course = course(id) else { return .gray }
        let siblings = semester(of: course.file.course).map { courses(in: $0).map(\.id) } ?? []
        return CourseAccent.resolve(token: token ?? course.file.course.color, position: siblings.firstIndex(of: id) ?? 0)
    }
}
