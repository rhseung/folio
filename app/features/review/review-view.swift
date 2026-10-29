import Algorithms
import FolioDomain
import FolioMarkdown
import FolioStorage
import PDFKit
import SwiftUI

struct ReviewOpener<Label: View>: View {
    let courseId: UUID
    let unitId: UUID
    /// Units to slide in after this one, as in Today's queue.
    var then: [ReviewView.Item] = []
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button { open = true } label: { label.contentShape(.rect) }
            .buttonStyle(.pointing(.plain))
            .sheet(isPresented: $open) { ReviewView(courses: [.init(courseId: courseId, unitId: unitId)] + then) }
    }
}

struct ReviewView: View {
    struct Item {
        let courseId: UUID
        let unitId: UUID
    }

    struct Source: Identifiable {
        enum Kind: Hashable { case note(URL), lecture(UUID) }
        let id: Kind
        let title: String
        let symbol: String
        /// Rough notes and lectures are references: they open beside the review note instead of replacing it.
        let beside: Bool
        var page: Int?
    }

    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let courses: [Item]
    @State private var position = 0
    @State private var started = Date.now
    @State private var notes: [NoteFile] = []
    @State private var sources: [Source] = []
    @State private var main: Source.Kind?
    @State private var side: Source.Kind?

    init(courseId: UUID, unitId: UUID) { courses = [Item(courseId: courseId, unitId: unitId)] }
    init(courses: [Item]) { self.courses = courses }

    var courseId: UUID { courses[position].courseId }
    var unitId: UUID { courses[position].unitId }

