import Foundation

struct AppRelease {
    let version: String
    let title: String
    let page: URL
}

/// Checks GitHub for a newer release.
///
/// Read-only and unauthenticated — it asks for the public releases endpoint and nothing
/// else. No telemetry goes the other way.
enum UpdateChecker {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/LinShanify/WritingToolsAnywhere/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct Payload: Decodable {
        let tag_name: String
        let name: String?
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Returns the newest release when it is newer than what's running, otherwise nil.
    static func check() async throws -> AppRelease? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.draft != true, payload.prerelease != true else { return nil }

        let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(version, than: currentVersion), let page = URL(string: payload.html_url)
        else { return nil }

        return AppRelease(version: version, title: payload.name ?? version, page: page)
    }

    /// Compares dotted numeric versions component by component, so 1.10 beats 1.9 —
    /// which a string comparison gets backwards.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
