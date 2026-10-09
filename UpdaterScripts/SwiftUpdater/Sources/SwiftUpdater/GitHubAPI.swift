import Foundation

struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

struct ReleaseMetadata: Decodable {
    let tagName: String
    let htmlURL: URL?
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

enum GitHubClient {
    static let owner = "RoversX"
    static let repo = "LaunchNext"

    static func releaseAPIURL(tag: String?, repositoryOwner: String?, repositoryName: String?) -> URL? {
        let owner = repositoryOwner ?? Self.owner
        let repo = repositoryName ?? Self.repo
        guard isValidGitHubRepositoryComponent(owner), isValidGitHubRepositoryComponent(repo) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        if let tag, !tag.isEmpty {
            components.path = "/repos/\(owner)/\(repo)/releases/tags/\(tag)"
        } else {
            components.path = "/repos/\(owner)/\(repo)/releases/latest"
        }
        return components.url
    }

    static func latestRelease(tag overrideTag: String?,
                              token: String?,
                              repositoryOwner: String? = nil,
                              repositoryName: String? = nil) async throws -> ReleaseMetadata {
        guard (repositoryOwner == nil) == (repositoryName == nil),
              let url = releaseAPIURL(tag: overrideTag,
                                      repositoryOwner: repositoryOwner,
                                      repositoryName: repositoryName) else {
            throw UpdaterError.network("Invalid GitHub update repository")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdaterError.network("Invalid response")
        }
        guard http.statusCode == 200 else {
            throw UpdaterError.network("GitHub API returned status \(http.statusCode)")
        }
        return try JSONDecoder().decode(ReleaseMetadata.self, from: data)
    }
}

func isValidGitHubRepositoryComponent(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    return value.unicodeScalars.allSatisfy(allowed.contains)
}
