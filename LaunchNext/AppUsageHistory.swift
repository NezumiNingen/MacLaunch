import Foundation

enum AppPathIdentity {
    nonisolated static func claim(_ path: String, in seenPaths: inout Set<String>) -> Bool {
        let normalizedPath = standardized(path)
        guard !normalizedPath.isEmpty else { return false }
        return seenPaths.insert(normalizedPath).inserted
    }

    nonisolated static func standardized(_ path: String) -> String {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

/// Stores this Mac's observed GUI app launches locally and ranks folder items.
/// macOS does not expose a public lifetime launch counter for other apps, so
/// counts begin when LaunchNext is running with this feature installed.
enum AppUsageHistory {
    static let storageKey = "appUsageHistory.launchCountsByPath"

    static func recordLaunch(path: String, defaults: UserDefaults = .standard) -> Bool {
        let normalizedPath = AppPathIdentity.standardized(path)
        guard !normalizedPath.isEmpty else { return false }
        var counts = defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
        counts[normalizedPath, default: 0] += 1
        defaults.set(counts, forKey: storageKey)
        return true
    }

    static func orderedPaths(_ paths: [String],
                             pinnedPaths: Set<String> = [],
                             launchCounts: [String: Int]) -> [String] {
        let normalizedPins = Set(pinnedPaths.map(AppPathIdentity.standardized))
        let normalizedCounts = Dictionary(launchCounts.map { (AppPathIdentity.standardized($0.key), $0.value) },
                                          uniquingKeysWith: { first, _ in first })
        let indexed = paths.enumerated().map { (index: $0.offset, path: $0.element) }
        let pinned = indexed.filter { normalizedPins.contains(AppPathIdentity.standardized($0.path)) }
        let unpinned = indexed.filter { !normalizedPins.contains(AppPathIdentity.standardized($0.path)) }
            .sorted { lhs, rhs in
                let leftCount = normalizedCounts[AppPathIdentity.standardized(lhs.path), default: 0]
                let rightCount = normalizedCounts[AppPathIdentity.standardized(rhs.path), default: 0]
                if leftCount != rightCount { return leftCount > rightCount }
                return lhs.index < rhs.index
            }
        return (pinned + unpinned).map(\.path)
    }
}
