import CoreGraphics

/// Chooses the largest grid that fits the current Launchpad viewport while
/// keeping a consistent minimum cell pitch across displays.
struct AdaptiveLaunchpadGridMetrics: Equatable {
    static let minimumColumnPitch: CGFloat = 146
    static let minimumRowPitch: CGFloat = 108
    static let minimumColumns = 1
    static let maximumColumns = 64
    static let minimumRows = 1
    static let maximumRows = 32

    let columns: Int
    let rows: Int

    static func calculate(for availableSize: CGSize,
                          columnSpacing: CGFloat = 20,
                          rowSpacing: CGFloat = 14) -> Self {
        let width = availableSize.width.isFinite ? max(0, availableSize.width) : 0
        let height = availableSize.height.isFinite ? max(0, availableSize.height) : 0
        let columns = countThatFits(length: width,
                                    spacing: columnSpacing,
                                    pitch: minimumColumnPitch,
                                    range: minimumColumns...maximumColumns)
        let rows = countThatFits(length: height,
                                 spacing: rowSpacing,
                                 pitch: minimumRowPitch,
                                 range: minimumRows...maximumRows)
        return Self(columns: columns, rows: rows)
    }

    private static func countThatFits(length: CGFloat,
                                      spacing: CGFloat,
                                      pitch: CGFloat,
                                      range: ClosedRange<Int>) -> Int {
        let count = (length + spacing) / pitch
        if count <= CGFloat(range.lowerBound) { return range.lowerBound }
        if count >= CGFloat(range.upperBound) { return range.upperBound }
        return Int(floor(count))
    }
}
