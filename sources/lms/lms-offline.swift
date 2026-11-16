import Foundation

public enum LMSOffline {
    // 서버가 답하지 않은 것과 이 기기가 망에 닿지 않은 것을 함께 오프라인으로 본다. 둘 다 다음 주기에 다시 읽으면 되고,
    // 로그인을 다시 할 일이 아니다.
    public static func contains(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dataNotAllowed,
            .internationalRoamingOff, .dnsLookupFailed,
        ].contains(error.code)
    }
}
