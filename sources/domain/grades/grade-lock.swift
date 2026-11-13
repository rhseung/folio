public enum GradeLock {
    public static let unlockSeconds: Double = 5 * 60
    // 999h 같은 오타로 성적이 계속 열려 있지 않도록 `folio unlock --for`의 최대 시간을 제한한다.
    public static let maxUnlockSeconds: Double = 12 * 60 * 60
}
