import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Action {
    static func decode(_ json: Data) throws -> Self {
        do {
            return try JSONDecoder.folio.decode(Self.self, from: json)
        } catch let error as DecodingError {
            throw CLIError(
                exit: .usage, message: String(localized: .runBadInput(RunCommand.describe(error))),
                hints: [String(localized: .runBadInputHint)])
        }
    }
}

extension JSONValue {
    func overlaid(with patch: JSONValue) -> JSONValue {
        guard case .object(var base) = self, case .object(let p) = patch else { return patch }
        for (k, v) in p { base[k] = base[k].map { $0.overlaid(with: v) } ?? v }
        return .object(base)
    }
}
