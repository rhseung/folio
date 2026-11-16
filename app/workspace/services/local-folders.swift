import CryptoKit
import Foundation

// 테스트, 미리보기, `mise run render`가 시스템에 폴더를 물으면 이 Mac의 실제 폴더를 받는다. 그러면 픽스처로 돌린
// 실행이 사용자의 끝나지 않은 강의 녹음을 복구하거나 옮기거나 지울 수 있다. 그래서 이런 실행에서 폴더를 물으면 폴더
// 이름과 함께 process를 멈춘다. 그래야 빠뜨린 override가 실제 파일을 건드리기 전에 바로 드러난다.
enum LocalFolders {
    struct RealFolderInIsolatedRun: Error, CustomStringConvertible {
        let name: String
        var description: String {
            "Application Support/Folio/\(name) is this Mac's real folder; tests, previews and renders must give their own"
        }
    }

    static func isIsolated(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    // 테스트 호스트, 창 스냅숏 실행, 크기 측정 실행은 설치된 앱과 bundle ID가 같아서 UserDefaults도 사용자의 것을 쓴다. 그러면
    // 사용자가 숨긴 열과 접은 구획이 그림과 측정을 바꾸고, 실행이 바꾼 값은 사용자의 앱에 남는다. 그런 실행은 화면 상태를 기억하지 않는다.
    static func isolatesDefaults(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isIsolated(environment) || environment["FOLIO_SNAPSHOT_DIR"] != nil || environment["FOLIO_RESIZE_PROBE"] != nil
    }

    // 픽스처의 과목 ID는 고정되어 있다. 그래서 실제 폴더를 쓰면 픽스처 실행이 남긴 파일이 그곳에 계속 남고, 다음 픽스처
    // 실행이 실제 강의 녹음을 임시 폴더로 복구한 뒤 여기서 지운다. 따라서 픽스처로 돌린 앱(`FOLIO_GIST`, 창 스냅숏 포함)은
    // `perGIST` 폴더를 자기 임시 폴더에 둔다.
    static func url(_ name: String, perGIST: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment) throws
        -> URL
    {
        guard !isIsolated(environment) else { throw RealFolderInIsolatedRun(name: name) }
        if perGIST, let gist = environment[Workspace.environmentKey] {
            let digest = SHA256.hash(data: Data(gist.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
            return URL.temporaryDirectory.appending(path: "Folio-\(digest)/\(name)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Folio/\(name)", directoryHint: .isDirectory)
    }

    static func applicationSupport(_ name: String, perGIST: Bool = false) -> URL {
        do { return try url(name, perGIST: perGIST) } catch { fatalError("\(error)") }
    }
}
