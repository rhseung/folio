import FolioActions
import FolioDomain
import SwiftUI

struct JoinOnlineButton: View {
    @Environment(\.openURL) private var openURL
    let url: URL
    var prominent = false

    var body: some View {
        if prominent {
            Button(.sessionsJoin, systemImage: "video") { Self.join(url, openURL) }.buttonStyle(.prominent)
                .help(url.absoluteString)
        } else {
            SessionSlot(String(localized: .sessionsJoin), symbol: "video", help: url.absoluteString, fixed: false) {
                Self.join(url, openURL)
            }
        }
    }

    static func join(_ url: URL, _ openURL: OpenURLAction) {
        guard let app = OnlineLink.appURL(url) else { return openURL(url) }
        openURL(app, completion: fallback(to: url, with: openURL))
    }

    // macOS에서 LaunchServices는 이 completion을 자기 background queue에서 부른다. 여기서 쓴 클로저는 View 안이라
    // @MainActor로 추론되고, Swift 6는 그것이 main queue 밖에서 돌면 trap 한다. 그래서 @Sendable로 두고 웹 링크를 열기
    // 전에 main actor로 돌아가야 한다.
    static func fallback(to url: URL, with openURL: OpenURLAction) -> @Sendable (Bool) -> Void {
        { @Sendable accepted in
            if !accepted { Task { @MainActor in openURL(url) } }
        }
    }
}
