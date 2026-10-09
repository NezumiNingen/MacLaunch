import XCTest

final class UpdateRepositoryConfigurationTests: XCTestCase {
    func testEmptyOrPartialConfigurationDisablesUpdateRepository() {
        XCTAssertNil(UpdateRepositoryConfiguration(owner: nil, name: nil))
        XCTAssertNil(UpdateRepositoryConfiguration(owner: "my-account", name: nil))
        XCTAssertNil(UpdateRepositoryConfiguration(owner: nil, name: "my-launchnext"))
        XCTAssertNil(UpdateRepositoryConfiguration(owner: "  ", name: "my-launchnext"))
    }

    func testConfiguredRepositoryBuildsLatestAndTaggedReleaseURLs() throws {
        let repository = try XCTUnwrap(UpdateRepositoryConfiguration(owner: "my-account", name: "my-launchnext"))

        XCTAssertEqual(
            repository.latestReleaseURL()?.absoluteString,
            "https://api.github.com/repos/my-account/my-launchnext/releases/latest"
        )
        XCTAssertEqual(
            repository.latestReleaseURL(tag: "v2.5.0")?.absoluteString,
            "https://api.github.com/repos/my-account/my-launchnext/releases/tags/v2.5.0"
        )
    }

    func testRepositoryComponentsCannotInjectAPathOrQuery() {
        XCTAssertNil(UpdateRepositoryConfiguration(owner: "other/repo", name: "my-launchnext"))
        XCTAssertNil(UpdateRepositoryConfiguration(owner: "my-account", name: "repo?redirect=elsewhere"))
    }
}
