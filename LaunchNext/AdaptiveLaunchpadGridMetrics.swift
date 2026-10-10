import CoreGraphics

/// Chooses the largest grid that fits the current viewport, scaling the
/// minimum cell pitch with the user's icon-size preference.
struct AdaptiveLaunchpadGridMetrics: Equatable {
    static let defaultIconScale: Double = 1.05
    static let iconScaleRange: ClosedRange<Double> = 0.75...1.65
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
                          rowSpacing: CGFloat = 14,
                          iconScale: Double = defaultIconScale) -> Self {
        let width = availableSize.width.isFinite ? max(0, availableSize.width) : 0
        let height = availableSize.height.isFinite ? max(0, availableSize.height) : 0
        let finiteScale = iconScale.isFinite ? iconScale : defaultIconScale
        let scaleFactor = CGFloat(max(0.5, finiteScale / defaultIconScale))
        let columns = countThatFits(length: width,
                                    spacing: columnSpacing,
                                    pitch: minimumColumnPitch * scaleFactor,
                                    range: minimumColumns...maximumColumns)
        let rows = countThatFits(length: height,
                                 spacing: rowSpacing,
                                 pitch: minimumRowPitch * scaleFactor,
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
