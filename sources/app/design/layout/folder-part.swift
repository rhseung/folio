import FolioDomain
import SwiftUI

struct FolderPart: Shape {
    enum Kind { case outline, corners, fill }
    let kind: Kind
    var t: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    // 그린 닫힌 폴더를 160pt medium `folder`(템플릿 단위당 2.05 캔버스 px, 13px 획)에 맞춰 찾은 값이다. 작은 템플릿을
    // 고르게 키운 값과 다르다.
    static let unit: CGFloat = 2.05 / 160  // design: one-off, fitted to the folder symbol
    static let stroke: CGFloat = 13 / 160  // design: one-off, fitted to the folder symbol
    static let middle = CGPoint(x: 53.54, y: -35.51)
    static let left: CGFloat = 13.28, right: CGFloat = 93.8, bottom: CGFloat = -3.64  // design: one-off, folder template units
    static let top: CGFloat = -60.4, tabTop: CGFloat = -67.38  // design: one-off, folder template units
    static let bar: CGFloat = -48.7, barLeft: CGFloat = 25.2, barRight: CGFloat = 81.9  // design: one-off, folder template units
    static let flapTop: CGFloat = -44, lean: CGFloat = 8, corner: CGFloat = 9  // design: one-off, folder template units
    static let round: CGFloat = 6, foot: CGFloat = 7  // design: one-off, folder template units

    func path(in rect: CGRect) -> Path {
        let u = Self.unit * Theme.Glyph.lineSize
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - Self.middle.x) * u, y: rect.midY + (y - Self.middle.y) * u)
        }
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let edgeY = mix(Self.bar, Self.flapTop)
        let tl = pt(Self.left + Self.lean * t, edgeY), tr = pt(Self.right + Self.lean * t, edgeY)
        let bl = pt(Self.left, Self.bottom), br = pt(Self.right, Self.bottom)
        let r = Self.round * u
        func along(_ from: CGPoint, _ to: CGPoint, _ d: CGFloat) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y, l = (dx * dx + dy * dy).squareRoot()
            return CGPoint(x: from.x + dx / l * d, y: from.y + dy / l * d)
        }

        var p = Path()
        if kind == .corners {
            p.move(to: along(tl, tr, r))
            p.addArc(tangent1End: tl, tangent2End: bl, radius: r)
            p.move(to: along(tr, tl, r))
            p.addArc(tangent1End: tr, tangent2End: br, radius: r)
            return p
        }
        let backBottom = pt(Self.left, mix(Self.bar, Self.bottom - 12))
        p.move(to: backBottom)
        p.addArc(tangent1End: pt(Self.left, Self.tabTop), tangent2End: pt(33.5, Self.tabTop), radius: 8.5 * u)
        p.addArc(tangent1End: pt(33.5, Self.tabTop), tangent2End: pt(43.5, Self.top), radius: 5 * u)
        p.addArc(tangent1End: pt(43.5, Self.top), tangent2End: pt(Self.right, Self.top), radius: 5 * u)
        p.addArc(tangent1End: pt(Self.right, Self.top), tangent2End: pt(Self.right, Self.bar), radius: Self.corner * u)
        p.addLine(to: pt(Self.right, edgeY))
        switch kind {
        case .corners:
            break
        case .fill:
            // 두 영역을 같은 방향으로 감아야 만나는 곳이 뚫리지 않는다.
            p.addLine(to: tl)
            p.addLine(to: backBottom)
            p.closeSubpath()
            p.move(to: along(tl, tr, r * t))
            p.addArc(tangent1End: tr, tangent2End: br, radius: r * t)
            p.addArc(tangent1End: br, tangent2End: bl, radius: mix(Self.corner, 7) * u)
            p.addArc(tangent1End: bl, tangent2End: tl, radius: mix(Self.corner, Self.foot) * u)
            p.addArc(tangent1End: tl, tangent2End: tr, radius: r * t)
            p.closeSubpath()
        case .outline:
            p.move(to: along(tl, bl, r * t))
            p.addArc(tangent1End: bl, tangent2End: br, radius: mix(Self.corner, Self.foot) * u)
            p.addArc(tangent1End: br, tangent2End: tr, radius: mix(Self.corner, 7) * u)
            p.addLine(to: along(tr, br, r * t))
            p.move(to: CGPoint(x: mix(pt(Self.barLeft, 0).x, tl.x + r), y: tl.y))
            p.addLine(to: CGPoint(x: mix(pt(Self.barRight, 0).x, tr.x - r), y: tr.y))
        }
        return p
    }
}
