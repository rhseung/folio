// The one place the version is set. `mise run version-bump` rewrites the line below, `mise run generate` copies it into
// the app's MARKETING_VERSION, and the release workflow refuses a tag that differs from it. The build number is not
// here: it is the commit count, which only the build knows (scripts/version.sh).
public enum FolioVersion {
    public static let marketing = "0.1.0"
}
