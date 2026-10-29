import FolioDomain
import FolioStorage
import Foundation
import Testing

struct EventLogTests {
    struct Ping: LogEvent, Equatable {
        static let type = "test_ping"
        var n: Int
    }

    let log = EventLog(folder: FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)/logs"))

    @Test func mergesDevicesInTimeOrder() throws {
        let mac = UUID(), ipad = UUID()
        try log.append(Ping(n: 1), device: mac, at: Date(timeIntervalSince1970: 10))
        try log.append(Ping(n: 2), device: ipad, at: Date(timeIntervalSince1970: 5))
        try log.append(Ping(n: 3), device: mac, at: Date(timeIntervalSince1970: 10.5))

        let events = try log.readAll()
        #expect(try events.compactMap { try $0.decode(Ping.self)?.n } == [2, 1, 3])
        #expect(Set(events.map(\.device)) == [mac, ipad])

        let files = try FileManager.default.contentsOfDirectory(atPath: log.folder.path)
        #expect(Set(files) == ["\(mac.uuidString).jsonl", "\(ipad.uuidString).jsonl"])
    }

    @Test func skipsCutOffLinesAndKeepsUnknownTypes() throws {
        let device = UUID()
        try log.append(Ping(n: 1), device: device, at: Date(timeIntervalSince1970: 1))
        let file = log.folder.appending(path: "\(device.uuidString).jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let future = #"{"schemaVersion":1,"id":"E0000000-0000-4000-8000-000000000001","at":"1970-01-01T00:00:02.000Z","device":"\#(device.uuidString)","type":"from_the_future","data":{"x":1}}"#
        try handle.write(contentsOf: Data((future + "\n{\"schemaVer").utf8))
        try handle.close()

        let events = try log.readAll()
        #expect(events.map(\.type) == [Ping.type, "from_the_future"])
        #expect(try events[1].decode(Ping.self) == nil)
    }

    @Test func deviceIDIsStable() {
        let defaults = UserDefaults(suiteName: "folio-test-\(UUID().uuidString)")!
        #expect(LocalDevice.id(in: defaults) == LocalDevice.id(in: defaults))
    }
}
