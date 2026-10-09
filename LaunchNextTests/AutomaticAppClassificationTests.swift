import XCTest

final class AutomaticAppClassificationTests: XCTestCase {
    func testApplePublisherNamespaceIsRecognizedWithoutAnAppAllowlist() {
        XCTAssertTrue(AutomaticAppClassification.isAppleOwned(
            bundleIdentifier: "com.apple.iWork.Pages",
            appPath: "/Applications/Pages.app"
        ))
        XCTAssertTrue(AutomaticAppClassification.isAppleOwned(
            bundleIdentifier: "com.example.builtin",
            appPath: "/System/Applications/Example.app"
        ))
        XCTAssertFalse(AutomaticAppClassification.isAppleOwned(
            bundleIdentifier: "com.example.vendor.product",
            appPath: "/Applications/Product.app"
        ))
    }

    func testRegisteredVideoTypesOverrideMisleadingDeveloperCategory() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.developer-tools",
            searchFields: ["哔哩哔哩"],
            documentTypes: [[
                "CFBundleTypeName": "Video File",
                "CFBundleTypeExtensions": ["mp4", "mov", "mkv", "m3u8", "mp3", "wav"]
            ]]
        )

        XCTAssertEqual(result, "media")
    }

    func testTencentVideoNameUsesTheGenericMediaCategory() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["腾讯视频"],
            documentTypes: []
        )

        XCTAssertEqual(result, "media")
    }

    func testSocialNetworkingBundleCategoryGetsItsOwnCategory() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.social-networking",
            searchFields: ["Instagram"],
            documentTypes: []
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testLineLikeSocialNetworkingMetadataUsesTheSharedSocialMediaCategory() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.social-networking",
            searchFields: ["LINE"],
            documentTypes: []
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testOpaqueDisplayNameWithTwitterAliasIsNotAutomaticallyClassified() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["X", "Twitter"],
            documentTypes: []
        )

        XCTAssertNil(result)
    }

    func testChatExportNameUsesUtilitiesInsteadOfSocialMedia() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["ExportWeChat"],
            documentTypes: []
        )

        XCTAssertEqual(result, "utilities")
    }

    func testNamedShortVideoAppPrefersSocialMediaOverVideo() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["短视频应用"],
            documentTypes: []
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testShortVideoDescriptorPrefersSocialMediaOverGenericVideo() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["Short Video"],
            documentTypes: []
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testGenericBluRayPlayerDescriptorDoesNotNeedBrandMetadata() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["A Blu-ray Player for Mac"],
            documentTypes: []
        )

        XCTAssertEqual(result, "media")
    }

    func testGenericHorrorGenreCanIdentifyAGameWithoutAnAppAllowlist() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["WORLD OF HORROR"],
            documentTypes: []
        )

        XCTAssertEqual(result, "games")
    }

    func testHorrorMediaPlayerIsNotMistakenForAGame() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["Horror Movie Player"],
            documentTypes: []
        )

        XCTAssertNil(result)
    }

    func testTelephoneAndMirroringTermsUseDifferentGenericCategories() {
        let phone = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["电话"],
            documentTypes: []
        )
        let mirroring = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["iPhone Mirroring"],
            documentTypes: []
        )

        XCTAssertEqual(phone, "socialMedia")
        XCTAssertEqual(mirroring, "utilities")
    }

    func testMessagesMetadataAndAttachmentTypesClassifyAsSocialMedia() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.social-networking",
            searchFields: ["Messages"],
            documentTypes: [
                ["CFBundleTypeName": "Image", "LSItemContentTypes": ["public.image"]],
                ["CFBundleTypeName": "Audiovisual content", "LSItemContentTypes": ["public.audiovisual-content"]],
                ["CFBundleTypeName": "Plain Text", "LSItemContentTypes": ["public.utf8-plain-text"]]
            ]
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testFaceTimeFunctionUsesTheSocialMediaGroup() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.social-networking",
            searchFields: ["FaceTime"],
            documentTypes: []
        )

        XCTAssertEqual(result, "socialMedia")
    }

    func testBusinessMeetingAppIsClassifiedAsProductivity() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.business",
            searchFields: ["TencentMeeting"],
            documentTypes: []
        )

        XCTAssertEqual(result, "productivity")
    }

    func testGenericFinanceAndStockAppNamesUseProductivity() {
        let stocks = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["Stocks"],
            documentTypes: []
        )
        let finance = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["Personal Finance Manager"],
            documentTypes: []
        )

        XCTAssertEqual(stocks, "productivity")
        XCTAssertEqual(finance, "productivity")
    }

    func testMediaSoundtrackDoesNotBecomeAGameBecauseItsTitleMentionsHorror() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["WORLD OF HORROR Soundtrack"],
            documentTypes: []
        )

        XCTAssertEqual(result, "media")
    }

    func testCreativeProjectDocumentOutweighsBroadVideoCategory() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.video",
            searchFields: ["DaVinci Resolve"],
            documentTypes: [
                ["CFBundleTypeName": "DaVinci Resolve Project File", "CFBundleTypeExtensions": ["drp"]],
                ["CFBundleTypeName": "DaVinci Resolve Timeline File", "CFBundleTypeExtensions": ["drt"]]
            ]
        )

        XCTAssertEqual(result, "creative")
    }

    func testArchiveUtilitiesAreNotMistakenForMediaHandlers() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.utilities",
            searchFields: ["Unzip - RAR ZIP 7Z Unarchiver"],
            documentTypes: [[
                "CFBundleTypeName": "Supported files",
                "CFBundleTypeExtensions": ["mp3", "mp4", "mov", "zip"]
            ]]
        )

        XCTAssertEqual(result, "utilities")
    }

    func testBrandOnlyNameWithoutCategoryMetadataStaysUncategorized() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["X"],
            documentTypes: []
        )

        XCTAssertNil(result)
    }

    func testUnknownAppWithoutUsefulEvidenceStaysUncategorized() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "",
            searchFields: ["Example Application"],
            documentTypes: []
        )

        XCTAssertNil(result)
    }

    func testPlaceholderFoldersCanBeNamedFromTheirContents() {
        XCTAssertTrue(AutomaticFolderNameInference.isPlaceholder("Untitled"))
        XCTAssertTrue(AutomaticFolderNameInference.isPlaceholder("未命名文件夹"))
        XCTAssertFalse(AutomaticFolderNameInference.isPlaceholder("Games"))

        let inferred = AutomaticFolderNameInference.suggestedName(
            appNames: ["App A", "App B", "App C"],
            categoryIdentifiers: ["games", "games", "utilities"],
            localizedCategoryNames: ["games": "Games", "utilities": "Utilities"],
            allAppsAppleOwned: false,
            appleLabel: "Apple"
        )

        XCTAssertEqual(inferred, "Games")
    }

    func testOnlyDuplicateGeneratedAppleFolderNamesCanBeReconciled() {
        let names = ["media": ["影音 · Apple", "Media · Apple"],
                     "productivity": ["办公 · Apple", "Productivity · Apple"]]

        XCTAssertEqual(
            AutomaticFolderNameInference.managedAppleCategoryIdentifier(
                for: "影音 · Apple",
                generatedNamesByCategory: names,
                managedAppleCategoryIdentifiers: ["media"]
            ),
            "media"
        )
        XCTAssertNil(
            AutomaticFolderNameInference.managedAppleCategoryIdentifier(
                for: "My Apple Apps",
                generatedNamesByCategory: names,
                managedAppleCategoryIdentifiers: ["media", "productivity"]
            )
        )
        XCTAssertNil(
            AutomaticFolderNameInference.managedAppleCategoryIdentifier(
                for: "影音 · Apple",
                generatedNamesByCategory: names,
                managedAppleCategoryIdentifiers: ["productivity"]
            )
        )
    }

    func testPlaceholderFolderNameUsesAppNamesWhenCategoryIsUnclear() {
        let inferred = AutomaticFolderNameInference.suggestedName(
            appNames: ["AppsAnywhere", "AppsAnywhere"],
            categoryIdentifiers: [],
            localizedCategoryNames: [:],
            allAppsAppleOwned: false,
            appleLabel: "Apple"
        )

        XCTAssertEqual(inferred, "AppsAnywhere")
        XCTAssertEqual(AutomaticFolderNameInference.normalizedKey("AppsAnywhere"),
                       AutomaticFolderNameInference.normalizedKey("apps-anywhere"))
    }

    func testStandaloneAIPublisherTokenIdentifiesGenericAssistantMetadata() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.productivity",
            searchFields: ["Kimi"],
            documentTypes: [],
            publisherMetadata: ["Copyright © 2026 Example AI. All rights reserved."]
        )

        XCTAssertEqual(result, "artificialIntelligence")
    }

    func testAIInsidePublisherNameDoesNotMatchStandaloneToken() {
        let result = AutomaticAppClassification.classify(
            declaredCategory: "public.app-category.productivity",
            searchFields: ["Example app"],
            documentTypes: [],
            publisherMetadata: ["Copyright © 2026 OpenAI. All rights reserved."]
        )

        XCTAssertEqual(result, "productivity")
    }
}
