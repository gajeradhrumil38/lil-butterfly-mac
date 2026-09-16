import Foundation

/// Quietly logs each completed check-in choice locally — no viewer built
/// yet (a future history feature can read this data), no network calls
/// ever. Structurally identical to ConfigStore: same Application Support
/// directory, same atomic-write JSON pattern.
enum CheckInStore {
    private struct Entry: Codable {
        let date: Date
        let style: String
        let choice: String
    }

    private struct Log: Codable {
        var entries: [Entry]
    }

    private static let maxEntries = 500

    private static var fileURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Butterfly", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("checkins.json")
    }

    /// Appends one entry, dropping the oldest once past maxEntries so the
    /// file can't grow unbounded with no viewer ever trimming it.
    static func record(style: String, choice: String) {
        var log = load()
        log.entries.append(Entry(date: Date(), style: style, choice: choice))
        if log.entries.count > maxEntries {
            log.entries.removeFirst(log.entries.count - maxEntries)
        }
        save(log)
    }

    private static func load() -> Log {
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? JSONDecoder().decode(Log.self, from: data)
        else { return Log(entries: []) }
        return log
    }

    private static func save(_ log: Log) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
