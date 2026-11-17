import FolioDomain
import QuickLook
import SwiftUI

// Mac과 iPad는 PageBar 밑에 띠로, iPhone은 시트(`inSheet`)로 연다. 띠는 손잡이를 끌거나 펼침 버튼을 눌러 격자로 펼친다.
struct AssetTray: View {
    @Bindable var model: AssetTrayModel
    var inSheet = false
    @Environment(\.accent) private var accent
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            head
            if inSheet && model.expanded {
                SearchField(prompt: String(localized: .notesAssetsSearch), text: $model.search)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.s)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: height, alignment: .top)
        .background(targeted ? accent.tint : inSheet ? Theme.Palette.card : Theme.Palette.page.opacity(Theme.Opacity.soft))
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(accent.color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(Theme.Space.xs)
            }
        }
        .overlay(alignment: .bottom) { if !inSheet && !model.isEmpty { grabber } }
        .background(AssetThumbnailHost())
        .animation(Theme.Motion.quick, value: targeted)
        .animation(Theme.Motion.standard, value: model.expanded)
        .animation(Theme.Motion.standard, value: model.filter)
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls)
            return true
        } isTargeted: {
            targeted = $0
        }
        .fileImporter(isPresented: $model.picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addFiles(urls) }
        }
        .task(id: model.revision) { model.reload() }
        .sheet(item: $model.viewing) { AssetViewer(model: model, asset: $0) }
        .quickLookPreview($model.quickLook)
    }

    private var height: CGFloat? {
        if inSheet { return nil }
        if model.isEmpty { return Theme.Size.assetTrayHead + Theme.Size.rowHeight }
        return model.expanded ? Theme.Size.assetTrayGrid : Theme.Size.assetTray
    }

    private var head: some View {
        HStack(spacing: Theme.Space.s) {
            SegmentedControl(selection: $model.filter, options: model.filters, size: .small).fixedSize()
            Spacer(minLength: Theme.Space.s)
            if model.expanded && !inSheet {
                SearchField(prompt: String(localized: .notesAssetsSearch), text: $model.search)
                    .frame(maxWidth: Theme.Size.assetSearch)
            }
            Button {
                model.picking = true
            } label: {
                Label(.notesAssetsAdd, systemImage: "plus")
            }
            .buttonStyle(.ghostIcon)
            .help(Text(.notesAssetsAddHelp))
            if !inSheet && !model.isEmpty {
                Button {
                    model.expanded.toggle()
                } label: {
                    Label(model.expanded ? .commonCollapse : .commonExpand, systemImage: model.expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.ghostIcon)
                .help(Text(.notesAssetsExpandHelp))
            }
        }
        .padding(.leading, inSheet ? Theme.Space.l : Theme.Space.xl)
        .padding(.trailing, inSheet ? Theme.Space.s : Theme.Space.l)
        .frame(height: Theme.Size.assetTrayHead)
    }

    @ViewBuilder private var content: some View {
        let shelf = model.shelf
        if model.isEmpty {
            note(Label(.notesAssetsEmpty, systemImage: "square.and.arrow.down"))
        } else if shelf.isEmpty {
            note(Label(.notesAssetsNoMatch, systemImage: "magnifyingglass"))
        } else if model.expanded {
            grid(shelf)
        } else {
            strip(shelf)
        }
    }

    private func note(_ label: some View) -> some View {
        label
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, inSheet ? Theme.Space.l : Theme.Space.xl)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
    }

    private func strip(_ shelf: NoteAssetShelf) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                group(.notesAssetsUnused, shelf.unused) { tiles($0) }
                if !shelf.unused.isEmpty && !shelf.used.isEmpty {
                    Theme.Palette.lineSoft.frame(width: 1).padding(.vertical, Theme.Space.xs)
                }
                group(.notesAssetsUsed, shelf.used) { tiles($0) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, inSheet ? Theme.Space.l : Theme.Space.xl)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.l)
        }
        .scrollIndicators(.never)
        .overflowFade(.horizontal)
    }

    private func grid(_ shelf: NoteAssetShelf) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                group(.notesAssetsUnused, shelf.unused) { wrapped($0) }
                if !shelf.unused.isEmpty && !shelf.used.isEmpty { Theme.Palette.lineSoft.frame(height: 1) }
                group(.notesAssetsUsed, shelf.used) { wrapped($0) }
            }
            .padding(.horizontal, inSheet ? Theme.Space.l : Theme.Space.xl)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder private func group(
        _ title: LocalizedStringResource, _ assets: [NoteAsset], @ViewBuilder tiles: ([NoteAsset]) -> some View
    ) -> some View {
        if !assets.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.xs) {
                    Caption(String(localized: title))
                    Text(assets.count, format: .number).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                tiles(assets)
            }
        }
    }

    private func tiles(_ assets: [NoteAsset]) -> some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(assets) { TrayTile(model: model, asset: $0, collapsing: inSheet) }
        }
    }

    private func wrapped(_ assets: [NoteAsset]) -> some View {
        let columns =
            inSheet
            ? Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s), count: 3)
            : [GridItem(.adaptive(minimum: Theme.Size.assetTile.width, maximum: Theme.Size.assetTile.width), spacing: Theme.Space.s)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.s) {
            ForEach(assets) { TrayTile(model: model, asset: $0, collapsing: inSheet, fills: inSheet) }
        }
    }

    // 끌어 내리면 펼치고 끌어 올리면 접는다. 손잡이의 터치 표적은 띠 아래 여백에서 시작해 본문 위로 넘어가므로,
    // 노트 편집기가 띠를 `zIndex`로 위에 둔다.
    private var grabber: some View {
        Capsule()
            .fill(Theme.Palette.lineStrong)
            .frame(Theme.Size.grabber)
            .padding(.top, Theme.Space.m - Theme.Size.grabber.height / 2)
            .frame(width: Theme.Size.touchTarget * 2, height: Theme.Size.touchTarget, alignment: .top)
            .contentShape(.rect)
            .offset(y: Theme.Size.touchTarget - Theme.Space.l)
            .pointingHand()
            .gesture(
                DragGesture(minimumDistance: Theme.Space.xs).onEnded { drag in
                    if drag.translation.height > Theme.Space.xl { model.expanded = true }
                    if drag.translation.height < -Theme.Space.xl { model.expanded = false }
                }
            )
            .onTapGesture { model.expanded.toggle() }
            .accessibilityHidden(true)
    }
}

