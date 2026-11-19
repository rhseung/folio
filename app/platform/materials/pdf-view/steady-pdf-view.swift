import CoreImage
import Observation
import PDFKit
import SwiftUI

final class SteadyPDFView: PDFView {
    private var held: PDFDestination?
    private var settled: PDFDestination?
    private var letGo: DispatchWorkItem?
    // UIKit은 PDFView가 `document`에 필요한 것을 만들기 전에 `init(frame:)` 안에서 frame을 정한다. 그때 `document`를 읽으면 iPad에서 모든 PDF가 비정상적으로
    // 종료되었다.
    private var made = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        made = true
        watchPage()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        made = true
        watchPage()
    }

    private func watchPage() {
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: self)
    }

    // 연달아 일어나는 폭 변경(구분선을 프레임마다 끄는 경우)의 처음에 한 번 잡고, 폭이 잠시 그대로 있은 뒤에야 놓는다. 프레임마다 다시 잡으면 PDFKit이 이미 스크롤 오프셋 기준으로 줄인 쪽에서 자리를
    // 읽어 오차가 쌓였고, 구분선을 끌면 6쪽이 9쪽으로 갔다. 아무리 작은 변경도 센다. 칸이 제자리로 미끄러지는 동안 폭이 1초 동안 1pt보다 작게 바뀌는데, 이것도 쌓였다.
    private func hold(newWidth: CGFloat) {
        guard made, document != nil, newWidth > 0, newWidth != bounds.width else { return }
        if held == nil {
            guard bounds.width > 0, let spot = currentDestination, spot.page != nil else { return }
            held = spot
            settled = nil
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
        if !keep {
            forget()
            settled = spot
        }
        super.go(to: spot)
    }

    private func forget() {
        held = nil
        settled = nil
        letGo?.cancel()
        letGo = nil
    }

    // 폭이 바뀌면 PDFKit은 화면을 움직이지 않고 현재 쪽을 스스로 다시 고르는데, 맨 위 쪽이 아니라 가운데 쪽을 고른다. 이 다시 고르기는 대개 붙잡은 자리로
    // 돌아갈 때 함께 되돌려지지만, main 스레드가 바쁘면 놓은 뒤에야 와서 쪽 번호만 한 쪽 뒤로 남았다. 그래서 놓은 자리에서 화면이 움직이지 않았는데 현재 쪽이
    // 바뀌면 그 자리로 한 번 더 간다. 화면이 움직였으면 사용자가 넘긴 것이므로 놓아 준다. PDFKit이 알림을 보내는 도중이므로 그 호출이 끝난 뒤에 간다.
    @objc private func pageChanged() {
        guard let spot = held ?? settled else { return }
        guard stays(at: spot) else {
            settled = nil
            return
        }
        if currentPage != spot.page { DispatchQueue.main.async { [weak self] in self?.keepPage() } }
    }

    private func keepPage() {
        guard let spot = held ?? settled, stays(at: spot), currentPage != spot.page else { return }
        super.go(to: spot)
    }

    private func stays(at spot: PDFDestination) -> Bool {
        guard let now = currentDestination else { return false }
        return now.page == spot.page && abs(now.point.y - spot.point.y) < Self.samePlace
    }

    // 놓은 자리를 다시 읽으면 반올림 때문에 1pt 안팎으로 달라진다.
    static let samePlace: CGFloat = 2

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
