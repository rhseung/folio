import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension SettingsCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .settingsShowAbstract), discussion: String(localized: .settingsShowDiscussion))
        @OptionGroup var g: GlobalOptions

        // 항목과 기본값은 `SettingItem` 선언에서 읽는다. 설정을 더하면 여기를 고치지 않아도 보인다.
        func run() throws {
            let s = try CLI.context(g).settings()
            if g.json { return try printJSON(s) }
            let root = try JSONValue(s)
            let pages = AppLink.SettingsPage.allCases.map(Optional.some) + [nil]
            let width = SettingItem.all.map { String(localized: $0.name).columns }.max() ?? 0
            for page in pages {
                let items = SettingItem.all.filter { $0.page == page }
                guard !items.isEmpty else { continue }
                say((page.map { AppLink.settings($0).string } ?? String(localized: .settingsShowElsewhere)).styled(.bold))
                for item in items {
                    let value = item.value(in: root) ?? .null
                    let shown = item.text(of: value)
                    let fallback = value == item.fallback ? "" : " " + String(localized: .settingsShowDefault(item.text(of: item.fallback)))
                    say(
                        "  " + String(localized: item.name).padded(to: width) + "  " + shown + fallback.styled(.dim) + "  "
                            + item.key.styled(.dim))
                }
                say()
            }
        }
    }
}

extension SettingsCommand.Show: HandRead {
    static let reason = "설정 항목 선언(SettingItem)에서 그리는 출력으로 옮긴다(#500)"
}
