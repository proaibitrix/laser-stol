import Foundation

enum ProjectStore {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("LaserStol", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var lastProjectURL: URL {
        supportDirectory.appendingPathComponent("LastProject.json")
    }

    static func save(_ document: ProjectDocument, to url: URL? = nil) throws {
        var doc = document
        doc.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(doc)
        try data.write(to: url ?? lastProjectURL, options: .atomic)
    }

    static func load(from url: URL? = nil) -> ProjectDocument? {
        let target = url ?? lastProjectURL
        guard let data = try? Data(contentsOf: target) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProjectDocument.self, from: data)
    }

    static func autosave(_ document: ProjectDocument) {
        try? save(document)
    }
}
