import Foundation

/// The color names `course.json` stores and the order an unset color falls back through. The app's Theme and the
/// folio command both read this, so a course shows the same color in the app and in the terminal.
public enum CourseColor {
    /// The order an unset color falls back through.
    public static let cycle = ["violet", "blue", "orange", "green", "pink", "olive", "teal", "red"]
    /// Offered for a course that should stay quiet (a colloquium), but never picked for one left without a color: a
    /// course would turn gray without being asked.
    public static let neutral = "graphite"
    public static let presets = cycle + [neutral]

    /// Each colored name's light color, only to read a `#RRGGBB` saved before courses were limited to the presets as the
    /// nearest name. They are the light values of `CourseAccent.presets`; the app test `presetsReadAsThemselves` checks
    /// each still reads as its own name, graphite included.
    static let anchors: [(name: String, hex: UInt32)] = [
        ("violet", 0x8B7CF6), ("blue", 0x3B5BDB), ("orange", 0xE9A02C), ("green", 0x2D7A62),
        ("pink", 0xFF3D7F), ("olive", 0x8A8A3C), ("teal", 0x1D8FA8), ("red", 0xFF6B4A),
    ]
    /// OKLab chroma under which a saved color reads as the neutral. The mutedest preset, green, is at 0.085 and a slate
    /// blue at 0.07; a gray with a tint of blue or brown stays under 0.035.
    static let neutralChroma = 0.04

    public static func token(_ stored: String, position: Int) -> String {
        if presets.contains(stored) { return stored }
        // Courses from before the presets could name gray, which the app drew as its neutral.
        if stored == "gray" { return neutral }
        if stored.count == 7, stored.first == "#", let hex = UInt32(stored.dropFirst(), radix: 16) { return nearest(hex) }
        return cycle[position % cycle.count]
    }

    /// Nearest by OKLab distance, which follows how far apart colors look; RGB distance sends a dark navy to violet.
    /// Grays are split off first by chroma: by distance alone, where lightness counts as much as hue, a light gray
    /// reads as amber and a dark slate blue as graphite.
    static func nearest(_ hex: UInt32) -> String {
        let p = oklab(hex)
        if (p[1] * p[1] + p[2] * p[2]).squareRoot() < neutralChroma { return neutral }
        return anchors.min { a, b in
            let x = oklab(a.hex), y = oklab(b.hex)
            return zip(p, x).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) < zip(p, y).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
        }!.name
    }

    static func oklab(_ hex: UInt32) -> [Double] {
        let lin = [16, 8, 0].map { shift -> Double in
            let c = Double(hex >> UInt32(shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (lin[0], lin[1], lin[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }
}
