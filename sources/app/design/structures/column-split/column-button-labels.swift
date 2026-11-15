import SwiftUI

struct ColumnButtonLabels: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}
