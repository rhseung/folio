import Foundation

public struct ClassStartSettings: Codable, Sendable, Equatable {
    public enum Item: String, Codable, Sendable, CaseIterable {
        case recording, roughNote, lecture
    }

    public enum Recording: String, Codable, Sendable, CaseIterable {
        case off, ask, start
    }

    public enum RoughNote: String, Codable, Sendable, CaseIterable {
        case off
        case openExisting
        case create
    }

    public enum Lecture: String, Codable, Sendable, CaseIterable {
        case off, open
    }

    public enum Place: String, Codable, Sendable, CaseIterable {
        case here, beside, tab, window
    }

    public enum OpenIn: String, Codable, Sendable, CaseIterable {
        case splitTab, currentTab
    }

    public enum Screen: String, Codable, Sendable, CaseIterable {
        case front, notify
    }

    public var recording = Recording.off
    public var recordingOffsetMinutes = 0
    public var stopsRecording = false
    public var stopAfterMinutes = 0
    public var roughNote = RoughNote.off
    public var roughNotePlace = Place.here
    public var lecture = Lecture.off
    public var lecturePlace = Place.beside
    public var openIn = OpenIn.splitTab
    public var allLectures = false
    public var resumesLecture = true
    public var screen = Screen.notify
    public var preset: String?
    // JSON은 다른 타입을 키로 쓴 딕셔너리를 평평한 배열로 쓰므로, 과목 ID를 UUID가 아니라 문자열 키로 둔다.
    public var courseOff: [String: [Item]] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        recording = try c.value(.recording, or: d.recording)
        recordingOffsetMinutes = try c.value(.recordingOffsetMinutes, or: d.recordingOffsetMinutes)
        stopsRecording = try c.value(.stopsRecording, or: d.stopsRecording)
        stopAfterMinutes = try c.value(.stopAfterMinutes, or: d.stopAfterMinutes)
        roughNote = try c.value(.roughNote, or: d.roughNote)
        roughNotePlace = try c.value(.roughNotePlace, or: d.roughNotePlace)
        lecture = try c.value(.lecture, or: d.lecture)
        lecturePlace = try c.value(.lecturePlace, or: d.lecturePlace)
        openIn = try c.value(.openIn, or: d.openIn)
        allLectures = try c.value(.allLectures, or: d.allLectures)
        resumesLecture = try c.value(.resumesLecture, or: d.resumesLecture)
        screen = try c.value(.screen, or: d.screen)
        preset = try c.decodeIfPresent(String.self, forKey: .preset)
        courseOff = try c.value(.courseOff, or: d.courseOff)
    }

    public func off(for course: UUID) -> Set<Item> { Set(courseOff[course.uuidString] ?? []) }

    public mutating func setOff(_ items: Set<Item>, for course: UUID) {
        courseOff[course.uuidString] = items.isEmpty ? nil : Item.allCases.filter(items.contains)
    }

    public func isOn(_ item: Item, course: UUID) -> Bool {
        guard !off(for: course).contains(item) else { return false }
        return switch item {
        case .recording: recording != .off
        case .roughNote: roughNote != .off
        case .lecture: lecture != .off
        }
    }

    public func isOn(for course: UUID) -> Bool { Item.allCases.contains { isOn($0, course: course) } }

    func lead(course: UUID) -> TimeInterval {
        isOn(.recording, course: course) ? TimeInterval(max(0, -recordingOffsetMinutes) * 60) : 0
    }
}
