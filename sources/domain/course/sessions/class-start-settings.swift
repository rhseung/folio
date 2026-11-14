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

    public var recording: Recording = SettingItem.classRecording.choice()
    public var recordingOffsetMinutes = SettingItem.classRecordingOffset.int
    public var stopsRecording = SettingItem.classStopsRecording.bool
    public var stopAfterMinutes = SettingItem.classStopAfter.int
    public var roughNote: RoughNote = SettingItem.classRoughNote.choice()
    public var roughNotePlace: Place = SettingItem.classRoughNotePlace.choice()
    public var lecture: Lecture = SettingItem.classLecture.choice()
    public var lecturePlace: Place = SettingItem.classLecturePlace.choice()
    public var openIn: OpenIn = SettingItem.classOpenIn.choice()
    public var allLectures = SettingItem.classAllLectures.bool
    public var resumesLecture = SettingItem.classResumesLecture.bool
    public var screen: Screen = SettingItem.classScreen.choice()
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

    public func isOn(_ item: Item) -> Bool {
        switch item {
        case .recording: recording != .off
        case .roughNote: roughNote != .off
        case .lecture: lecture != .off
        }
    }

    public func isOn(_ item: Item, course: UUID) -> Bool { !off(for: course).contains(item) && isOn(item) }

    public func isOn(for course: UUID) -> Bool { Item.allCases.contains { isOn($0, course: course) } }

    func lead(course: UUID) -> TimeInterval {
        isOn(.recording, course: course) ? TimeInterval(max(0, -recordingOffsetMinutes) * 60) : 0
    }
}
