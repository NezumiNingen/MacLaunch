import Foundation

/// Portable organizer heuristics shared with the app and test targets.
/// Classification uses bundle metadata and multilingual function cues, with a
/// few global utility-name and social-platform aliases for weakly described apps.
enum AutomaticAppClassification {
    static func isAppleOwned(bundleIdentifier: String?, appPath: String) -> Bool {
        if bundleIdentifier?.lowercased().hasPrefix("com.apple.") == true {
            return true
        }

        // Some built-in apps have no TeamIdentifier in their system signature.
        // Their standard macOS bundle locations provide a portable fallback.
        let path = URL(fileURLWithPath: appPath).standardizedFileURL.path
        return path.hasPrefix("/System/Applications/")
            || path.hasPrefix("/System/Library/CoreServices/Applications/")
    }

    static func classify(declaredCategory: String,
                         searchFields: [String],
                         documentTypes: [[String: Any]],
                         publisherMetadata: [String] = []) -> String? {
        let category = normalizedToken(declaredCategory)
        let fields = searchFields.map(normalizedToken).filter { !$0.isEmpty }
        let publisherTokens = Set(publisherMetadata.flatMap {
            $0.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map(normalizedToken)
                .filter { !$0.isEmpty }
        })
        var scores: [String: Int] = [:]

        func add(_ category: String, _ points: Int) {
            scores[category, default: 0] += points
        }

        func hasAny(_ fields: [String], _ terms: [String]) -> Bool {
            let normalizedTerms = terms.map(normalizedToken).filter { !$0.isEmpty }
            return fields.map(normalizedToken).contains { field in
                normalizedTerms.contains(where: field.contains)
            }
        }

        func hasExact(_ fields: [String], _ terms: [String]) -> Bool {
            let normalizedTerms = Set(terms.map(normalizedToken).filter { !$0.isEmpty })
            return fields.contains(where: normalizedTerms.contains)
        }

        let mirroringCues = ["mirror", "mirroring", "screen mirroring", "display mirroring", "device mirroring",
                             "wireless display", "镜像", "屏幕镜像", "设备镜像", "投屏", "画面ミラーリング",
                             "スクリーンミラーリング", "화면 미러링", "미러링"]
        let socialInteractionCues = ["phone", "telephone", "mobile phone", "dialer", "telephony", "calling", "voip",
                                     "voice over ip", "face time", "facetime", "video call", "video calling", "voice call",
                                     "phone call", "messaging", "messenger", "message", "chat",
                                     "通讯", "通信", "聊天", "消息", "电话", "拨号", "通话", "電話", "電話会議",
                                     "ビデオ通話", "メッセージ", "채팅", "전화"]
        let creativeCues = ["photo", "photography", "camera", "image", "drawing", "illustration", "video editing",
                            "video editor", "photo editor", "image editor", "animation", "3d design", "photo booth",
                            "照片", "摄影", "相机", "图像", "绘图", "视频编辑", "视频剪辑", "后期制作",
                            "写真", "画像", "カメラ", "사진", "이미지"]
        let utilityCues = ["utilities", "utility", "system tool", "archive utility", "archive manager", "archiver",
                           "unzip", "unarchiver", "extractor", "compression tool", "zip utility", "mirror", "mirroring",
                           "screen mirroring", "device mirroring", "wireless display", "calculator", "clock", "password manager",
                           "passwords", "find my", "device finder", "weather", "maps", "navigation", "home automation",
                           "export", "data transfer", "backup utility", "chat backup", "message backup",
                           "smart home", "terminal", "system settings", "magnifier", "工具", "系统工具", "实用工具",
                           "镜像", "屏幕镜像", "设备镜像", "投屏", "导出", "数据迁移", "聊天记录备份", "消息备份",
                           "计算器", "时钟", "密码", "天气", "地图", "导航",
                           "ミラーリング", "ユーティリティ", "電卓", "天気", "地図", "미러링", "유틸리티", "계산기", "날씨"]
        let exactUtilityNames = ["clock", "home", "tips", "passwords", "weather", "calculator", "magnifier"]
        let aiCues = ["artificial intelligence", "machine learning", "language model", "large language model", "llm", "gpt",
                      "ai assistant", "ai tools", "generative ai", "人工智能", "大模型", "智能助手", "生成式ai"]
        let socialMediaCues = ["social", "social media", "social network", "social networking", "social platform",
                               "social app", "photo sharing", "video sharing", "short video", "short-form video",
                               "microblog", "microblogging", "sns", "社交媒体", "社交平台", "社交网络", "社交应用",
                               "短视频", "微博", "视频分享", "图片分享", "ソーシャルメディア", "ソーシャルネットワーク",
                               "소셜 미디어", "소셜 네트워크"]
        if hasAny(fields, mirroringCues) {
            add("utilities", 5)
        }
        let hasLanguageModelCue = hasAny(fields, ["gpt", "llm", "language model", "large language model",
                                                   "artificial intelligence", "ai assistant", "ai tools"])
        let hasDataTransferUtilityCue = hasAny(fields, ["export", "backup", "data transfer", "migration",
                                                        "导出", "备份", "数据迁移"])
        let socialInteractionWithoutChat = socialInteractionCues.filter { $0 != "chat" }
        if hasAny(fields, socialInteractionWithoutChat)
            || (hasAny(fields, ["chat"]) && !hasLanguageModelCue && !hasDataTransferUtilityCue) {
            add("socialMedia", 5)
        }
        if hasAny(fields, creativeCues) {
            add("creative", 5)
        }
        if hasAny(fields, utilityCues) {
            add("utilities", 5)
        }
        if hasExact(fields, exactUtilityNames) {
            add("utilities", 5)
        }
        // A standalone AI publisher token is useful when a product has a
        // generic display name and an otherwise broad productivity category.
        // Token matching avoids treating names such as "OpenAI" as "AI".
        if publisherTokens.contains("ai") {
            add("artificialIntelligence", 5)
        }
        if hasAny(fields, aiCues) {
            add("artificialIntelligence", 5)
        }
        if hasAny(fields, socialMediaCues) {
            add("socialMedia", 5)
        }

        // Bundle category declarations are useful but fallible, so they carry
        // less weight than a clear function in the app's name or metadata.
        if category.contains("socialnetworking") || category.contains("socialmedia") {
            add("socialMedia", 3)
        }
        if category.contains("developertools") { add("development", 3) }
        if ["productivity", "business", "education", "finance", "reference"].contains(where: category.contains) {
            add("productivity", 3)
        }
        if ["graphicsdesign", "photography"].contains(where: category.contains) { add("creative", 3) }
        if ["video", "music", "entertainment", "news", "books"].contains(where: category.contains) { add("media", 3) }
        if category.contains("utilities") { add("utilities", 3) }
        if category.contains("travel") { add("utilities", 3) }
        if category.contains("games") { add("games", 3) }

        // Genre words can identify games whose bundles omit Apple's category
        // key and whose names do not literally contain "game". Reduce this
        // evidence when the same app description also looks like a media app.
        let mediaTextCues = ["video", "audio", "music", "movie", "movies", "film", "films", "player",
                             "streaming", "podcast", "soundtrack", "sound track", "ost", "album",
                             "视频", "音频", "音乐", "电影", "影片", "播放器", "原声带", "配乐",
                             "播放", "映画", "ビデオ", "プレーヤー", "영화", "비디오", "플레이어"]
        let soundtrackCues = ["soundtrack", "sound track", "original score", "game soundtrack", "ost", "album",
                              "原声带", "原聲帶", "配乐", "配樂", "サウンドトラック", "사운드트랙"]
        let gameGenreCues = ["horror", "arcade", "role playing", "roleplaying", "rpg", "platformer",
                             "roguelike", "roguelite", "visual novel", "adventure game", "puzzle game",
                             "strategy game", "action game", "simulation game", "恐怖", "街机游戏", "角色扮演",
                             "视觉小说", "ホラー", "アーケードゲーム", "ロールプレイング", "공포", "아케이드 게임"]
        if hasAny(fields, soundtrackCues) {
            add("media", 5)
        } else if hasAny(fields, gameGenreCues) {
            add("games", hasAny(fields, mediaTextCues) ? 3 : 5)
        }

        // These are generic descriptors in several languages, not a list of
        // particular apps or bundle identifiers.
        let genericTerms: [(String, [String])] = [
            ("productivity", ["productivity", "office", "document", "spreadsheet", "presentation", "calendar", "notes",
                               "conference", "meeting", "finance", "financial", "banking", "bank", "investment",
                               "investing", "stock market", "stocks", "budget", "accounting", "办公", "文档", "表格",
                               "演示", "日历", "笔记", "会议", "金融", "银行", "理财", "股票", "投资", "记账",
                               "オフィス", "문서"]),
            ("development", ["developer", "development", "programming", "code editor", "source code", "terminal", "ide",
                              "开发", "编程", "代码", "终端", "開発", "プログラミング", "개발"]),
            ("creative", ["creative", "design", "graphics", "photo editor", "image editor", "drawing", "illustration", "3d",
                           "创意", "设计", "图像", "照片", "绘图", "創作", "デザイン", "画像", "디자인"]),
            ("artificialIntelligence", ["artificial intelligence", "machine learning", "language model", "large language model",
                                         "llm", "ai assistant", "ai tools", "人工智能", "大模型", "智能助手", "生成式ai"]),
            ("media", ["media", "video", "audio", "music", "movie", "player", "streaming", "blu-ray", "bluray", "disc player",
                        "podcast", "news", "newspaper", "magazine", "影音", "视频", "音频", "音乐", "电影", "新闻",
                        "播放", "播放器", "蓝光", "媒体",
                        "ブルーレイ", "動画", "音楽", "プレーヤー", "미디어", "비디오", "음악", "플레이어"]),
            ("utilities", ["utilities", "utility", "system tool", "archive utility", "compression tool",
                            "mirror", "mirroring", "screen mirroring", "device mirroring", "wireless display",
                            "工具", "系统工具", "实用工具", "镜像", "屏幕镜像", "设备镜像", "投屏",
                            "圧縮", "ミラーリング", "ユーティリティ", "미러링", "유틸리티"]),
            ("games", ["game", "games", "游戏", "ゲーム", "게임"])
        ]
        for (category, terms) in genericTerms where hasAny(fields, terms) {
            add(category, 3)
        }
        if hasAny(fields, ["chat"]) && !hasLanguageModelCue && !hasDataTransferUtilityCue {
            add("socialMedia", 3)
        }

        // A range of registered media extensions or media UTIs strongly
        // indicates a media app, even when the bundle's category is wrong.
        let mediaExtensions: Set<String> = [
            "3gp", "asf", "avi", "f4v", "flv", "hevc", "m2ts", "m2v", "m4v", "mkv", "mov", "mp4",
            "mpeg", "mpg", "mts", "mxf", "ogv", "rm", "rmvb", "swf", "ts", "vob", "webm", "wmv",
            "wtv", "m3u8", "mp3", "m4a", "aac", "wav", "flac", "ogg", "aiff", "opus"
        ]
        var registeredMediaExtensions = Set<String>()
        var declaresMediaContent = false
        var hasMediaTypeName = false
        for documentType in documentTypes {
            let typeName = documentType["CFBundleTypeName"] as? String ?? ""
            let contentTypes = documentType["LSItemContentTypes"] as? [String] ?? []
            let extensions = Set((documentType["CFBundleTypeExtensions"] as? [String] ?? []).map(normalizedToken))
            registeredMediaExtensions.formUnion(extensions.intersection(mediaExtensions))
            declaresMediaContent = declaresMediaContent || contentTypes.contains { type in
                let value = normalizedToken(type)
                return value.contains("movie") || value.contains("video")
                    || (value.contains("audio") && !value.contains("audiovisual")) || value.contains("mpeg4")
            }
            let normalizedTypeName = normalizedToken(typeName)
            if !normalizedTypeName.contains("audiovisual"),
               hasAny([typeName] + contentTypes, ["media", "video", "audio", "movie", "player", "streaming",
                                                   "影音", "视频", "音频", "电影", "蓝光", "媒体"]) {
                hasMediaTypeName = true
            }
        }
        let hasUtilityIntent = hasAny(fields, utilityCues) || category.contains("utilities")
        if registeredMediaExtensions.count >= 3 || declaresMediaContent {
            add("media", hasUtilityIntent ? 2 : 5)
        } else if !registeredMediaExtensions.isEmpty {
            add("media", 2)
        }
        if hasMediaTypeName {
            add("media", 2)
        }

        let creativeDocumentCues = ["project file", "timeline", "editing project", "template bundle", "design document",
                                    "animation project", "creative project", "项目文件", "时间线", "剪辑工程", "模板包"]
        if documentTypes.contains(where: { documentType in
            let typeName = documentType["CFBundleTypeName"] as? String ?? ""
            let contentTypes = documentType["LSItemContentTypes"] as? [String] ?? []
            return hasAny([typeName] + contentTypes, creativeDocumentCues)
        }) {
            add("creative", 5)
        }

        guard let winner = scores.max(by: { $0.value < $1.value }), winner.value >= 3 else { return nil }
        let runnerUp = scores.filter { $0.key != winner.key }.map(\.value).max() ?? 0
        guard winner.value - runnerUp >= 2 else { return nil }
        return winner.key
    }

