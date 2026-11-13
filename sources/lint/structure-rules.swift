import Foundation
import SwiftSyntax

extension Rules {
    // AGENTS.md "레이어" and "화면: 모델과 뷰": app/design and app/platform are what screens build on, so they can't
    // reach back into a screen, and a screen's model is its own. The compiler can't see this: sources/app is one module.
    static var appDirection: Rule {
        Rule(
            name: "app-direction",
            advice: "app/design and app/platform don't use types from app/features, and a feature doesn't use another "
                + "feature's Model (AGENTS.md \"레이어\"); move the shared part down to app/design, app/platform or FolioDomain"
        ) { code in
            let owners = featureTypes(in: code)
            var hits: [Hit] = []
            for file in code.files(under: "sources/app") where !isDebugFile(file.path) {
                let feature = featureName(of: file.path)
                let lower = file.path.hasPrefix("sources/app/design/") || file.path.hasPrefix("sources/app/platform/")
                guard lower || feature != nil else { continue }
                for token in file.tokens {
                    guard case .identifier(let name) = token.tokenKind, let owner = owners[name], owner != feature,
                        lower || name.hasSuffix("Model"), !file.debugOnly(token)
                    else { continue }
                    hits.append(Hit("app-direction", file, file.line(of: token), "\(name) from features/\(owner)"))
                }
            }
            return hits
        }
    }

    // A type name declared under sources/app/features, by the feature it belongs to. A name also declared elsewhere is left out:
    // which one a file means is past a syntax tree.
    static func featureTypes(in code: Codebase) -> [String: String] {
        var owners: [String: String] = [:]
        var elsewhere: Set<String> = []
        for file in code.files(under: "sources", "tests", except: "tests/unit/app", "tests/e2e/app") {
            let feature = featureName(of: file.path)
            for name in declaredTypes(in: file) {
                if let feature, owners[name] == nil || owners[name] == feature { owners[name] = feature } else { elsewhere.insert(name) }
            }
        }
        return owners.filter { !elsewhere.contains($0.key) }
    }

    static func declaredTypes(in file: SourceFile) -> [String] {
        var names: [String] = []
        walk(Syntax(file.tree)) { node in
            if let declaration = node.as(StructDeclSyntax.self) { names.append(declaration.name.text) }
            if let declaration = node.as(ClassDeclSyntax.self) { names.append(declaration.name.text) }
            if let declaration = node.as(EnumDeclSyntax.self) { names.append(declaration.name.text) }
            if let declaration = node.as(ActorDeclSyntax.self) { names.append(declaration.name.text) }
            if let declaration = node.as(ProtocolDeclSyntax.self) { names.append(declaration.name.text) }
            if let declaration = node.as(TypeAliasDeclSyntax.self) { names.append(declaration.name.text) }
        }
        return names
    }

    static func featureName(of path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count > 4, parts[0] == "sources", parts[1] == "app", parts[2] == "features" else { return nil }
        return String(parts[3])
    }

    // AGENTS.md "앱 링크": a switch over AppLink.Kind has no `default:`, so a new kind doesn't compile until every
    // place handles it. Which enum a switch is over is past a syntax tree; a `….kind` switch whose every case is a
    // kind of AppLink is taken to be one.
    static var kindDefault: Rule {
        Rule(
            name: "kind-default",
            advice: "name every AppLink.Kind instead of `default:`, so a new kind fails to compile until it is handled "
                + "(AGENTS.md \"구조 축\" 앱 링크)"
        ) { code in
            let kinds = appLinkKinds(in: code)
            guard !kinds.isEmpty else { return [] }
            var hits: [Hit] = []
            for file in code.files(under: "sources", "tests", except: "tests/unit/app", "tests/e2e/app") {
                for switchExpr in file.nodes(SwitchExprSyntax.self) {
                    let subject = switchExpr.subject.trimmedDescription
                    guard subject == "kind" || subject.hasSuffix(".kind") else { continue }
                    var named: [String] = []
                    var fallback: SwitchDefaultLabelSyntax?
                    var other = false
                    for item in switchExpr.cases {
                        guard let switchCase = item.as(SwitchCaseSyntax.self) else { other = true; continue }
                        switch switchCase.label {
                        case .default(let label): fallback = label
                        case .case(let label):
                            for caseItem in label.caseItems {
                                let pattern = caseItem.pattern.as(ExpressionPatternSyntax.self)?.expression
                                if let member = pattern?.as(MemberAccessExprSyntax.self), member.base == nil {
                                    named.append(member.declName.baseName.text)
                                } else {
                                    other = true
                                }
                            }
                        }
                    }
                    guard let fallback, !other, !named.isEmpty, named.allSatisfy(kinds.contains) else { continue }
                    hits.append(Hit("kind-default", file, file.line(of: fallback), "switch \(subject) default:"))
                }
            }
            return hits
        }
    }

    static func appLinkKinds(in code: Codebase) -> Set<String> {
        var kinds: Set<String> = []
        for file in code.files(under: "sources", "tests", except: "sources/app", "tests/unit/app", "tests/e2e/app") {
            for declaration in file.nodes(EnumDeclSyntax.self) where declaration.name.text == "Kind" {
                var parent = declaration.parent
                while let node = parent, !node.is(StructDeclSyntax.self), !node.is(ExtensionDeclSyntax.self) { parent = node.parent }
                let owner =
                    parent?.as(StructDeclSyntax.self)?.name.text
                    ?? parent?.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
                guard owner == "AppLink" else { continue }
                for element in declaration.memberBlock.members.compactMap({ $0.decl.as(EnumCaseDeclSyntax.self) }) {
                    kinds.formUnion(element.elements.map(\.name.text))
                }
            }
        }
        return kinds
    }