private struct TrayTile: View {
    let model: AssetTrayModel
    let asset: NoteAsset
    let collapsing: Bool
    var fills = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.insert(asset, collapsing: collapsing)
        } label: {
            AssetTile(model: model, asset: asset, size: fills ? nil : Theme.Size.assetTile, showsName: hovering)
        }
        .buttonStyle(.pointing(.plain))
        .scaleEffect(hovering ? 1.04 : 1)
        .shadow(Theme.Shadow.lifted, shown: hovering)
        .animation(Theme.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
        .help(Text(.notesAssetsTileHelp))
        .accessibilityLabel(model.name(asset))
        .accessibilityValue(model.detail(asset))
        .draggable(model.dragText(asset)) { AssetTile(model: model, asset: asset) }
        .contextMenu {
            Button {
                model.insert(asset, collapsing: collapsing)
            } label: {
                Label(.notesAssetsInsert, systemImage: "text.insert")
            }
            Button {
                model.viewLarge(asset)
            } label: {
                Label(.notesAssetsViewLarge, systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } preview: {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                AssetTile(model: model, asset: asset, size: Theme.Size.assetPreview)
                Text(model.name(asset)).font(Theme.Typeface.bodyLarge.weight(.semibold)).lineLimit(2)
                    .padding(.top, Theme.Space.xs)
                Text(model.detail(asset)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Space.m)
            .background(Theme.Palette.card)
        }
    }
}
