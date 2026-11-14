import FolioAI
import FolioDomain
import SwiftUI

struct CourseColumn: View {
    @Environment(\.accent) private var accent
    @Environment(\.closeColumn) private var closeColumn
    @Bindable var model: CourseModel
    let course: LoadedCourse

    var body: some View {
        let file = course.file
        let recent = model.recent(file)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.codeLine(model.workspace)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                        .padding(.leading, ColumnRow<EmptyView>.titleInset - Theme.Inset.listRow.leading)
                    HStack(spacing: ColumnRow<EmptyView>.gap) {
                        CourseMark(icon: course.file.course.icon, color: accent.color, font: Theme.Glyph.lineTitle)
                        Text(course.title).font(Theme.Typeface.columnTitle).lineLimit(2)
                    }
                }
                .padding(.horizontal, Theme.Inset.listRow.leading)

                VStack(spacing: Theme.Space.xxs) {
                    ForEach(CourseTab.allCases) { item in
                        let chosen = model.section.tab == item
                        Button {
                            if !chosen { model.section = item.pages[0] }
                            closeColumn()
                        } label: {
                            ColumnRow(title: item.title, symbol: item.symbol, chosen: chosen, tint: accent.color, fill: accent.tint) {
                                if let trailing = model.trailing(item, file: file) {
                                    if trailing.warning {
                                        Chip(trailing.text, tone: .warning)
                                    } else {
                                        Text(trailing.text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.pointing(.plain))
                        if chosen, item.pages.count > 1 {
                            ForEach(item.pages) { page in
                                Button {
                                    model.section = page
                                    closeColumn()
                                } label: {
                                    Text(page.title).lineLimit(1)
                                        .foregroundStyle(model.section == page ? accent.ink : Theme.Palette.textSecondary)
                                        .fontWeight(model.section == page ? .semibold : .regular)
                                        .padding(.leading, ColumnRow<EmptyView>.titleInset)
                                        .padding(.vertical, Theme.Space.xs)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                            }
                        }
                    }
                }

                if model.section == .notes {
                    NoteList(workspace: model.workspace, course: course, selection: $model.openNote, moves: model.noteMoves)
                } else if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Caption(String(localized: .courseRecent)).padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.tight)
                        ForEach(recent) { session in
                            Button {
                                if let id = session.roughNoteId ?? session.reviewNoteId {
                                    model.show(note: id)
                                } else {
                                    model.section = .sessions
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(model.recentTitle(session, in: file)).lineLimit(1)
                                    Text(model.recentDetail(session, in: file)).lineLimit(1)
                                        .font(Theme.Typeface.label.weight(.regular))
                                        .foregroundStyle(
                                            file.needsReviewNote(session, at: model.workspace.now)
                                                ? Theme.Palette.danger : Theme.Palette.textTertiary)
                                }
                                .padding(Theme.Inset.listRow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu { SessionMenu(courseId: course.id, sessionId: session.id, openNote: model.show(note:)) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
            .clearOfColumnButtons(inset: Theme.Space.l)
        }
        .overflowFade(.vertical)
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .columnBackground()
    }
}
