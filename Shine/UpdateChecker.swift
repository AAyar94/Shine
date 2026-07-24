//
//  UpdateChecker.swift
//  Shine
//
//  Checks the GitHub releases page for a newer version.
//

import Foundation

enum UpdateChecker {
    private static let repo = "AAyar94/Shine"
    private static let releasesURL = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    struct Result {
        let latestVersion: String
        let releaseURL: URL
    }

    /// Fetches the latest release tag from GitHub and compares it to the
    /// running app version. Returns `nil` when the app is up to date.
    static func check() async -> Result? {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let releaseURL = URL(string: htmlURLString)
        else { return nil }

        let latest = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard compareVersions(latest, isNewerThan: currentVersion) else { return nil }
        return Result(latestVersion: latest, releaseURL: releaseURL)
    }

    /// Simple numeric version comparison ("1.5" > "1.4", "2.0" > "1.9.1").
    private static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }
}
