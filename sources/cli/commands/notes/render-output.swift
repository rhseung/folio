import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

struct RenderOutput: ParsableArguments {
    @Option(name: .customLong("width"), help: ArgumentHelp(String(localized: .noteRenderHelpWidth), valueName: "points")) var widths:
        [Int] = []
    @Option(help: ArgumentHelp(String(localized: .noteRenderHelpOut), valueName: "folder"), completion: .directory) var out: String?

    var sizes: [Int] { widths.isEmpty ? PageRender.widths : widths.map { min(max($0, 200), 1600) } }

    func report(_ result: RenderResult, label: String, json: Bool) throws {
        if json { return try printJSON(result) }
        let folder = URL(filePath: out.map(absolute) ?? FileManager.default.temporaryDirectory.appending(path: "folio-render").path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for shot in result.images {
            let url = folder.appending(path: "\(label)-\(shot.theme)-\(shot.width).png")
            try Data(base64Encoded: shot.png)?.write(to: url)
            say(url.path)
        }
        for p in result.problems { warn(p) }
        for line in result.console { warn(line) }
    }
}
