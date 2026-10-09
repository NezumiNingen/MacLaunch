import Foundation

/// The update endpoint belongs to the build, not to a particular Mac.
/// It is configured through build settings so the same app works across Macs.
struct UpdateRepositoryConfiguration: Equatable {
    static let ownerInfoKey = "LaunchNextUpdateRepositoryOwner"
    static let nameInfoKey = "LaunchNextUpdateRepositoryName"

    let owner: String
    let name: String

    init?(owner: String?, name: String?) {
        guard let owner = Self.normalizedComponent(owner),
              let name = Self.normalizedComponent(name) else { return nil }
        self.owner = owner
        self.name = name
    }

    static var current: Self? {
        Self(owner: Bundle.main.object(forInfoDictionaryKey: ownerInfoKey) as? String,
             name: Bundle.main.object(forInfoDictionaryKey: nameInfoKey) as? String)
    }

    func latestReleaseURL(tag: String? = nil) -> URL? {
        let endpoint = tag.map { "releases/tags/\($0)" } ?? "releases/latest"
        return URL(string: "https://api.github.com/repos/\(owner)/\(name)/\(endpoint)")
    }

    private static func normalizedComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0)
              }) else { return nil }
        return trimmed
    }
}
