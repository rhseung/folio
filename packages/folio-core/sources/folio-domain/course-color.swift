/// The color names `course.json` stores and the order an unset color falls back through. The app's Theme and the
/// folio command both read this, so a course shows the same color in the app and in the terminal.
public enum CourseColor {
    public static let presets = ["violet", "blue", "orange", "green", "pink", "olive", "teal", "red"]

    /// The stored `#RRGGBB`, `gray`, or preset name; anything else (an empty or unknown value) is the preset at the
    /// course's place among its semester's courses.
    public static func token(_ stored: String, position: Int) -> String {
        if stored.count == 7, stored.first == "#", UInt32(stored.dropFirst(), radix: 16) != nil { return stored }
        if stored == "gray" || presets.contains(stored) { return stored }
        return presets[position % presets.count]
    }
}
