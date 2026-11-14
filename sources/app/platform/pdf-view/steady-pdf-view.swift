import CoreImage
import Observation
import PDFKit
import SwiftUI

final class SteadyPDFView: PDFView {
    private var held: PDFDestination?
    private var letGo: DispatchWorkItem?
    // UIKit은 PDFView가 `document`에 필요한 것을 만들기 전에 `init(frame:)` 안에서 frame을 정한다. 그때 `document`를 읽으면 iPad에서 모든 PDF가 비정상적으로
    // 종료되었다.
    private var made = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        made = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        made = true
    }

    // 연달아 일어나는 폭 변경(구분선을 프레임마다 끄는 경우)의 처음에 한 번 잡고, 폭이 잠시 그대로 있은 뒤에야 놓는다. 프레임마다 다시 잡으면 PDFKit이 이미 스크롤 오프셋 기준으로 줄인 쪽에서 자리를
    // 읽어 오차가 쌓였고, 구분선을 끌면 6쪽이 9쪽으로 갔다. 아무리 작은 변경도 센다. 칸이 제자리로 미끄러지는 동안 폭이 1초 동안 1pt보다 작게 바뀌는데, 이것도 쌓였다.
    private func hold(newWidth: CGFloat) {
        guard made, document != nil, newWidth > 0, newWidth != bounds.width else { return }
        if held == nil {
            guard bounds.width > 0, let spot = currentDestination, spot.page != nil else { return }
            held = spot
        }
        letGo?.cancel()
        // PDFKit은 배치 단계가 끝난 뒤에 쪽을 새 폭에 맞춰 줄일 수 있으므로, 그 뒤에 놓는다.
        let work = DispatchWorkItem { [weak self] in self?.release() }
        letGo = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settling, execute: work)
    }

    static let settling: TimeInterval = 0.2

    private func release(keep: Bool = false) {
        guard let spot = held else { return }
        if !keep { forget() }
        super.go(to: spot)
    }

    private func forget() {
        held = nil
        letGo?.cancel()
        letGo = nil
    }

    override func go(to page: PDFPage) {
        forget()
        super.go(to: page)
        waitForWidth(PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: displayBox).maxY)))
    }

    override func go(to destination: PDFDestination) {
        forget()
        super.go(to: destination)
        waitForWidth(destination)
    }

    private func waitForWidth(_ spot: PDFDestination) {
        if bounds.width == 0 { held = spot }
    }

    override func go(to selection: PDFSelection) {
        forget()
        super.go(to: selection)
    }

    #if os(macOS)
    override func setFrameSize(_ newSize: NSSize) {
        hold(newWidth: newSize.width)
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        release(keep: true)
    }
    #else
    override var frame: CGRect {
        get { super.frame }
        set {
            hold(newWidth: newValue.width)
            super.frame = newValue
        }
    }

    override var bounds: CGRect {
        get { super.bounds }
        set {
            hold(newWidth: newValue.width)
            super.bounds = newValue
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        release(keep: true)
    }
    #endif
}
