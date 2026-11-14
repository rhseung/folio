import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialCommand {
    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .materialSplitAbstract), discussion: String(localized: .materialSplitDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpMaterial), valueName: "material"), completion: Complete.materials)
        var material: String
        @Argument(help: ArgumentHelp(String(localized: .materialSplitHelpSections), valueName: "pages:unit")) var sections: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            var made: [String: UUID] = [:]
            let cuts = try sections.map { arg in
                // 쪽에는 콜론이 없고 단원 제목에는 있을 수 있으므로 첫 콜론에서 나눈다.
                guard let colon = arg.firstIndex(of: ":") else {
                    throw CLIError(exit: .usage, message: String(localized: .materialSplitFormat(arg)))
                }
                let bounds = arg[..<colon].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
                let title = String(arg[arg.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                guard (1...2).contains(bounds.count), let first = bounds.first ?? nil, let last = bounds.last ?? nil, !title.isEmpty else {
                    throw CLIError(exit: .usage, message: String(localized: .materialSplitFormat(arg)))
                }
                if let unit = c.file.units.first(where: { $0.title == title }) {
                    return LectureCut(unit: unit.id, firstPage: first, lastPage: last)
                }
                let id = made[title] ?? UUID()
                made[title] = id
                return LectureCut(unit: id, title: title, firstPage: first, lastPage: last)
            }
            try perform(spec: MaterialSplit(course: c.id, material: m.id, sections: cuts), g, ctx: ctx)
        }
    }
}
