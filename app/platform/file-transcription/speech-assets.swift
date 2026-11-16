import AVFoundation
import FolioDomain
import Speech

enum SpeechAssets {
    // 앱은 locale을 예약해야 언어 모델을 볼 수 있다. 다른 앱이 이미 설치한 모델도 같다. 예약하기 전에는 상태가 미설치로 읽히고 설치를 요청해도 아무것도 돌아오지 않는데, 예전에는 이를 "이 언어는
    // 받아쓸 수 없다"로 읽었다.
    static func request(for transcriber: SpeechTranscriber, locale: Locale) async throws -> AssetInstallationRequest? {
        try await reserve(locale)
        guard await AssetInventory.status(forModules: [transcriber]) != .installed else { return nil }
        return try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    }

    static func context(_ hints: TranscriptionHints) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints.terms
        return context
    }

    private static func reserve(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) { return }
        if reserved.count >= AssetInventory.maximumReservedLocales, let other = reserved.first {
            _ = await AssetInventory.release(reservedLocale: other)
        }
        _ = try await AssetInventory.reserve(locale: locale)
    }
}
