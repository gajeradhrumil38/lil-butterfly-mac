import Foundation

struct Config: Codable {
    var minMinutes: Int
    var maxMinutes: Int
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var paused: Bool
    var messages: [String]

    static var `default`: Config {
        Config(
            minMinutes: 45,
            maxMinutes: 90,
            quietHoursEnabled: true,
            quietHoursStart: 23,
            quietHoursEnd: 7,
            paused: false,
            messages: [
                "Drink some water 💧",
                "Take a deep breath",
                "Roll your shoulders back",
                "You're doing better than you think",
                "Look away from the screen for 20 seconds",
                "Smile — even a small one counts 🙂",
                "Sit up a little straighter",
                "You've got this",
                "Stretch your neck side to side",
                "Remember to blink :)",
                "A little progress is still progress",
                "Unclench your jaw",
                "Go get some fresh air if you can",
                "You're allowed to take a short break",
                "Good posture check — how's it looking?",
            ]
        )
    }

    func isQuietHour(at date: Date = Date()) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietHoursStart == quietHoursEnd { return false }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            // wraps past midnight, e.g. 23 -> 7
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }

    func randomIntervalSeconds() -> TimeInterval {
        let minSec = Double(minMinutes) * 60
        let maxSec = Double(maxMinutes) * 60
        return Double.random(in: minSec...maxSec)
    }

    func randomMessage() -> String {
        messages.randomElement() ?? "You've got this"
    }
}

enum ConfigStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LilButterfly", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else {
            let def = Config.default
            save(def)
            return def
        }
        return config
    }

    static func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
