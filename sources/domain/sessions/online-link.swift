import Foundation

public enum OnlineLink {
    public static func stored(_ text: String?) -> String? {
        text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }

    // 웹 링크는 브라우저 탭을 열고 앱으로 넘길지 묻지만, 이 scheme은 바로 앱으로 간다.
    public static func appURL(_ url: URL) -> URL? {
        guard let host = url.host()?.lowercased(), host == "zoom.us" || host.hasSuffix(".zoom.us") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "j", parts[1].allSatisfy(\.isNumber) else { return nil }

        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = "zoom.us"
        app.path = "/join"
        let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pwd" }?.value
        app.queryItems =
            [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
            + (pwd.map { [URLQueryItem(name: "pwd", value: $0)] } ?? [])
        return app.url
    }
}