    nonisolated private static func normalizedToken(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })).lowercased()
    }
}

/// Pure naming heuristics for folders that still carry a generic placeholder.
/// App metadata and localization are supplied by the app-level organizer.
enum AutomaticFolderNameInference {
    static func normalizedKey(_ value: String) -> String {
        token(value)
    }

    static func isPlaceholder(_ name: String) -> Bool {
        let normalized = token(name)
        let placeholders = [
            "untitled", "untitledfolder", "folder", "newfolder",
            "未命名", "未命名文件夹", "新建文件夹", "新文件夹", "文件夹", "無題", "名称未設定",
            "sans titre", "dossier sans titre", "nouveau dossier", "ohne titel", "neuer ordner",
            "sin titulo", "carpeta sin titulo", "nueva carpeta", "senza titolo", "nuova cartella",
            "フォルダ", "新規フォルダ", "제목 없음", "새 폴더", "새로운 폴더"
        ].map(token)
        return placeholders.contains(normalized)
    }

    static func managedAppleCategoryIdentifier(
        for folderName: String,
        generatedNamesByCategory: [String: [String]],
        managedAppleCategoryIdentifiers: Set<String>
    ) -> String? {
        let normalizedName = token(folderName)
        guard !normalizedName.isEmpty else { return nil }
        for identifier in generatedNamesByCategory.keys.sorted() {
            guard managedAppleCategoryIdentifiers.contains(identifier) else { continue }
            for generatedName in generatedNamesByCategory[identifier] ?? [] where token(generatedName) == normalizedName {
                return identifier
            }
        }
        return nil
    }

