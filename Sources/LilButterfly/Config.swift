import Foundation

struct Config: Codable {
    var minMinutes: Int
    var maxMinutes: Int
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var paused: Bool
    var messages: [String]
    var mode: String            // "roaming" | "docked"
    var dockEdge: String        // "left" | "right" | "top" | "bottom"
    var pinnedAssetIndex: Int?  // nil = random each visit
    var customIntervalSeconds: Double?  // nil = use minMinutes...maxMinutes; set by the menu's interval slider

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
            ],
            mode: "roaming",
            dockEdge: "right",
            pinnedAssetIndex: nil,
            customIntervalSeconds: nil
        )
    }

    init(
        minMinutes: Int, maxMinutes: Int, quietHoursEnabled: Bool, quietHoursStart: Int,
        quietHoursEnd: Int, paused: Bool, messages: [String], mode: String, dockEdge: String,
        pinnedAssetIndex: Int?, customIntervalSeconds: Double?
    ) {
        self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.paused = paused
        self.messages = messages
        self.mode = mode
        self.dockEdge = dockEdge
        self.pinnedAssetIndex = pinnedAssetIndex
        self.customIntervalSeconds = customIntervalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case minMinutes, maxMinutes, quietHoursEnabled, quietHoursStart, quietHoursEnd
        case paused, messages, mode, dockEdge, pinnedAssetIndex, customIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minMinutes = try c.decode(Int.self, forKey: .minMinutes)
        maxMinutes = try c.decode(Int.self, forKey: .maxMinutes)
        quietHoursEnabled = try c.decode(Bool.self, forKey: .quietHoursEnabled)
        quietHoursStart = try c.decode(Int.self, forKey: .quietHoursStart)
        quietHoursEnd = try c.decode(Int.self, forKey: .quietHoursEnd)
        paused = try c.decode(Bool.self, forKey: .paused)
        messages = try c.decode([String].self, forKey: .messages)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "roaming"
        dockEdge = try c.decodeIfPresent(String.self, forKey: .dockEdge) ?? "right"
        pinnedAssetIndex = try c.decodeIfPresent(Int.self, forKey: .pinnedAssetIndex)
        customIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .customIntervalSeconds)
    }

    func isQuietHour(at date: Date = Date()) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietHoursStart == quietHoursEnd { return false }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }

    func randomIntervalSeconds() -> TimeInterval {
        if let customIntervalSeconds { return customIntervalSeconds }
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
