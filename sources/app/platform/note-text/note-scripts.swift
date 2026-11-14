import FolioDomain
import JavaScriptCore
import Observation
import WebKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum NoteScripts {
    private static let helpers: JSValue? = {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(NoteStyle.resource("native.js"))
        return context.objectForKeyedSubscript("folioNative")
    }()

    static let languages: [String] =
        helpers?.objectForKeyedSubscript("languages").call(withArguments: [])?.toArray()?.compactMap { $0 as? String } ?? []

    static func highlight(_ code: String, language: String) -> [(range: NSRange, classes: String)] {
        guard let flat = helpers?.objectForKeyedSubscript("highlight").call(withArguments: [code, language])?.toArray() else { return [] }
        return stride(from: 0, to: flat.count - 2, by: 3).compactMap { i in
            guard let from = flat[i] as? Int, let to = flat[i + 1] as? Int, let cls = flat[i + 2] as? String else { return nil }
            return (NSRange(location: from, length: to - from), cls)
        }
    }
}
