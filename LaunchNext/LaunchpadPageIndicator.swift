import SwiftUI

enum LaunchpadUIMetrics {
    static let overallScale: CGFloat = 1.05
}

enum PageControlMetrics {
    static let pageStep: CGFloat = 40 * LaunchpadUIMetrics.overallScale
    static let bubbleWidth: CGFloat = 36 * LaunchpadUIMetrics.overallScale
    static let bubbleHeight: CGFloat = 32 * LaunchpadUIMetrics.overallScale
    static let horizontalPadding: CGFloat = 3 * LaunchpadUIMetrics.overallScale
    static let buttonSize: CGFloat = 32 * LaunchpadUIMetrics.overallScale
    static let sideGap: CGFloat = 8 * LaunchpadUIMetrics.overallScale
    static let organizerWidth: CGFloat = 72 * LaunchpadUIMetrics.overallScale
    static let organizerHeight: CGFloat = 32 * LaunchpadUIMetrics.overallScale
    static let backgroundButtonWidth: CGFloat = 72 * LaunchpadUIMetrics.overallScale
    static let backgroundButtonHeight: CGFloat = 32 * LaunchpadUIMetrics.overallScale
    static let rowHeight: CGFloat = 36 * LaunchpadUIMetrics.overallScale

    private static func indicatorHalfWidth(pageCount: Int) -> CGFloat {
        CGFloat(max(1, pageCount)) * pageStep / 2 + horizontalPadding
    }

    static func addButtonOffset(pageCount: Int) -> CGFloat {
        -(indicatorHalfWidth(pageCount: pageCount) + sideGap + buttonSize / 2)
    }

    static func removeButtonOffset(pageCount: Int) -> CGFloat {
        addButtonOffset(pageCount: pageCount) - buttonSize - sideGap
    }

    static func organizeButtonOffset(pageCount: Int) -> CGFloat {
        indicatorHalfWidth(pageCount: pageCount) + sideGap + organizerWidth / 2
    }

    static func backgroundButtonOffset(pageCount: Int) -> CGFloat {
        organizeButtonOffset(pageCount: pageCount) + organizerWidth / 2 + sideGap + backgroundButtonWidth / 2
    }

    static func settingsButtonOffset(pageCount: Int) -> CGFloat {
        backgroundButtonOffset(pageCount: pageCount) + backgroundButtonWidth / 2 + sideGap + buttonSize / 2
    }
}

/// A draggable Liquid Glass page control with a cursor-following selection capsule.
struct LaunchpadPageIndicator: View {
    let pageCount: Int
    let currentPage: Int
    let isActive: Bool
    var backgroundStyle: BackgroundLabelContrast.Style? = nil
    let onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dragLocation: CGFloat?
    @State private var restingPage: Int?
    @State private var isDragging = false

    private var trackWidth: CGFloat { CGFloat(max(1, pageCount)) * PageControlMetrics.pageStep }
    private var bubbleX: CGFloat {
        guard let dragLocation else {
            let page = restingPage ?? currentPage
            return CGFloat(page) * PageControlMetrics.pageStep
                + (PageControlMetrics.pageStep - PageControlMetrics.bubbleWidth) / 2
        }
        return min(max(dragLocation - PageControlMetrics.bubbleWidth / 2, 0),
                   max(0, trackWidth - PageControlMetrics.bubbleWidth))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                ForEach(0..<max(0, pageCount), id: \.self) { index in
                    Button { select(index) } label: {
                        Color.clear
                            .frame(width: PageControlMetrics.pageStep, height: PageControlMetrics.bubbleHeight)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("第 \(index + 1) 页，共 \(pageCount) 页")
                    .accessibilityLabel(Text(verbatim: (index + 1).formatted()))
                    .accessibilityAddTraits(currentPage == index ? .isSelected : [])
                }
            }

            Capsule()
                .fill(Color.clear)
                .frame(width: PageControlMetrics.bubbleWidth, height: PageControlMetrics.bubbleHeight)
                .glassEffect(.regular, in: Capsule())
                .allowsHitTesting(false)
                .offset(x: bubbleX)
        }
        .frame(width: trackWidth, height: PageControlMetrics.bubbleHeight)
        .padding(.horizontal, PageControlMetrics.horizontalPadding)
        .padding(.vertical, 2)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Color.clear.glassEffect(.regular, in: Capsule())
            }
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    restingPage = nil
                    dragLocation = value.location.x
                    isDragging = true
                }
                .onEnded { value in
                    let target = Int((value.location.x / PageControlMetrics.pageStep).rounded(.down))
                    let destination = min(max(target, 0), max(0, pageCount - 1))
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.38, dampingFraction: 0.78)) {
                        dragLocation = nil
                        restingPage = destination
                        isDragging = false
                        onSelect(destination)
                    }
                    // Hold the destination bubble until the parent has published
                    // its page change, so it cannot briefly snap back to the old page.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard restingPage == destination else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { restingPage = nil }
                    }
                }
        )
        .animation(reduceMotion || isDragging ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: currentPage)
        .onChange(of: currentPage) { _, newPage in
            guard let restingPage else { return }
            if restingPage != newPage {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) {
                    self.restingPage = nil
                }
            }
        }
        .allowsHitTesting(isActive)
        .frame(height: PageControlMetrics.rowHeight)
    }

    private func select(_ index: Int) {
        restingPage = nil
        onSelect(min(max(index, 0), max(0, pageCount - 1)))
    }
}
