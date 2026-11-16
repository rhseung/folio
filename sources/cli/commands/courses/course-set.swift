import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension CourseCommand {
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .courseSetAbstract), discussion: String(localized: .courseSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .commonHelpMemo))) var memo: String?
        @Option(help: ArgumentHelp(String(localized: .commonHelpCredits))) var credits: Double?
        @Option(help: ArgumentHelp(String(localized: .commonHelpMode))) var mode: GradingMode?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpColor(CourseColor.presets.joined(separator: ", "))), valueName: "color"))
        var color: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpIcon), valueName: "symbol")) var icon: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpReviews))) var reviews: Toggle?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpSharingApproved))) var sharingApproved: Toggle?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpGrade), valueName: "grade")) var grade: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpInstructor), valueName: "name")) var instructor: [String] = []
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpCategory), valueName: "category")) var category: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            var fields: [CourseSet.Field] = []
            if let memo { fields.append(.memo(memo)) }
            if let credits { fields.append(.credits(credits)) }
            if let mode { fields.append(.gradingMode(mode)) }
            if let color {
                let token = color == "none" ? "" : color
                guard token.isEmpty || CourseColor.presets.contains(token) else {
                    throw CLIError(
                        exit: .usage, message: String(localized: .courseSetColorUnknown(CourseColor.presets.joined(separator: ", "))))
                }
                fields.append(.color(token))
            }
            if let icon { fields.append(.icon(icon == "none" ? nil : icon)) }
            if let reviews { fields.append(.reviews(reviews.value)) }
            if let sharingApproved { fields.append(.sharingApproved(sharingApproved.value)) }
            if let grade { fields.append(.finalGrade(grade == "none" ? nil : try r.letterGrade(grade).id)) }
            if !instructor.isEmpty { fields.append(.instructors(try instructor.clearing.map { try r.person($0).id })) }
            if !category.isEmpty { fields.append(.categories(try category.clearing.map { try r.category($0).id })) }
            guard !fields.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .courseSetNothingToChange)) }
            try perform(spec: CourseSet(course: c.id, fields), g, ctx: ctx)
        }
    }
}
