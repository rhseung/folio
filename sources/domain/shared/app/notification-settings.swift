import Foundation

// 알림 종류마다 켜기와 시점을 한 표에 둔다. `settings.json`에는 종류 이름 아래 객체로 쓴다
// (`"notifications": {"examMorning": {"on": true, "minute": 480}}`). 종류마다 쓰는 칸과 기본값은 설정 항목 선언(`Kind.item`)이 정한다.
public struct NotificationSettings: Codable, Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable, CodingKey {
        case assignmentDue, examDayBefore, examMorning, dailyReview, attendance

        // 종류가 쓰는 칸은 `notifications.<종류>.<칸>`으로 선언한 설정 항목이다. 선언하지 않은 칸(출석 알림의 시각)은 nil이다.
        public func item(_ field: Field) -> SettingItem? { SettingItem.item("notifications.\(rawValue).\(field.rawValue)") }

        public var defaultRule: Rule {
            Rule(on: item(.on)?.bool ?? true, minute: item(.minute)?.int, leadHours: item(.leadHours)?.ints)
        }
    }

    public struct Rule: Codable, Sendable, Equatable {
        public var on: Bool
        // 그날 자정부터 센 분이다.
        public var minute: Int?
        // 마감 몇 시간 전에 알리는지다.
        public var leadHours: [Int]?

        public init(on: Bool, minute: Int? = nil, leadHours: [Int]? = nil) {
            self.on = on
            self.minute = minute
            self.leadHours = leadHours
        }
    }

    // 종류 하나의 칸이다. `settings.json`의 키이자 설정 항목 키의 끝(`notifications.examMorning.minute`)이다.
    public enum Field: String, CodingKey { case on, minute, leadHours }

    public var rules: [Kind: Rule]

    public init() {
        rules = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, $0.defaultRule) })
    }

    public subscript(kind: Kind) -> Rule {
        get { rules[kind] ?? kind.defaultRule }
        set { rules[kind] = newValue }
    }

    // 예전 앱의 설정 파일에는 새 종류나 칸이 없으므로, 없는 것은 기본값으로 읽는다. 종류가 쓰지 않는 칸은 버린다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Kind.self)
        self.init()
        for kind in Kind.allCases where c.contains(kind) {
            let r = try c.nestedContainer(keyedBy: Field.self, forKey: kind)
            var rule = kind.defaultRule
            rule.on = try r.value(.on, or: rule.on)
            if let minute = rule.minute { rule.minute = try r.value(.minute, or: minute) }
            if let hours = rule.leadHours { rule.leadHours = try r.value(.leadHours, or: hours) }
            rules[kind] = rule
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Kind.self)
        for kind in Kind.allCases { try c.encode(self[kind], forKey: kind) }
    }
}

// 저장할 때 모르는 필드를 지키는 일(`JSONValue.preservingUnknownKeys`)은 저장된 속성의 이름으로 키를 알아본다. 표는 사전
// 하나라 종류 이름을 속성처럼 보이게 하지 않으면, 종류 객체가 모르는 필드로 보여 예전 값이 새 값을 덮는다.
extension NotificationSettings: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: Kind.allCases.map { (label: Optional($0.rawValue), value: self[$0] as Any) })
    }
}