    // AGENTS.md "구조 축" 라이브 시계: a view that changes by the minute reads `workspace.liveNow`, which also moves when
    // the app comes forward or the Mac wakes; a TimelineView of its own misses both. Only a timer counting seconds keeps one.
    static var minuteTimeline: Rule {
        Rule(
            name: "minute-timeline",
            advice: "read workspace.liveNow or LiveTime for a view that changes by the minute or day; TimelineView is for "
                + "timers counting seconds (AGENTS.md \"구조 축\" 라이브 시계)"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app") {
                for call in file.nodes(FunctionCallExprSyntax.self) where calledName(call) == "TimelineView" {
                    guard let schedule = call.arguments.first?.expression, slowSchedule(schedule) else { continue }
                    hits.append(Hit("minute-timeline", file, file.line(of: call), "TimelineView(\(scheduleName(schedule)))"))
                }
            }
            return hits
        }
    }

    static func slowSchedule(_ schedule: ExprSyntax) -> Bool {
        if schedule.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "everyMinute" { return true }
        guard let call = schedule.as(FunctionCallExprSyntax.self), calledName(call) == "periodic",
            let period = call.arguments.first(where: { $0.label?.text == "by" })?.expression
        else { return false }
        let text = period.trimmedDescription.filter { $0 != "_" }
        return (Double(text) ?? 0) >= 60
    }

    static func scheduleName(_ schedule: ExprSyntax) -> String {
        if let call = schedule.as(FunctionCallExprSyntax.self), let name = calledName(call) { return ".\(name)" }
        return schedule.trimmedDescription
    }

    // AGENTS.md "화면 계약": a screen puts nothing in the window's toolbar; its tools go in PageBar and its side panels
    // behind a FAB, since the window (or a pane) draws the frame.
    static var screenToolbar: Rule {
        Rule(
            name: "screen-toolbar",
            advice: "a screen doesn't fill the window's toolbar: tools go in PageBar, side panels behind a FAB "
                + "(AGENTS.md \"화면: 모델과 뷰\" 화면 계약)"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app/features") where !isDebugFile(file.path) {
                for call in file.nodes(FunctionCallExprSyntax.self) {
                    guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                        member.declName.baseName.text == "toolbar", !file.debugOnly(call)
                    else { continue }
                    hits.append(Hit("screen-toolbar", file, file.line(of: member.declName), ".toolbar"))
                }
            }
            return hits
        }
    }

    // Launch settings (the GIST folder, test hosting, the isolated local folders) are read where the app and the CLI
    // set themselves up, so a knob for one run can't sit unseen in a screen. Debug code and tests are free to read them.
    static var launchEnvironment: Rule {
        Rule(
            name: "launch-environment",
            advice: "read the process environment only in the launch files ("
                + launchFiles.sorted().joined(separator: ", ") + ") and pass the value in"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources", except: "sources/lint", "sources/lint-command")
            where !isDebugFile(file.path) && !launchFiles.contains(file.path) {
                for member in file.nodes(MemberAccessExprSyntax.self) where member.declName.baseName.text == "environment" {
                    guard member.base?.trimmedDescription == "ProcessInfo.processInfo", !file.debugOnly(member) else { continue }
                    hits.append(Hit("launch-environment", file, file.line(of: member), "ProcessInfo.processInfo.environment"))
                }
            }
            return hits
        }
    }

    static let launchFiles: Set<String> = [
        "sources/app/app/folio-app.swift", "sources/app/app/services/local-folders.swift", "sources/app/app/workspace/workspace.swift",
        "sources/cli/core/environment.swift",
    ]

    // AGENTS.md "이름과 주석": file and folder names are lower kebab case.
    static var kebabNames: Rule {
        Rule(name: "kebab-names", advice: "name files and folders in lower kebab case (AGENTS.md \"이름과 주석\")") { code in
            var hits: [Hit] = []
            for path in code.paths {
                var parts = path.split(separator: "/").map(String.init)
                guard parts.last != "Package.swift" else { continue }
                parts[parts.count - 1] = String(parts[parts.count - 1].dropLast(".swift".count))
                for part in parts where !isKebab(part) {
                    hits.append(Hit("kebab-names", path: path, 1, part))
                }
            }
            return hits
        }
    }

    static func isKebab(_ name: String) -> Bool {
        name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { piece in
            !piece.isEmpty
                && piece.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { word in
                    !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
                }
        }
    }

    static let folderLimit = 20

    // A folder past twenty files has stopped saying what is in it; split it by the parts a reader looks for
    // (`features/<기능>/<구역>`), and keep tests in the shape of their sources.
    static var folderSize: Rule {
        Rule(
            name: "folder-size",
            advice: "keep a folder to \(folderLimit) Swift files: group them in subfolders by what a reader looks for, "
                + "at most features/<기능>/<구역> deep, tests shaped like their sources"
        ) { code in
            let folders = Dictionary(grouping: code.paths) { ($0 as NSString).deletingLastPathComponent }
            return folders.filter { $0.value.count > folderLimit }.keys.sorted().map {
                Hit("folder-size", path: $0, 1, "more than \(folderLimit) files")
            }
        }
    }
}
