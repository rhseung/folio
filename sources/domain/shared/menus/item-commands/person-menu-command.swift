import Foundation

// MARK: People, codes, requirements

public enum PersonMenuCommand: ItemCommand {
    case open, mail, share, remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .mail: .start
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, hasMail: Bool) -> [PersonMenuCommand] {
        (host.opensItem ? [.open] : []) + (hasMail ? [.mail] : []) + [.share, .remove]
    }
}
