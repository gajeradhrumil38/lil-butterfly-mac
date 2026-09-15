import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let name: String?

    var version: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}

/// Checks GitHub Releases only. No analytics or user data is sent.
final class UpdateChecker {
    private let repository = "gajeradhrumil38/lil-butterfly-mac"
    private let currentVersion: String

    init(currentVersion: String) {
        self.currentVersion = currentVersion
    }

    func check(completion: @escaping (Result<GitHubRelease?, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            completion(.failure(UpdateError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Butterfly/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [currentVersion] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(UpdateError.invalidResponse))
                return
            }
            guard (200..<300).contains(http.statusCode), let data else {
                completion(.failure(UpdateError.httpStatus(http.statusCode)))
                return
            }
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                completion(self.isNewer(release.version, than: currentVersion) ? .success(release) : .success(nil))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        let count = max(remoteParts.count, localParts.count)
        for index in 0..<count {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                Int(component.filter(\Character.isNumber)) ?? 0
            }
    }

    enum UpdateError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The update URL is invalid."
            case .invalidResponse: return "GitHub returned an invalid update response."
            case .httpStatus(let code): return "GitHub returned HTTP \(code)."
            }
        }
    }
}
