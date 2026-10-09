import XCTest

final class AppUsageHistoryTests: XCTestCase {
    func testAppPathIdentityRejectsRepeatedAndNormalizedDuplicatePaths() {
        var claimed = Set<String>()

        XCTAssertTrue(AppPathIdentity.claim("/Applications/X.app", in: &claimed))
        XCTAssertFalse(AppPathIdentity.claim("/Applications/./X.app", in: &claimed))
        XCTAssertFalse(AppPathIdentity.claim("", in: &claimed))
    }

    func testFolderItemsRankByLaunchCountAndKeepStableTies() {
        let first = "/Applications/First.app"
        let second = "/Applications/Second.app"
        let third = "/Applications/Third.app"
        let fourth = "/Applications/Fourth.app"

        let result = AppUsageHistory.orderedPaths(
            [first, second, third, fourth],
            launchCounts: [first: 3, second: 8, third: 3]
        )

        XCTAssertEqual(result, [second, first, third, fourth])
    }

    func testPinnedAppsStayAheadOfUsageRankedApps() {
        let first = "/Applications/First.app"
        let second = "/Applications/Second.app"
        let third = "/Applications/Third.app"

        let result = AppUsageHistory.orderedPaths(
            [first, second, third],
            pinnedPaths: [first],
            launchCounts: [second: 30, third: 5]
        )

        XCTAssertEqual(result, [first, second, third])
    }

    func testLaunchCountsAreStoredInTheSelectedLocalDefaultsSuite() throws {
        let suiteName = "AppUsageHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppUsageHistory.recordLaunch(path: "/Applications/Example.app", defaults: defaults))
        XCTAssertTrue(AppUsageHistory.recordLaunch(path: "/Applications/Example.app", defaults: defaults))

        let counts = try XCTUnwrap(defaults.dictionary(forKey: AppUsageHistory.storageKey) as? [String: Int])
        XCTAssertEqual(counts["/Applications/Example.app"], 2)
    }
}
