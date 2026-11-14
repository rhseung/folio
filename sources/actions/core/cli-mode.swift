public enum CLIMode: Sendable {
    case generated, manual
    public static func manual(reason: String) -> CLIMode { .manual }
}
