import Foundation

struct SavedPlaylist: Codable {
    var version = 1
    var name: String
    var tracks: [Entry]
    var selectedIndex: Int?
    var highlightedIndex: Int? = nil
    var options: Options
    struct Entry: Codable {
        var path: String
        var bookmark: Data?
        var fade: FadeMode
        var position: Double
        var title: String? = nil
        var occurrenceID: String? = nil
    }
    struct Options: Codable {
        var startMode: StartMode
        var endMode: EndMode
        var stopBeforeEnd: Double
        var shuffle: Bool
        var repeatAll: Bool
    }
    static func relativePath(_ url: URL, to directory: URL) -> String {
        let a = directory.standardizedFileURL.pathComponents, b = url.standardizedFileURL.pathComponents
        var common = 0
        while common < min(a.count,b.count), a[common] == b[common] { common += 1 }
        return (Array(repeating: "..", count:a.count-common) + b.dropFirst(common)).joined(separator:"/")
    }
    func write(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(self).write(to:url,options:.atomic)
    }
    static func read(from url: URL) throws -> SavedPlaylist {
        let data = try Data(contentsOf:url)
        guard data.count <= 5_000_000 else { throw PlaylistError.invalid }
        let value = try JSONDecoder().decode(Self.self,from:data)
        guard value.version == 1, value.tracks.count <= 10000,
              value.tracks.allSatisfy({ !$0.path.isEmpty && $0.position.isFinite && $0.position >= 0 && ($0.occurrenceID.map { UUID(uuidString:$0) != nil } ?? true) }),
              value.options.stopBeforeEnd.isFinite, (0...30).contains(value.options.stopBeforeEnd),
              (value.selectedIndex.map({value.tracks.indices.contains($0)}) ?? true),
              (value.highlightedIndex.map({value.tracks.indices.contains($0)}) ?? true) else { throw PlaylistError.invalid }
        return value
    }
    enum PlaylistError: LocalizedError { case invalid
        var errorDescription: String? { "This playlist is damaged or uses an unsupported version." }
    }
}
