import Foundation

/// What was picked on the quick-add line's chips over what the line reads: a course, a deadline, the repeat.
///
/// A pick holds while the line keeps reading what it read when the pick was made, so typing more of the title leaves a
/// corrected course or deadline alone. Once the typing reads that field differently (another course named, another
/// day typed), the typing is the newer word and the pick goes.
public struct QuickAddPicks: Equatable, Sendable {
    public struct Pick<Value: Equatable & Sendable>: Equatable, Sendable {
        public var value: Value
        /// What the line read for this field when the pick was made.
        public var read: Value
    }

    public var course: Pick<UUID?>?
    public var due: Pick<Date?>?
    public var repeats: Pick<AssignmentRepeat?>?

    public init() {}

    public var isEmpty: Bool { course == nil && due == nil && repeats == nil }

    public mutating func pickCourse(_ id: UUID?, over read: QuickAdd) { course = Pick(value: id, read: read.courseId) }
    public mutating func pickDue(_ date: Date?, over read: QuickAdd) { due = Pick(value: date, read: read.due) }
    public mutating func pickRepeats(_ repeats: AssignmentRepeat?, over read: QuickAdd) {
        self.repeats = Pick(value: repeats, read: read.repeats)
    }

    /// Drops the picks whose field the line now reads differently.
    public mutating func keep(over read: QuickAdd) {
        if course?.read != read.courseId { course = nil }
        if due?.read != read.due { due = nil }
        if repeats?.read != read.repeats { repeats = nil }
    }

    public func applied(to read: QuickAdd) -> QuickAdd {
        var r = read
        if let course, course.read == read.courseId { r.courseId = course.value }
        if let due, due.read == read.due { r.due = due.value }
        if let repeats, repeats.read == read.repeats { r.repeats = repeats.value }
        return r
    }
}
