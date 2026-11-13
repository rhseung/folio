import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct InfoBlocks: View {
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink
    @Environment(\.openURL) private var openURL
    let course: LoadedCourse
    @State private var model: CourseInfoModel

    init(workspace: Workspace, course: LoadedCourse) {
        self.course = course
        _model = State(initialValue: CourseInfoModel(workspace: workspace))
    }

    var body: some View {
        let c = course.file.course
        let people = model.people(c)
        Group {
            Block(String(localized: .courseInfoPeople)) {
                Card {
                    if people.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .courseInfoNoPeople)) } }
                    ForEach(Array(people.enumerated()), id: \.element.id) { i, p in
                        CardRow(last: i == people.count - 1) {
                            // The name and its details open the person; the address beside them still writes mail.
                            Button { openLink(AppLink(.person, p.id)) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(p.name)
                                        if let detail = model.detail(p) {
                                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        }
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.Palette.textTertiary)
                                    Spacer(minLength: Theme.Space.m)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .help(Text(.courseInfoOpenPerson(p.name)))
                            if let url = model.mailURL(p) {
                                Link(p.email, destination: url).buttonStyle(.plain).foregroundStyle(accent.ink).pointingHand()
                            }
                        }
                        .contextMenu {
                            Button(.courseInfoOpenPerson(p.name), systemImage: "person") { openLink(AppLink(.person, p.id)) }
                            if let url = model.mailURL(p) {
                                Button(.courseInfoWriteMail, systemImage: "envelope") { openURL(url) }
                            }
                        }
                    }
                }
            }
            Block(String(localized: .courseInfoMemo)) {
                Card {
                    GrowingTextEditor(text: $model.memo)
                        .padding(Theme.Space.m)
                    Theme.Palette.lineSoft.frame(height: 1)
                    CardRow(last: true) {
                        Spacer()
                        Button(.courseInfoSaveMemo) { model.saveMemo(course.id) }
                            .buttonStyle(.prominent)
                            .disabled(model.memo == c.memo)
                    }
                }
            }
            Block(String(localized: .courseInfoFolder)) {
                Card {
                    FormRow(label: course.store.url.lastPathComponent, detail: course.store.url.deletingLastPathComponent().path, last: true) {
                        #if os(macOS)
                        Button(.commonShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                        #endif
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button(.commonShowInFinder, systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([course.store.url]) }
                    }
                    #endif
                }
            }
        }
        .onAppear { model.memo = c.memo }
        // A memo saved elsewhere (another device, the sync) replaces the shown one unless it is being edited here.
        .onChange(of: c.memo) { old, new in if model.memo == old { model.memo = new } }
    }
}
