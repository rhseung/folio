import Foundation

// 폴더의 깊이와 이름을 그 무게에 맞춘다(AGENTS.md "프로젝트 구조"). 무게는 하위 폴더까지 포함한 Swift 파일 수다. 바로 아래
// 파일만 세면 하위 폴더로만 나뉜 큰 폴더(`app`)가 가벼운 폴더로 잡힌다.
extension Rules {
    static let folderLimit = 20

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

    static var folderSmall: Rule {
        Rule(
            name: "folder-small", strict: true,
            advice: "don't keep a folder for one Swift file, or for two unless it is named for an area "
                + "(sources/tools/lint/area.swift): move the files up into the folder above. An area folder of an area "
                + "layer and a test folder shaped like its source folder may be small"
        ) { code in
            let weights = folderWeights(code.paths)
            let layers = Set(areaLayers)
            return weights.keys.sorted().compactMap { folder in
                guard let weight = weights[folder], weight <= 2, !toolOwned(folder), let parent = parentFolder(folder),
                    !layers.contains(parent), !mirrorsSource(folder, in: weights)
                else { return nil }
                if weight == 2, Area.names.contains(baseName(folder)) { return nil }
                return Hit("folder-small", path: folder, 1, weight == 1 ? "one Swift file" : "two Swift files")
            }
        }
    }

    static let heavyNames: Set = ["core", "shared", "common", "base", "utils", "helpers", "misc", "app"]

    static var folderName: Rule {
        Rule(
            name: "folder-name", strict: true,
            advice: "name a folder in a module for the part it holds: not a heavy name ("
                + heavyNames.sorted().joined(separator: ", ") + ") that only fits right under sources/, "
                + "not its parent's name again (sessions/transcription, not sessions/sessions), and under app/features "
                + "not a view or model (the file name says the role)"
        ) { code in
            folderWeights(code.paths).keys.sorted().compactMap { folder in
                guard !toolOwned(folder), let parent = parentFolder(folder) else { return nil }
                let name = baseName(folder)
                let above = baseName(parent)
                if heavyNames.contains(name) { return Hit("folder-name", path: folder, 1, name + "/") }
                if repeats(name, above) { return Hit("folder-name", path: folder, 1, "\(above)/\(name)/") }
                if folder.hasPrefix(RepoPath.features + "/"), name.hasSuffix("-view") || name.hasSuffix("-model") {
                    return Hit("folder-name", path: folder, 1, name + "/")
                }
                return nil
            }
        }
    }

    static var areaFolder: Rule {
        Rule(
            name: "area-folder", strict: true,
            advice: "a folder right under an area layer (" + areaLayers.joined(separator: ", ")
                + ") is an area from the area table (sources/tools/lint/area.swift); add a new area to the table first"
        ) { code in
            let layers = Set(areaLayers)
            return folderWeights(code.paths).keys.sorted().compactMap { folder in
                guard let parent = parentFolder(folder), layers.contains(parent) else { return nil }
                let name = baseName(folder)
                guard !Area.names.contains(name), !RepoPath.layerBases.contains(name) else { return nil }
                return Hit("area-folder", path: folder, 1, name + "/")
            }
        }
    }

    // tests/unit은 sources와 같은 경로로 나누므로 영역 층도 같은 경로에 있다.
    static var areaLayers: [String] {
        let prefix = RepoPath.packages + "/"
        return RepoPath.areaLayers
            + RepoPath.areaLayers.filter { $0.hasPrefix(prefix) }.map { RepoPath.unitTests + "/" + $0.dropFirst(prefix.count) }
    }

    static func folderWeights(_ paths: [String]) -> [String: Int] {
        var weights: [String: Int] = [:]
        for path in paths {
            var folder = (path as NSString).deletingLastPathComponent
            while !folder.isEmpty {
                weights[folder, default: 0] += 1
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return weights
    }

    static func toolOwned(_ folder: String) -> Bool {
        RepoPath.roots.contains(folder) || RepoPath.moduleParents.contains(folder)
            || parentFolder(folder).map { RepoPath.moduleParents.contains($0) } == true
            || folder.split(separator: "/").contains { $0 == RepoPath.generated }
    }

    // 테스트 폴더는 그 소스 폴더를 따라 나누므로 무게를 소스 폴더가 정한다.
    static func mirrorsSource(_ folder: String, in weights: [String: Int]) -> Bool {
        let prefix = RepoPath.unitTests + "/"
        guard folder.hasPrefix(prefix) else { return false }
        return weights[RepoPath.packages + "/" + folder.dropFirst(prefix.count)] != nil
    }

    // `sessions/session-recording`처럼 단수형으로 되풀이해도 잡는다.
    static func repeats(_ name: String, _ parent: String) -> Bool {
        let stems = parent.hasSuffix("s") ? [parent, String(parent.dropLast())] : [parent]
        return stems.contains { name == $0 || name.hasPrefix($0 + "-") }
    }

    static func parentFolder(_ folder: String) -> String? {
        let parent = (folder as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    static func baseName(_ folder: String) -> String { (folder as NSString).lastPathComponent }
}
