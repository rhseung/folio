import ArgumentParser
import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension Action {
    static func decode(_ json: Data) throws -> Self { try decodeInput(Self.self, json) }
}

func decodeInput<T: Decodable>(_ type: T.Type, _ json: Data) throws -> T {
    do {
        return try JSONDecoder.folio.decode(T.self, from: json)
    } catch let error as DecodingError {
        throw CLIError(
            exit: .usage, message: String(localized: .runBadInput(RunCommand.describe(error))),
            hints: [String(localized: .runBadInputHint)])
    }
}

extension JSONValue {
    func overlaid(with patch: JSONValue) -> JSONValue {
        guard case .object(var base) = self, case .object(let p) = patch else { return patch }
        for (k, v) in p { base[k] = base[k].map { $0.overlaid(with: v) } ?? v }
        return .object(base)
    }
}
