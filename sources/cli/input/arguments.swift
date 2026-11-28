import ArgumentParser
import FolioCore
import FolioDomain
import Foundation

extension UUID: @retroactive ExpressibleByArgument {
    public init?(argument: String) { self.init(uuidString: argument) }
}

extension NoteKind: ExpressibleByArgument {}
extension NoteFormat: ExpressibleByArgument {}
extension MathSyntax: ExpressibleByArgument {}
extension AttendanceState: ExpressibleByArgument {}
extension AssignmentStatus: ExpressibleByArgument {}
extension AssignmentRepeat: ExpressibleByArgument {
    public init?(argument: String) { self.init(text: argument) }
}
extension MaterialStatus: ExpressibleByArgument {}
extension GradingMode: ExpressibleByArgument {}
extension Term: ExpressibleByArgument {}
extension ProblemSource: ExpressibleByArgument {}
extension SolveMode: ExpressibleByArgument {}
extension GradeBasis: ExpressibleByArgument {}
extension WrongReason: ExpressibleByArgument {}
extension Verdict: ExpressibleByArgument {}
extension ExamPlanPeriod.After: ExpressibleByArgument {}

extension Session.Kind: ExpressibleByArgument {
    public init?(argument: String) { self.init(word: argument) }
}

extension JSONValue: ExpressibleByArgument {
    public init?(argument: String) {
        self = (try? JSONDecoder().decode(JSONValue.self, from: Data(argument.utf8))) ?? .string(argument)
    }
}

extension LocalDate: ExpressibleByArgument {
    public init?(argument: String) { self.init(argument) }
}

extension [String] {
    var clearing: [String] { self == ["none"] ? [] : self }
}
