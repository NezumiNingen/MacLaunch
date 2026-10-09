import XCTest
import CoreGraphics

final class AdaptiveLaunchpadGridMetricsTests: XCTestCase {
    func testGridGrowsWithAvailableViewport() {
        let ordinary = AdaptiveLaunchpadGridMetrics.calculate(for: CGSize(width: 1512, height: 650))
        let larger = AdaptiveLaunchpadGridMetrics.calculate(for: CGSize(width: 2560, height: 1400))

        XCTAssertEqual(ordinary, AdaptiveLaunchpadGridMetrics(columns: 10, rows: 6))
        XCTAssertGreaterThan(larger.columns, ordinary.columns)
        XCTAssertGreaterThan(larger.rows, ordinary.rows)
    }

    func testSmallAndVeryLargeViewportsStayWithinSafeBounds() {
        let small = AdaptiveLaunchpadGridMetrics.calculate(for: CGSize(width: 100, height: 50))
        let huge = AdaptiveLaunchpadGridMetrics.calculate(for: CGSize(width: 20_000, height: 20_000))

        XCTAssertEqual(small, AdaptiveLaunchpadGridMetrics(columns: 1, rows: 1))
        XCTAssertEqual(huge, AdaptiveLaunchpadGridMetrics(columns: 64, rows: 32))
    }

    func testNonFiniteViewportDimensionsUseMinimumGrid() {
        let metrics = AdaptiveLaunchpadGridMetrics.calculate(for: CGSize(width: CGFloat.infinity, height: CGFloat.nan))

        XCTAssertEqual(metrics, AdaptiveLaunchpadGridMetrics(columns: 1, rows: 1))
    }
}
