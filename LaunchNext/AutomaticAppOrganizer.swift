import Foundation

/// App-level organizer categories derived from portable bundle metadata.
/// Kept separate from layout-preset definitions so each feature owns its model.
enum AutomaticAppCategory: String, CaseIterable, Hashable {
    case socialMedia
    case productivity
    case development
    case creative
    case artificialIntelligence
    case media
    case utilities
    case games

    /// A single detected game still belongs in the Games collection; other
    /// categories need multiple apps before an automatic folder is worthwhile.
    var minimumAppsForFolder: Int { self == .games ? 1 : 2 }

    var localizationKey: LocalizationKey {
        switch self {
        case .socialMedia: .autoFolderSocialMedia
        case .productivity: .autoFolderProductivity
        case .development: .autoFolderDevelopment
        case .creative: .autoFolderCreative
        case .artificialIntelligence: .autoFolderAI
        case .media: .autoFolderMedia
        case .utilities: .autoFolderUtilities
        case .games: .autoFolderGames
        }
    }

    static func classify(_ app: AppInfo) -> AutomaticAppCategory? {
        let bundle = bundle(for: app.url)
        let declaredCategory = (bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? "")
            .lowercased()
        let nameCandidates = [
            app.name,
            app.url.deletingPathExtension().lastPathComponent,
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "",
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        ]
        let documentTypes = bundle?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        let publisherMetadata = [
            bundle?.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleGetInfoString") as? String
        ].compactMap { $0 }
        guard let rawCategory = AutomaticAppClassification.classify(
            declaredCategory: declaredCategory,
            // Bundle-ID vendor segments often contain unrelated words (for
            // example, a vendor name containing "design"). User-facing names
            // and explicit bundle categories are stronger portable signals.
            searchFields: nameCandidates,
            documentTypes: documentTypes,
            publisherMetadata: publisherMetadata
        ) else { return nil }
        return AutomaticAppCategory(rawValue: rawCategory)
    }

    static func isAppleOwned(_ app: AppInfo) -> Bool {
        AutomaticAppClassification.isAppleOwned(
            bundleIdentifier: bundle(for: app.url)?.bundleIdentifier,
            appPath: app.url.path
        )
    }

    /// Some app-store wrappers keep the actual application bundle one level
    /// below the visible .app directory. Read that inner bundle generically so
    /// the classifier can use its normal category and display-name metadata.
    private static func bundle(for appURL: URL) -> Bundle? {
        if let bundle = Bundle(url: appURL), bundle.infoDictionary != nil {
            return bundle
        }

        let fileManager = FileManager.default
        let wrapperRoots = [
            appURL.appendingPathComponent("Wrapper", isDirectory: true),
            appURL.appendingPathComponent("Contents/Applications", isDirectory: true),
            appURL.appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)
        ]
        for root in wrapperRoots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            let nestedApps = children
                .filter { $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for nestedApp in nestedApps {
                if let bundle = Bundle(url: nestedApp), bundle.infoDictionary != nil {
                    return bundle
                }
            }
        }
        return nil
    }
}

struct AutomaticAppOrganizationResult {
    let appsOrganized: Int
    let foldersCreated: Int
    let foldersRenamed: Int
}

/// Stable destination identity shared by organizer planning and AppStore commit.
struct AutomaticAppFolderGroup: Hashable {
    let category: AutomaticAppCategory?
    let repeatedNameKey: String?
    let customTitle: String?
    let isAppleOwned: Bool

    init(category: AutomaticAppCategory, isAppleOwned: Bool) {
        self.category = category
        self.repeatedNameKey = nil
        self.customTitle = nil
        self.isAppleOwned = isAppleOwned
    }

    init(repeatedNameKey: String, customTitle: String, isAppleOwned: Bool) {
        self.category = nil
        self.repeatedNameKey = repeatedNameKey
        self.customTitle = customTitle
        self.isAppleOwned = isAppleOwned
    }

    var storageKey: String {
        if let repeatedNameKey {
            return isAppleOwned ? "title.\(repeatedNameKey).apple" : "title.\(repeatedNameKey)"
        }
        guard let category else { return "invalid" }
        return isAppleOwned ? "\(category.rawValue).apple" : category.rawValue
    }
}
