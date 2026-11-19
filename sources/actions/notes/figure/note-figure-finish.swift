import CoreText
import FolioDomain
import Foundation
import JavaScriptCore

// 노트 그림을 쓰기 전에 그림 스타일을 넣고 검사한다. 일은 웹 번들의 그림 엔진(sources/web/src/figure.js)이 하고, 앱과
// CLI가 같은 결과를 내도록 둘 다 이 타입으로 부른다. 엔진은 MathJax를 담아 크므로 처음 쓸 때 한 번 읽는다.
public enum NoteFigureFinish {
    public struct Finished: Sendable {
        public let svg: String
        public let problems: [NoteFigure.Problem]
    }

    public struct EngineFailure: Error, CustomStringConvertible {
        public let description: String
    }

    public static func finish(_ svg: String) throws -> Finished {
        let source = try engine.call("source", svg)
        let found = NoteFigure.problems(source)
        if found.contains(where: { if case .notXML = $0 { true } else if case .notSVG = $0 { true } else { false } }) {
            return Finished(svg: svg, problems: found)
        }
        let out = try engine.call("finish", source, FigureStyle.engineJSON)
        guard let result = try? JSONDecoder().decode(EngineResult.self, from: Data(out.utf8)) else {
            throw EngineFailure(description: "figure.js: \(out.prefix(200))")
        }
        var problems = found
        for p in result.problems.compactMap(\.problem) where !problems.contains(p) { problems.append(p) }
        return Finished(svg: result.svg, problems: problems)
    }

    // 쓸 때 넣은 것을 걷어 낸, 쓴 사람이 쓴 모양이다. 고쳐 쓸 사람은 이 모양을 읽는다.
    public static func source(_ svg: String) throws -> String { try engine.call("source", svg) }

    // 노트의 mermaid 블록 하나를 미리보기와 같은 배치로 그려 본 그림 검사 결과다.
    public static func diagramProblems(_ mermaid: String) throws -> [NoteFigure.Problem] {
        let out = try engine.call("diagram", mermaid, FigureStyle.engineJSON)
        guard let result = try? JSONDecoder().decode(DiagramResult.self, from: Data(out.utf8)) else {
            throw EngineFailure(description: "figure.js: \(out.prefix(200))")
        }
        var problems: [NoteFigure.Problem] = []
        for p in result.problems.compactMap(\.problem) where !problems.contains(p) { problems.append(p) }
        return problems
    }

    private struct EngineResult: Decodable {
        var svg: String
        var problems: [Found]
    }

    private struct DiagramResult: Decodable {
        var problems: [Found]
    }

    private struct Found: Decodable {
        var kind: String
        var a, b, shape, tex, reason, text: String?

        var problem: NoteFigure.Problem? {
            switch kind {
            case "tex": .tex(tex ?? "", reason: reason ?? "")
            case "tspan": .tspanMath(text ?? "")
            case "labels": .overlap(a ?? "", b ?? "")
            case "line": .onLine(a ?? "", shape ?? "")
            case "fill": .onEdge(a ?? "", shape ?? "")
            case "outside": .outside(a ?? "")
            case "through": .notThrough(a ?? "", b ?? "", gap: text ?? "")
            case "point": .noPoint(a ?? "", b ?? "")
            case "diagram": .notDrawn(reason ?? "")
            default: nil
            }
        }
    }

    private static let engine = Engine()
}

// JSContext는 한 번에 한 스레드만 쓸 수 있어서 잠금 안에서만 부른다.
private final class Engine: @unchecked Sendable {
    private let lock = NSLock()
    private var context: JSContext?

    func call(_ name: String, _ arguments: String...) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        let context = try loaded()
        let function = context.objectForKeyedSubscript("folioFigure")?.objectForKeyedSubscript(name)
        let value = function?.call(withArguments: arguments)
        if let error = context.exception {
            context.exception = nil
            throw NoteFigureFinish.EngineFailure(description: "figure.js \(name): \(error)")
        }
        guard let text = value?.toString() else { throw NoteFigureFinish.EngineFailure(description: "figure.js \(name)") }
        return text
    }

    private func loaded() throws -> JSContext {
        if let context { return context }
        guard let url = Bundle.module.url(forResource: "figure", withExtension: "js") else {
            throw NoteFigureFinish.EngineFailure(description: "figure.js가 \(Bundle.module.bundlePath)에 없습니다")
        }
        let script: String
        do { script = try String(contentsOf: url, encoding: .utf8) } catch {
            throw NoteFigureFinish.EngineFailure(description: "figure.js를 읽지 못했습니다: \(error)")
        }
        guard let made = JSContext() else { throw NoteFigureFinish.EngineFailure(description: "JSContext를 만들지 못했습니다") }
        let measure: @convention(block) (String, Double, Double) -> Double = { text, px, weight in Self.width(text, px, weight) }
        made.setObject(unsafeBitCast(measure, to: AnyObject.self), forKeyedSubscript: "folioMeasure" as NSString)
        made.evaluateScript(script)
        if let error = made.exception { throw NoteFigureFinish.EngineFailure(description: "figure.js: \(error)") }
        context = made
        return made
    }

    // 노트 페이지가 그림 글자를 그리는 글꼴(시스템 산세리프, 한글은 Apple SD Gothic Neo로 이어짐)로 잰다. 겹침 검사가
    // 실제로 보이는 폭과 같아야 하기 때문이다.
    private static func width(_ text: String, _ px: Double, _ weight: Double) -> Double {
        let kind: CTFontUIFontType = weight >= 600 ? .emphasizedSystem : .system
        guard let font = CTFontCreateUIFontForLanguage(kind, CGFloat(px), nil) else { return Double(text.count) * px * 0.6 }
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(string)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}