    var body: some View {
        if let course = workspace.course(courseId), let unit = course.file.units.first(where: { $0.id == unitId }) {
            let accent = workspace.accent(courseId)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(course: course, unit: unit, accent: accent)
                    Theme.Palette.lineSoft.frame(height: 1)
                    HStack(spacing: 0) {
                        if let source = sources.first(where: { $0.id == main }) {
                            pane(source, course: course, closable: false)
                        } else {
                            ContentUnavailableView("이 단원에 노트가 없습니다", systemImage: "doc.text",
                                                   description: Text("연결된 회차의 복습 노트나 이 단원을 태그한 노트가 여기에 나옵니다. 노트 없이 복습했다면 결과만 고르세요."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if let source = sources.first(where: { $0.id == side }) {
                            Theme.Palette.lineSoft.frame(width: 1)
                            pane(source, course: course, closable: true)
                        }
                    }
                }
                .id(position)
                .transition(AsymmetricTransition(insertion: .push(from: .trailing), removal: FlipAway()))
                Theme.Palette.lineSoft.frame(height: 1)
                footer(unit: unit)
            }
            .clipped()
            .frame(minWidth: 860, idealWidth: side == nil ? 960 : 1280, minHeight: 640, idealHeight: 760)
            .background(Theme.Palette.card)
            .foregroundStyle(Theme.Palette.text)
            .font(Theme.Typeface.body)
            .environment(\.accent, accent)
            .tint(accent.ink)
            .task(id: unitId) { load(course: course, unit: unit) }
        } else {
            ContentUnavailableView("단원을 찾지 못했습니다", systemImage: "questionmark.folder")
                .frame(minWidth: 480, minHeight: 320)
                .toolbar { Button("닫기") { dismiss() } }
        }
    }

    func header(course: LoadedCourse, unit: FolioDomain.Unit, accent: CourseAccent) -> some View {
        let sessions = course.file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.tight) {
                        CourseDot(color: accent.color, size: 8)
                        Text("\(course.title) · 복습").font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                    }
                    Text(unit.title).font(Theme.Typeface.columnTitle).lineLimit(2)
                    if !sessions.isEmpty {
                        Text(sessions.map { course.file.name(of: $0) }.joined(separator: ", "))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                if courses.count > 1 {
                    Text("\(position + 1) / \(courses.count)").font(Theme.Typeface.caption).monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary).rolling("\(position)")
                }
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Label(elapsed(until: context.date), systemImage: "timer")
                        .monospacedDigit()
                        .chip()
                }
                .help("공부 시간에 더해집니다")
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            // One chip per source, so a lecture is a click away without leaving the review note.
            if sources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(sources) { source in
                            let on = source.id == main || source.id == side
                            Button { pick(source) } label: {
                                Label(source.title, systemImage: source.symbol)
                                    .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                                    .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                                    .padding(Theme.Inset.toggle)
                                    .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.pointing(.plain))
                            .help(action(for: source) ?? "보고 있는 노트")
                            .contextMenu { if let action = action(for: source) { Button(action) { pick(source) } } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func pane(_ source: Source, course: LoadedCourse, closable: Bool) -> some View {
        VStack(spacing: 0) {
            if closable {
                HStack(spacing: Theme.Space.s) {
                    Label(source.title, systemImage: source.symbol).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Button { side = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.ghost).tint(Theme.Palette.textTertiary).help("닫기")
                }
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                Theme.Palette.lineSoft.frame(height: 1)
            }
            // Keyed by source: the PDF view keeps its first document, so another file needs a new view.
            SourcePane(source: source, note: notes.first { .note($0.url) == source.id }, course: course).id(source.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func footer(unit: FolioDomain.Unit) -> some View {
        let now = Date.now
        // A unit with a cycle but no next day settles with that result; one without a cycle has no day to show.
        let hasCycle = workspace.reviewStates(of: courseId, now: now)[unit.id] != nil
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("얼마나 기억났나요?").font(Theme.Typeface.bodyStrong)
                Text("고른 결과로 다음 복습일이 정해집니다").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            Button("건너뛰기") { finish(.skip) }
                .buttonStyle(.ghost)
                .help("이미 공부한 단원입니다. 틀린 카드나 시험 계획이 생길 때만 다시 올라옵니다")
            ForEach([ReviewResult.again, .hard, .good, .easy], id: \.self) { result in
                let next = workspace.nextReview(course: courseId, unit: unit.id, result: result, now: now)
                Button { finish(result) } label: {
                    VStack(spacing: Theme.Space.xxs) {
                        HStack(spacing: Theme.Space.tight) {
                            Text("\(result.shortcut)")
                                .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: 16, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.Palette.line))
                            Text(result.label).font(Theme.Typeface.bodyStrong)
                        }
                        Text(next?.shortLabel ?? (hasCycle ? "복습 끝" : " ")).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .frame(minWidth: 96)
                    .padding(.vertical, Theme.Space.s)
                    .background(result == .again ? Theme.Palette.dangerFill : Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .keyboardShortcut(KeyEquivalent(Character("\(result.shortcut)")), modifiers: [])
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .background(Theme.Palette.page)
    }

    func load(course: LoadedCourse, unit: FolioDomain.Unit) {
        notes = workspace.notes(for: unit, in: courseId)
        let links = course.file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
            .flatMap(\.materials).uniqued(on: \.materialId)
        let lectures = links.compactMap { link in
            course.file.materials.first { $0.id == link.materialId && $0.path.lowercased().hasSuffix(".pdf") }.map { m in
                Source(id: .lecture(m.id), title: (m.path as NSString).lastPathComponent, symbol: "doc.richtext", beside: true, page: link.firstPage)
            }
        }
        sources = notes.map { n in
            Source(id: .note(n.url), title: "\(n.meta.kind.label) · \(n.title)", symbol: n.meta.kind == .rough ? "pencil.line" : "doc.text", beside: n.meta.kind == .rough)
        } + lectures
        main = (sources.first { !$0.beside } ?? sources.first)?.id
        side = nil
    }

    func action(for source: Source) -> String? {
        source.id == main ? nil : source.id == side ? "옆에서 닫기" : source.beside ? "옆에 펼치기" : "이 노트로 바꾸기"
    }

    func pick(_ source: Source) {
        if source.id == main { return }
        if source.id == side { side = nil } else if source.beside { side = source.id } else { main = source.id }
    }

    func elapsed(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(started)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func finish(_ result: ReviewResult) {
        workspace.recordReview(course: courseId, unit: unitId, result: result, start: started, end: .now)
        guard position + 1 < courses.count else { return dismiss() }
        withAnimation(.snappy(duration: 0.45)) {
            position += 1
            started = .now
        }
    }
}

private struct SourcePane: View {
    @Environment(Workspace.self) private var workspace
    let source: ReviewView.Source
    let note: NoteFile?
    let course: LoadedCourse
    @State private var html: String?
    @State private var pdf: PDFController?
    @State private var failed = false

    var body: some View {
        Group {
            if let pdf {
                PDFKitView(controller: pdf)
            } else if let html {
                HTMLView(body: html, baseURL: note?.url.deletingLastPathComponent())
            } else if failed {
                ContentUnavailableView("열 수 없습니다", systemImage: "doc.questionmark", description: Text(source.title))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    func load() async {
        switch source.id {
        case .note:
            guard let note else { failed = true; return }
            html = HTMLRenderer.render(ParsedNote((try? course.store.read(note)) ?? ""))
        case .lecture(let id):
            guard let material = course.file.materials.first(where: { $0.id == id }),
                  let url = try? await workspace.download(material, course: course.id),
                  let document = PDFDocument(url: url) else { failed = true; return }
            pdf = PDFController(document: document, page: (source.page ?? 1) - 1)
        }
    }
}

extension ReviewResult {
    var shortcut: Int {
        switch self {
        case .again: 1
        case .hard: 2
        case .good: 3
        case .easy: 4
        case .skip: 0
        }
    }
}

private struct FlipAway: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotation3DEffect(.degrees(phase.isIdentity ? 0 : -75), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
