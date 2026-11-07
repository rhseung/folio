import FolioDomain
import QuickLookThumbnailing
import SwiftUI

/// The add sheet: one calm row per file with where it lands, and quiet menus for what it is and which class it is for.
struct ImportPlaceSheet: View {
    @State private var model: ImportPlaceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var listFocused: Bool

    init(workspace: Workspace, course: LoadedCourse, files: [URL], places: [String]) {
        _model = State(initialValue: ImportPlaceModel(workspace: workspace, course: course, files: files, places: places))
    }

    var body: some View {
        let placements = model.placements
        let kinds = model.kinds
        SheetForm(title: model.title, confirm: model.confirmTitle, note: model.hint, width: Self.width) {
            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    ImportRow(model: model, row: row, placement: placements[row.id], kinds: kinds, selected: model.selection.contains(row.id))
                        .opens { click(row.id) }
                    if row.id < model.rows.count - 1 { Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l) }
                }
            }
            // The chosen row's fill reaches the card's rounded ends.
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                model.step(press.key == .downArrow ? 1 : -1, extend: press.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(characters: .decimalDigits) { press in
                guard press.modifiers.isEmpty, let n = Int(press.characters), model.applyKind(number: n) else { return .ignored }
                return .handled
            }
        } onConfirm: {
            model.confirm()
            dismiss()
        }
        .onAppear { listFocused = true }
    }

    /// Room for a long file name beside both menus: the sheet is a list to read, not a form to fill.
    static let width: CGFloat = 640

    private func click(_ id: Int) {
        listFocused = true
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        model.click(id, extend: flags.contains(.shift), toggle: flags.contains(.command))
        #else
        // A tap carries no modifier keys; ⇧↑↓ from a hardware keyboard still widen the selection.
        model.click(id)
        #endif
    }
}

private struct ImportRow: View {
    let model: ImportPlaceModel
    let row: ImportPlaceModel.Row
    let placement: MaterialIntake.Placement
    let kinds: [ImportPlaceModel.Kind]
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            FileThumbnail(url: row.url)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(row.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(destination).font(Theme.Typeface.mono).lineLimit(1).truncationMode(.middle)
                    .help([placement.path, model.nameNote(placement)].compactMap(\.self).joined(separator: "\n"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Space.xs) {
                kindMenu
                if model.isLecture(row) { sessionMenu }
            }
            .fixedSize()
        }
        .padding(EdgeInsets(top: Theme.Space.m, leading: Theme.Space.l, bottom: Theme.Space.m, trailing: Theme.Space.m))
        .frame(minHeight: Self.height)
        .background(selected ? Theme.Palette.fill : .clear)
    }

    /// A thumbnail, two lines of text and the row's padding.
    static let height: CGFloat = 64

    @Environment(\.accent) private var accent

    /// The folder in the quiet mono of a path, and only what Folio adds to the name in color: the week in front, the
    /// number past a name the folder holds.
    private var destination: AttributedString {
        var out = AttributedString(placement.folder + "/")
        out.foregroundColor = Theme.Palette.textTertiary
        var name = placement.name
        if let prefix = placement.prefix {
            var part = AttributedString(prefix)
            part.foregroundColor = accent.ink
            out += part
            name.removeFirst(prefix.count)
        }
        let ext = (name as NSString).pathExtension
        var base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var tail = AttributedString()
        if let suffix = placement.suffix, base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
            tail = AttributedString(suffix)
            tail.foregroundColor = Theme.Palette.warning
        }
        var plain = AttributedString(base)
        plain.foregroundColor = Theme.Palette.textTertiary
        var dot = AttributedString(ext.isEmpty ? "" : "." + ext)
        dot.foregroundColor = Theme.Palette.textTertiary
        return out + plain + tail + dot
    }

    private var kindMenu: some View {
        Menu {
            ForEach(Array(kinds.enumerated()), id: \.element.id) { i, kind in
                if kind.perItem {
                    Section(kind.label) {
                        ForEach(kind.places, id: \.self) { place in
                            choice((place as NSString).lastPathComponent, on: row.folder == place) { model.setFolder(place, for: model.targets(row)) }
                        }
                    }
                } else {
                    choice(kind.label, detail: "\(i + 1)  \(kind.places[0])", on: kind.places.contains(row.folder)) {
                        model.setKind(kind, for: model.targets(row))
                    }
                }
            }
        } label: {
            QuietMenuLabel(text: model.kindLabel(row), guessed: model.kindWhy(row) != nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).pointingHand()
        .help(model.kindWhy(row) ?? String(localized: .materialsImportKind))
    }

    private var sessionMenu: some View {
        Menu {
            choice(String(localized: .materialsImportNoSession), on: row.session == nil) { model.setSession(nil, for: model.targets(row)) }
            Divider()
            ForEach(model.sessions) { s in
                choice(model.sessionTitle(s), detail: model.sessionNote(s), on: row.session == s.id) { model.setSession(s.id, for: model.targets(row)) }
            }
        } label: {
            QuietMenuLabel(text: model.sessionLabel(row), guessed: model.sessionWhy(row) != nil)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).pointingHand()
        .help(model.sessionWhy(row) ?? String(localized: .materialsImportSession))
    }

    private func choice(_ label: String, detail: String? = nil, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if on { Image(systemName: "checkmark") }
            Text(label)
            if let detail { Text(detail) }
        }
    }
}

/// A menu's current value as quiet text, a ⌃⌄ after it, and a ✦ in front when Folio guessed it. The pill shows only
/// under the pointer: a row of grey chips per file read as a form to fill.
private struct QuietMenuLabel: View {
    let text: String
    let guessed: Bool
    @State private var hovering = false
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            if guessed { Image(systemName: "sparkle").font(Theme.Glyph.small).foregroundStyle(accent.color) }
            Text(text).lineLimit(1).frame(maxWidth: Self.maxText, alignment: .leading).fixedSize()
            Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
        }
        .foregroundStyle(hovering ? Theme.Palette.text : Theme.Palette.textSecondary)
        .padding(Theme.Inset.toggle)
        .background(Capsule().fill(Theme.Palette.fill).opacity(hovering ? 1 : 0))
        .contentShape(.capsule)
        .onHover { hovering = $0 }
    }

    /// A long session topic truncates rather than pushing the file name out of its row.
    static let maxText: CGFloat = 176
}

/// The file's first page, as Finder would show it; a document glyph until it is drawn, or where none can be.
private struct FileThumbnail: View {
    let url: URL
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: Theme.Radius.small))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.Palette.lineSoft))
            } else {
                LineIcon(symbol: "doc").foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .task(id: url) { image = await Self.draw(url) }
    }

    static let size = CGSize(width: 48, height: 40)

    private static func draw(_ url: URL) async -> Image? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        #if os(macOS)
        return Image(nsImage: rep.nsImage)
        #else
        return Image(uiImage: rep.uiImage)
        #endif
    }
}
