import FolioDomain
import SwiftUI

// 표의 칸과 좁은 목록이 함께 쓰는 블록 하나다. 회차는 팝오버를, 예정 수업은 그 수업의 메뉴를, 시험은 시험 화면을 연다.
struct SessionBlock: View {
    @Environment(\.accent) private var accent
    @Environment(\.openLink) private var openLink
    @Bindable var model: SessionsModel
    let course: LoadedCourse
    let entry: SessionTableEntry
    let table: SessionTable
    var other = false
    var minHeight = Theme.Size.touchTarget

    var body: some View {
        switch entry.item {
        case .session(let session):
            Button {
                model.open(session.id)
            } label: {
                face
            }
            .buttonStyle(.pointing(.plain))
            .contextMenu { SessionMenu(courseId: model.courseId, sessionId: session.id, host: .own, openNote: openNote) }
            .popover(isPresented: shows(session.id), arrowEdge: .trailing) {
                SessionPopover(model: model, course: course, session: session, table: table)
            }
            .fileDrop { model.importFiles($0, into: session) }
            .linkTarget(session.id)
        case .planned:
            if let item = model.planned(entry) {
                Menu {
                    SuggestedSessionItems(item: item, primary: true, openNote: openNote)
                } label: {
                    face
                }
                .menuButton(indicator: .hidden)
                .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote) }
            } else {
                face
            }
        case .exam, .deadline:
            Button {
                if let link = model.link(entry) { openLink(link, course: model.courseId) }
            } label: {
                face
            }
            .buttonStyle(.pointing(.plain))
        }
    }

    func shows(_ id: UUID) -> Binding<Bool> {
        Binding {
            model.popover == id
        } set: {
            if !$0, model.popover == id { model.popover = nil }
        }
    }

    func openNote(_ id: UUID) { openLink(AppLink(.note, id), course: model.courseId) }

    var face: some View {
        let tags = model.tags(entry)
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(model.title(entry))
                .font(model.isUntitled(entry) || entry.look == .upcoming ? Theme.Typeface.body : Theme.Typeface.bodyStrong)
                .foregroundStyle(model.isUntitled(entry) ? Theme.Palette.textTertiary : ink)
                .strikethrough(entry.look == .cancelled)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let line = model.line(entry, other: other) {
                Text(line).font(Theme.Typeface.caption).foregroundStyle(ink.opacity(Theme.Opacity.secondaryInk)).lineLimit(1)
            }
            if !tags.isEmpty {
                FlowLayout(spacing: Theme.Space.xs) { ForEach(tags, id: \.self) { BlockTagView(tag: $0) } }
                    .padding(.top, Theme.Space.xxs)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .padding(.leading, hasStripe ? Theme.Space.s + Theme.Size.stripe : Theme.Space.s)
        .padding(.trailing, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background { fill }
        .overlay(alignment: .leading) { if let stripe { stripe.frame(width: Theme.Size.stripe) } }
        .clipShape(.rect(cornerRadius: Theme.Radius.block))
        .overlay { border }
        .opacity(entry.look == .cancelled ? Theme.Opacity.ended : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spoken(entry))
        .accessibilityAddTraits(.isButton)
    }

    var ink: Color {
        switch entry.look {
        case .exam: Theme.Palette.danger
        case .cancelled: Theme.Palette.textSecondary
        case .upcoming: Theme.Palette.textTertiary
        default: accent.ink
        }
    }

    var hasStripe: Bool { stripe != nil }

    var stripe: Color? {
        switch entry.look {
        case .late: Theme.Palette.warning
        case .absent: Theme.Palette.danger
        default: nil
        }
    }

    @ViewBuilder var fill: some View {
        switch entry.look {
        case .upcoming, .next: Color.clear
        case .cancelled: Theme.Palette.fill
        case .exam: Theme.Palette.dangerFill
        case .absent: accent.tint.overlay { BlockHatch(color: Theme.Palette.danger.opacity(Theme.Opacity.toneEdge)) }
        default: accent.tint
        }
    }

    @ViewBuilder var border: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.block)
        switch entry.look {
        case .upcoming: shape.strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        case .next: shape.strokeBorder(accent.color, style: StrokeStyle(lineWidth: Theme.Size.line, dash: [4, 4]))
        default: if entry.isMakeup { shape.strokeBorder(accent.color, lineWidth: 1) }
        }
    }
}

private struct BlockTagView: View {
    @Environment(\.accent) private var accent
    let tag: SessionsModel.BlockTag

    var body: some View {
        Group {
            if let symbol = tag.symbol {
                Image(systemName: symbol).font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(minWidth: Theme.Size.smallIcon, minHeight: Theme.Size.smallIcon).accessibilityLabel(tag.spoken)
            } else if let text = tag.text {
                Badge(text, tone: tag.tone)
            }
        }
        .help(tag.spoken)
    }
}

// 결석한 회차의 빗금이다. 색만으로 알리지 않도록 줄무늬를 더한다.
private struct BlockHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += Theme.Space.s
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
