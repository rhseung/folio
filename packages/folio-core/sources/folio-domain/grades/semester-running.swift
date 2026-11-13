import Foundation

extension Semester {
    public func isRunning(on day: LocalDate) -> Bool {
        guard let start, let end else { return false }
        return start <= day && day <= end
    }
}