    static func suggestedName(appNames: [String],
                              categoryIdentifiers: [String],
                              localizedCategoryNames: [String: String],
                              allAppsAppleOwned: Bool,
                              appleLabel: String) -> String? {
        let categoryCounts = categoryIdentifiers.reduce(into: [String: Int]()) { counts, identifier in
            counts[identifier, default: 0] += 1
        }
        let rankedCategories = categoryCounts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }

        if let winner = rankedCategories.first {
            let runnerUpCount = rankedCategories.dropFirst().first?.value ?? 0
            let hasClearMajority = winner.value >= 2
                && winner.value > runnerUpCount
                && winner.value * 2 >= categoryIdentifiers.count
            if hasClearMajority, let categoryName = localizedCategoryNames[winner.key], !categoryName.isEmpty {
                if allAppsAppleOwned, !appleLabel.isEmpty {
                    return "\(categoryName) · \(appleLabel)"
                }
                return categoryName
            }
        }

        var uniqueNames: [String] = []
        var seenNames = Set<String>()
        for rawName in appNames {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = token(name)
            guard !normalized.isEmpty,
                  normalized != "unknownapp",
                  seenNames.insert(normalized).inserted else { continue }
            uniqueNames.append(name)
        }

        guard let first = uniqueNames.first else { return nil }
        guard uniqueNames.count > 1 else { return first }
        let second = uniqueNames[1]
        return uniqueNames.count > 2 ? "\(first) + \(second) + …" : "\(first) + \(second)"
    }

    nonisolated private static func token(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })).lowercased()
    }
}
