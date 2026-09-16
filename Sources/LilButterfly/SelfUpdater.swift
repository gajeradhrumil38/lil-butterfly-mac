import AppKit

/// Downloads and installs the newest release in place, then relaunches —
/// so "Update" in the menu is a single click rather than sending the user to
/// a GitHub page to copy/paste a terminal command. Mirrors what
/// scripts/install.sh does from outside the app, using the same tools
/// (curl/ditto/xattr), just orchestrated in-process.
final class SelfUpdater {
    enum UpdateError: LocalizedError {
        case missingApp
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingApp: return "The download did not contain Butterfly.app."
            case .commandFailed(let detail): return detail
            }
        }
    }

    /// Runs entirely on a background queue. On success the new app is
    /// already launched and this process calls NSApp.terminate — completion
    /// only meaningfully fires on failure (the old process is still around
    /// to report it).
    func update(downloadURL: URL, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performUpdate(downloadURL: downloadURL)
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    private func performUpdate(downloadURL: URL) throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("butterfly-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let archivePath = tempDir.appendingPathComponent("Butterfly.zip")
        try run("/usr/bin/curl", ["-fL", "-s", downloadURL.absoluteString, "-o", archivePath.path])

        let extractDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archivePath.path, extractDir.path])

        guard let sourceApp = try fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent == "Butterfly.app" })
        else {
            throw UpdateError.missingApp
        }

        let destinationPath = "/Applications/Butterfly.app"
        // Replacing the files backing a running process's own bundle is
        // safe on macOS — already-mapped executable pages and already-open
        // resource handles stay valid until this process actually exits,
        // and nothing here reads new bundle content before the fresh
        // process (launched below) takes over.
        let replaceCommand = "rm -rf '\(destinationPath)' && ditto '\(sourceApp.path)' '\(destinationPath)' && xattr -dr com.apple.quarantine '\(destinationPath)' 2>/dev/null; true"

        if fileManager.isWritableFile(atPath: "/Applications") {
            try run("/bin/bash", ["-c", replaceCommand])
        } else {
            try runElevated(replaceCommand)
        }

        try run("/usr/bin/open", [destinationPath])
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed(message?.isEmpty == false ? message! : "\(launchPath) failed.")
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Prompts for the account password via the standard macOS
    /// authorization dialog — only reached if /Applications somehow isn't
    /// writable by the current user (uncommon; matches install.sh's own
    /// sudo fallback for the same case).
    private func runElevated(_ shellCommand: String) throws {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: appleScript) else {
            throw UpdateError.commandFailed("Could not prepare the elevated install step.")
        }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String ?? "The elevated install step failed."
            throw UpdateError.commandFailed(message)
        }
    }
}
