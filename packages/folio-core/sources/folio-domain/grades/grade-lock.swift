/// docs/SPEC.md "성적 잠금": the app and `folio` keep grades shown this long after the owner unlocks them.
public enum GradeLock {
    public static let unlockSeconds: Double = 5 * 60
    /// The longest `folio unlock --for` takes, so a typo like 999h can't leave grades open for good.
    public static let maxUnlockSeconds: Double = 12 * 60 * 60
}
