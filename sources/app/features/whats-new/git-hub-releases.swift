import FolioDomain
import Foundation
import Observation

// 토큰 없이 공개 저장소의 릴리스를 읽는다. 노트를 앱에 묶지 않으므로, 머지한 뒤 고친 PR 본문도 릴리스를 거쳐 앱에
// 닿는다.
struct GitHubReleases: ReleaseFeed {
    // 백 개면 몇 년 치 릴리스다. 그보다 많으면 가장 새것이 아니라 가장 오래된 것이 페이지에서 빠진다.
    static let url = URL(string: "https://api.github.com/repos/rhseung/folio/releases?per_page=100")!

    func releases() async throws -> [PatchNotes.Release] {
        var request = URLRequest(url: Self.url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try PatchNotes.releases(fromGitHub: data)
    }
}
