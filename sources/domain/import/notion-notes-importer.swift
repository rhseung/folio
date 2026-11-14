import Foundation

public enum NotionNotesImporter {
    // 노션 제목은 마크다운 이스케이프(`1\\. Numbers`)가 붙거나 태그(`<p>Worksheet</p>`)로 감싸여 온다.
    static func clean(_ title: String) -> String {
        var s = title
        s.replace(/<[^>]+>/) { _ in "" }
        s.replace(/\\([\\`*_{}\[\]()#+\-.!~<>|])/) { m in String(m.1) }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func session(of title: String) -> (week: Int, index: Int, review: Bool)? {
        guard let m = title.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\d+)주차-(\d+)(\s*정리)?/) else { return nil }
        return (Int(m.1)!, Int(m.2)!, m.3 != nil)
    }

    public static func merge(
        _ dump: NotionCourseDump, into file: CourseFile, existingNotes: Set<UUID>,
        calendar: Calendar, device: DeviceID, now: Date
    ) -> NotionMergeResult {
        var file = file
        var result = NotionMergeResult(file: file, notes: [], sessionsAdded: 0, componentsAdded: 0, scoresAdded: 0, warnings: [])

        let dump = cleaned(dump)
        var named: [String: UUID] = [:]
        for row in dump.notes.sorted(by: { ($0.date ?? "", $0.title) < ($1.date ?? "", $1.title) }) {
            guard let source = row.file else { continue }
            var sessionId: UUID?
            var kind: NoteKind = row.kind == "러프" ? .rough : .unit
            if let s = session(of: row.title) {
                let review = row.kind == "복습" || (row.kind == nil && s.review)
                kind = review ? .review : .rough
                let key = "\(s.week)주차-\(s.index)"
                let day = row.date.flatMap(LocalDate.init).flatMap { $0.date(in: calendar) }
                // 다른 노션 번호가 이미 가져간 회차는 다른 수업이다. 날짜나 이름으로 다시 맞추면 두 수업이 하나로 합쳐진다.
                let claimed = Set(named.filter { $0.key != key }.values)
                let index: Int
                if let existing = file.sessions.firstIndex(where: { $0.roughNoteId == row.id || $0.reviewNoteId == row.id })
                    ?? named[key].flatMap({ id in file.sessions.firstIndex { $0.id == id } })
                    ?? day.flatMap({ d in
                        file.sessions.firstIndex {
                            !claimed.contains($0.id) && $0.week == s.week && calendar.isDate($0.date, inSameDayAs: d)
                        }
                    })
                    ?? file.sessions.firstIndex(where: {
                        !claimed.contains($0.id) && ordinal(of: $0, in: file.sessions) == (s.week, s.index)
                    })
                {
                    index = existing
                } else {
                    file.sessions.append(Session(device: device, at: now, week: s.week, date: day ?? now))
                    result.sessionsAdded += 1
                    index = file.sessions.count - 1
                }
                // 이미 course.json에 있는 노트는 그 항목의 연결을 유지한다. 여기서 이으면 회차 쪽만 정해지고, 사용자가 지운
                // 연결이 되살아난다.
                if !existingNotes.contains(row.id) {
                    // 회차는 종류마다 노트를 하나만 가진다. 이미 다른 노트를 가진 회차는 그 노트를 유지하고, 이 노트는 모델이 거절할
                    // 둘째 노트가 되지 않도록 회차 없이 들어온다.
                    let s = file.sessions[index]
                    let taken = s.note(of: kind).map { $0 != row.id } ?? false
                    if taken {
                        let name = file.title(of: s, calendar: calendar)
                        result.warnings.append(
                            String(
                                localized: review
                                    ? .importNotesSessionHasReview(row.title, name) : .importNotesSessionHasRough(row.title, name)))
                    } else {
                        if review { file.sessions[index].reviewNoteId = row.id } else { file.sessions[index].roughNoteId = row.id }
                        sessionId = s.id
                    }
                }
                named[key] = file.sessions[index].id
            }

            if !existingNotes.contains(row.id) {
                result.notes.append(
                    NotionNotePlan(
                        id: row.id, title: row.title, meta: NoteMeta(id: row.id, kind: kind, sessionId: sessionId), sourceFile: source))
            }
        }

        file.sessions.sort(by: Session.inOrder)

        mergeScores(dump.scores, into: &file, result: &result, device: device, now: now)
        result.file = file
        return result
    }

    static func ordinal(of session: Session, in sessions: [Session]) -> (Int, Int) {
        let week = sessions.filter { $0.week == session.week }.sorted(by: Session.inOrder)
        return (session.week, (week.firstIndex { $0.id == session.id } ?? week.count) + 1)
    }

    static func cleaned(_ dump: NotionCourseDump) -> NotionCourseDump {
        var d = dump
        for i in d.notes.indices { d.notes[i].title = clean(d.notes[i].title) }
        for i in d.scores.indices { d.scores[i].name = clean(d.scores[i].name) }
        return d
    }

    static func mergeScores(
        _ rows: [NotionCourseDump.ScoreRow], into file: inout CourseFile, result: inout NotionMergeResult, device: DeviceID, now: Date
    ) {
        let ids = Set(rows.map(\.id))
        let parent = Dictionary(keepingFirst: rows.compactMap { r in r.parentId.flatMap { ids.contains($0) ? (r.id, $0) : nil } })
        let hasChildren = Set(parent.values)
        func existing(_ row: NotionCourseDump.ScoreRow) -> UUID? {
            file.components.first {
                $0.id == row.id || $0.name.caseInsensitiveCompare(row.name.trimmingCharacters(in: .whitespaces)) == .orderedSame
            }?.id
        }
        func ancestors(_ id: UUID) -> [UUID] {
            var chain = [id]
            while let p = parent[chain.last!], !chain.contains(p) { chain.append(p) }
            return chain
        }

        // 이미 구성 요소로 저장한 행(앞선 가져오기가 하위 항목을 저장했을 수 있다)은 점수를 유지한다. 그 위에 부모를
        // 더하면 같은 비중을 두 번 세므로 부모는 더하지 않는다.
        let covered = Set(rows.filter { existing($0) != nil }.flatMap { ancestors($0.id).dropFirst() })
        let hadComponents = !file.components.isEmpty

        var componentFor: [UUID: UUID] = [:]
        for row in rows {
            if let id = existing(row) { componentFor[row.id] = id }
        }

        for row in rows where parent[row.id] == nil && componentFor[row.id] == nil && !covered.contains(row.id) {
            let order = (file.components.map(\.order).max() ?? -1) + 1
            file.components.append(
                GradeComponent(
                    id: row.id, device: device, at: now, name: row.name.trimmingCharacters(in: .whitespaces),
                    weight: row.weight ?? 0, order: order))
            componentFor[row.id] = row.id
            result.componentsAdded += 1
        }

        // 어떤 과목은 비중을 점수(합이 1000)로 주지만, 구성 요소의 비중은 백분율이다.
        let total = file.components.map(\.weight).reduce(0, +)
        if !hadComponents, total > 150 {
            for i in file.components.indices { file.components[i].weight *= 100 / total }
            result.warnings.append(String(localized: .importNotesWeightsScaled(Int(total))))
        }

        for row in rows where !hasChildren.contains(row.id) {
            guard let score = row.score else { continue }
            guard let componentId = ancestors(row.id).lazy.compactMap({ componentFor[$0] }).first else {
                result.warnings.append(String(localized: .importNotesNoComponent(row.name)))
                continue
            }
            guard let max = row.max, max > 0 else {
                result.warnings.append(String(localized: .importNotesNoMax(row.name)))
                continue
            }
            let title = row.name.trimmingCharacters(in: .whitespaces)
            let duplicate = file.scores.contains { $0.id == row.id || ($0.componentId == componentId && $0.title == title) }
            if duplicate { continue }
            file.scores.append(
                ScoreEntry(id: row.id, device: device, at: now, componentId: componentId, title: title, score: score, max: max))
            result.scoresAdded += 1
        }
    }
}
