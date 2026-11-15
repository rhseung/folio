import FolioDomain
import SwiftUI

extension View {
    func chip() -> some View {
        padding(Theme.Inset.control)
            .surface(Theme.Palette.fill, in: .capsule)
            .contentShape(.capsule)
    }
}

extension Binding {
    // 지운 행의 컨트롤은 사라지는 동안에도 바인딩을 읽는다. 그때 그냥 `$array[i]`를 쓰면 배열 끝을 넘어 읽어 앱이
    // 종료되므로, 지운 뒤에도 남는 바인딩을 준다.
    func element<E: Identifiable>(id: E.ID, fallback: E) -> Binding<E> where Value == [E] {
        Binding<E>(
            get: { wrappedValue.first { $0.id == id } ?? fallback },
            set: { new in if let j = wrappedValue.firstIndex(where: { $0.id == id }) { wrappedValue[j] = new } })
    }

    func element<E>(at i: Int, fallback: E) -> Binding<E> where Value == [E] {
        Binding<E>(
            get: { wrappedValue.indices.contains(i) ? wrappedValue[i] : fallback },
            set: { new in if wrappedValue.indices.contains(i) { wrappedValue[i] = new } })
    }
}

extension View {
    func toolbarField() -> some View {
        padding(.horizontal, Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .toolbarSurface()
    }

    func toolbarGroup() -> some View {
        frame(height: Theme.Size.toolbarButton).toolbarSurface()
    }

    private func toolbarSurface() -> some View {
        background(Theme.Palette.text.opacity(Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
    }
}
