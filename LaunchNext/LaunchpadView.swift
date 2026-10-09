import SwiftUI
import Combine
import AppKit
import CoreVideo
import UniformTypeIdentifiers

private struct PressTrackingPlainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? .linear(duration: 0.0001) : LNAnimations.springFast,
                       value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChanged(isPressed)
            }
    }
}

private struct TapGuardPlainButtonStyle: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChanged(isPressed)
            }
    }
}

private struct PageControlCircleButton: View {
    let symbol: String
    let title: String
    let isEnabled: Bool
    let onPressChanged: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Circle().fill(Color.clear).glassEffect(.regular, in: Circle())
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressTrackingPlainButtonStyle(onPressChanged: onPressChanged))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .help(title)
        .accessibilityLabel(Text(title))
    }
}

private struct WindowFrameReportingModifier: ViewModifier {
    let onFrameChange: (CGRect) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { report(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in report(frame) }
                    .allowsHitTesting(false)
            }
        }
    }

    private func report(_ frame: CGRect) {
        let callback = onFrameChange
        DispatchQueue.main.async { callback(frame) }
    }
}

private struct SettingsButtonAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// A single drop falls onto the glass just above the settings control. The
/// popup itself is revealed by an irregular ink front that spreads from the
/// point where the drop meets the panel.
private struct SettingsInkDrop: View {
    let progress: CGFloat

    private var visibility: CGFloat {
        let appear = smoothStep(progress / 0.045)
        let disappear = 1 - smoothStep((progress - 0.39) / 0.17)
        return appear * disappear
    }

    private var fall: CGFloat { smoothStep(progress / 0.30) }

    var body: some View {
        ZStack {
            InkDropShape()
                .fill(LinearGradient(
                    colors: [Color(red: 0.49, green: 0.91, blue: 1),
                             Color(red: 0.13, green: 0.62, blue: 0.91),
                             Color(red: 0.16, green: 0.30, blue: 0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .cyan.opacity(0.42), radius: 8, y: 2)
            Ellipse()
                .fill(.white.opacity(0.76))
                .frame(width: 3.2, height: 6)
                .offset(x: -2, y: -3)
                .blur(radius: 0.35)
        }
        .frame(width: 18, height: 25)
        .scaleEffect(0.68 + 0.32 * visibility)
        .opacity(Double(visibility))
        .offset(y: -22 + 22 * fall)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private struct InkDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX + 1, y: rect.minY + h * 0.22),
                      control2: CGPoint(x: rect.maxX + 1, y: rect.minY + h * 0.80))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX - 1, y: rect.minY + h * 0.80),
                      control2: CGPoint(x: rect.minX - 1, y: rect.minY + h * 0.22))
        path.closeSubpath()
        return path
    }
}

/// Organic radial mask used to uncover the settings panel as if ink were
/// spreading from the drop's landing point. The contour is drawn in SwiftUI,
/// so it works without a Metal shader or a machine-specific GPU dependency.
private struct InkRevealShape: Shape {
    var progress: CGFloat
    var center: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let origin = CGPoint(x: rect.width * center.x, y: rect.height * center.y)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let farthest = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 0
        let t = smoothStep(progress)
        let radius = 5 + (farthest + 28 - 5) * t
        let texture = 1 - smoothStep((progress - 0.70) / 0.30)
        let amplitude = min(13, farthest * 0.035) * texture
        let pointCount = 240
        var points: [CGPoint] = []
        points.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let angle = CGFloat(index) * 2 * .pi / CGFloat(pointCount)
            let broad = 0.28 * sin(3 * angle + 0.35)
                + 0.18 * sin(5 * angle - 0.8)
            let ripples = 0.26 * sin(9 * angle + progress * 8.0)
                + 0.16 * sin(15 * angle - progress * 13.0)
                + 0.10 * sin(23 * angle + 1.7)
            let distance = max(1, radius + amplitude * (broad + ripples))
            points.append(CGPoint(x: origin.x + cos(angle) * distance,
                                  y: origin.y + sin(angle) * distance))
        }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

private struct LiquidSettingsPopup: View {
    @ObservedObject var appStore: AppStore
    let progress: CGFloat
    let buttonFrameInWindow: CGRect
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rootFrame = proxy.frame(in: .global)
            let anchor = settingsAnchor(in: rootFrame, size: size)
            let scale = LaunchpadUIMetrics.overallScale
            let panelWidth = min(820 * scale, max(360, size.width - 40))
            let panelHeight = min(640 * scale, max(320, size.height - 40))
            let center = panelCenter(anchor: anchor, size: size,
                                     panelWidth: panelWidth, panelHeight: panelHeight)
            let popupAnchor = UnitPoint(
                x: min(max((anchor.x - (center.x - panelWidth / 2)) / panelWidth, 0), 1),
                y: min(max((anchor.y - (center.y - panelHeight / 2)) / panelHeight, 0), 1)
            )
            let clampedProgress = min(max(progress, 0), 1)
            let cornerRadius = 28 * scale

            ZStack {
                Button {
                    guard clampedProgress > 0.92 else { return }
                    onDismiss()
                } label: {
                    Color.black.opacity(0.14 * Double(smoothStep(min(max((clampedProgress - 0.66) / 0.34, 0), 1))))
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)

                popupPanel(width: panelWidth, height: panelHeight, radius: cornerRadius,
                           progress: clampedProgress,
                           anchor: popupAnchor)
                    .position(center)

                SettingsInkDrop(progress: clampedProgress)
                    .position(x: anchor.x, y: anchor.y - 24)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .opacity(clampedProgress == 0 ? 0 : 1)
            .allowsHitTesting(clampedProgress > 0.03)
        }
        .ignoresSafeArea()
    }

    private func popupPanel(width: CGFloat, height: CGFloat, radius: CGFloat,
                            progress: CGFloat,
                            anchor: UnitPoint) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 30, y: 14)

            SettingsView(appStore: appStore)
                .frame(width: width, height: height)
                .opacity(contentOpacity(for: progress))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .mask {
            InkRevealShape(
                progress: min(max((progress - 0.30) / 0.60, 0), 1),
                center: CGPoint(x: anchor.x, y: anchor.y)
            )
            .fill(.white)
            .frame(width: width, height: height)
            .blur(radius: 3.5)
        }
        .overlay {
            InkRevealShape(
                progress: min(max((progress - 0.30) / 0.60, 0), 1),
                center: CGPoint(x: anchor.x, y: anchor.y)
            )
            .stroke(
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.13, blue: 0.25).opacity(0.78),
                             Color(red: 0.20, green: 0.72, blue: 0.91).opacity(0.78),
                             Color.white.opacity(0.48),
                             Color(red: 0.07, green: 0.29, blue: 0.56).opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .opacity(0.68 * (1 - min(max((progress - 0.82) / 0.18, 0), 1)))
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(Rectangle())
        .allowsHitTesting(progress > 0.92)
        .accessibilityAddTraits(.isModal)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func contentOpacity(for progress: CGFloat) -> Double {
        Double(min(max((progress - 0.70) / 0.27, 0), 1))
    }

    private func settingsAnchor(in rootFrame: CGRect, size: CGSize) -> CGPoint {
        guard !buttonFrameInWindow.isEmpty else {
            return CGPoint(x: size.width * 0.645,
                           y: size.height - 48 * LaunchpadUIMetrics.overallScale)
        }
        return CGPoint(x: buttonFrameInWindow.midX - rootFrame.minX,
                       y: buttonFrameInWindow.midY - rootFrame.minY)
    }

    private func panelCenter(anchor: CGPoint, size: CGSize,
                             panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        let horizontalInset = min(panelWidth / 2 + 20, size.width / 2)
        let verticalInset = min(panelHeight / 2 + 20, size.height / 2)
        let x = min(max(anchor.x, horizontalInset), size.width - horizontalInset)
        let preferredY = anchor.y - panelHeight / 2 - 18
        let y = min(max(preferredY, verticalInset), size.height - verticalInset)
        return CGPoint(x: x, y: y)
    }
}

private extension View {
    func reportWindowFrame(_ onChange: @escaping (CGRect) -> Void) -> some View {
        modifier(WindowFrameReportingModifier(onFrameChange: onChange))
    }
}

// MARK: - LaunchpadItem extension
extension LaunchpadItem {
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

// MARK: - 简化的翻页管理器
private class PageFlipManager: ObservableObject {
    @Published var isCooldown: Bool = false
    private var lastFlipTime: Date?
    var autoFlipInterval: TimeInterval = 0.8
    
    func canFlip() -> Bool {
        guard !isCooldown else { return false }
        guard let lastTime = lastFlipTime else { return true }
        return Date().timeIntervalSince(lastTime) >= autoFlipInterval
    }
    
    func recordFlip() {
        lastFlipTime = Date()
        isCooldown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + autoFlipInterval) {
            self.isCooldown = false
        }
    }
}

// Outlives the tile that started a Legacy drag, which can disappear during reordering.
private final class LegacyItemDragSession {
    weak var window: NSWindow?
    var eventMonitor: Any?
    var lastGestureUpdate = ProcessInfo.processInfo.systemUptime
    var usesMouseMonitor = false
    var isEnding = false

    init(window: NSWindow?) {
        self.window = window
    }

    func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}

private final class FPSMonitor {
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: Double = 0
    private let callback: (Double, Double) -> Void

    init?(callback: @escaping (Double, Double) -> Void) {
        self.callback = callback
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else { return nil }
        displayLink = link
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(link, { _, inNow, _, _, _, userInfo in
            guard let userInfo else { return kCVReturnSuccess }
            let monitor = Unmanaged<FPSMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.step(timestamp: inNow.pointee)
            return kCVReturnSuccess
        }, userInfo)
        CVDisplayLinkStart(link)
    }

    private func step(timestamp: CVTimeStamp) {
        guard timestamp.videoTimeScale != 0 else { return }
        let current = Double(timestamp.videoTime) / Double(timestamp.videoTimeScale)
        guard lastTimestamp != 0 else {
            lastTimestamp = current
            return
        }
        let delta = current - lastTimestamp
        lastTimestamp = current
        guard delta > 0 else { return }
        callback(1.0 / delta, delta)
    }

    func invalidate() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    deinit {
        invalidate()
    }
}

private extension View {
    @ViewBuilder
    func launchpadBackgroundStyle(_ style: AppStore.BackgroundStyle,
                                  cornerRadius: CGFloat,
                                  forcedColor: Color? = nil,
                                  maskColor: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let forcedColor {
            self.background(forcedColor, in: shape)
        } else {
            switch style {
            case .glass:
                let base = self.liquidGlass(in: shape)
                if let maskColor {
                    base.background(maskColor, in: shape)
                } else {
                    base
                }
            case .blur:
                let base = self.background(.ultraThinMaterial, in: shape)
                if let maskColor {
                    base.background(maskColor, in: shape)
                } else {
                    base
                }
            case .unfiltered:
                if let maskColor {
                    self.background(maskColor, in: shape)
                } else {
                    self
                }
            }
        }
    }
}

struct LaunchpadView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var searchEngine: LaunchpadSearchEngine
    @StateObject private var backgroundImageController = BackgroundImageController()
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyMonitor: Any?
    @State private var windowObserver: NSObjectProtocol?
    @State private var windowHiddenObserver: NSObjectProtocol?
    @State private var draggingItem: LaunchpadItem?
    @State private var legacyItemDragSession: LegacyItemDragSession?
    @State private var displayedGridRefreshID: UUID
    @State private var dragPreviewPosition: CGPoint = .zero
    @State private var dragPreviewScale: CGFloat = 1.2
    @State private var pendingDropIndex: Int? = nil
    @StateObject private var pageFlipManager = PageFlipManager()
    @State private var folderHoverCandidateIndex: Int? = nil
    @State private var folderHoverBeganAt: Date? = nil
    @State private var folderAppToReveal: String? = nil
    @State private var selectedIndex: Int? = nil
    @State private var isKeyboardNavigationActive: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var reorderNamespace
    @State private var handoffEventMonitor: Any? = nil
    @State private var globalMouseUpMonitor: Any? = nil
    @State private var gridOriginInWindow: CGPoint = .zero
    @State private var currentContainerSize: CGSize = .zero
    @State private var currentColumnWidth: CGFloat = 0
    @State private var currentAppHeight: CGFloat = 0
    @State private var currentIconSize: CGFloat = 0
    @State private var headerTotalHeight: CGFloat = 0
    @State private var headerFrameInWindow: CGRect = .zero
    @State private var favoritesFrameInWindow: CGRect = .zero
    @State private var pageIndicatorFrameInWindow: CGRect = .zero
    @State private var addPageButtonFrameInWindow: CGRect = .zero
    @State private var removePageButtonFrameInWindow: CGRect = .zero
    @State private var autoOrganizeButtonFrameInWindow: CGRect = .zero
    @State private var backgroundButtonFrameInWindow: CGRect = .zero
    @State private var settingsButtonFrameInWindow: CGRect = .zero
    @State private var showBackgroundOptions = false
    @State private var settingsPopupIsMounted = false
    @State private var settingsPopupProgress: CGFloat = 0
    @State private var settingsPopupDismissID = UUID()
    @State private var pageControlButtonIsPressed = false
    @State private var pageControlButtonPressID = UUID()
    @State private var autoOrganizationFeedback: String?
    @State private var autoOrganizationFeedbackID = UUID()
    
    // 性能优化：使用静态缓存避免状态修改问题
    private static var geometryCache: [String: CGPoint] = [:]
    private static var lastGeometryUpdate: Date = Date.distantPast
    private let geometryCacheTimeout: TimeInterval = 0.1 // 100ms缓存超时
    
    // 性能监控
    @State private var performanceMetrics: [String: TimeInterval] = [:]
    private let enablePerformanceMonitoring = false // 设置为true启用性能监控
    @State private var isHandoffDragging: Bool = false
    private struct ScrollState {
        var isUserSwiping: Bool = false
        var accumulatedX: CGFloat = 0
        var wheelAccumulated: CGFloat = 0
        var wheelLastDirection: Int = 0
        var wheelLastFlipAt: Date? = nil
        var followOffset: CGFloat = 0
        var followLastUpdateAt: TimeInterval = 0
        var followLastOffset: CGFloat = 0
    }

    @State private var scrollState = ScrollState()
    private let wheelFlipCooldown: TimeInterval = 0.15
    @State private var dragPointerOffset: CGPoint = .zero
    @State private var blankDragStartPoint: CGPoint? = nil
    @State private var blankDragShouldIgnore: Bool = false
    @State private var blankDragConsumed: Bool = false
    @State private var fpsMonitor: FPSMonitor?
    @State private var fpsValue: Double = 0
    @State private var frameTimeMilliseconds: Double = 0
    @State private var isWindowVisible: Bool = false

    init(appStore: AppStore) {
        _appStore = ObservedObject(wrappedValue: appStore)
        _searchEngine = ObservedObject(wrappedValue: appStore.searchEngine)
        _displayedGridRefreshID = State(initialValue: appStore.gridRefreshTrigger)
    }

    @StateObject private var folderPresentation = CAFolderPresentationController()

    private var isFolderOpen: Bool { appStore.openFolder != nil }
    private var currentScreenID: String? {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        return screen.map { AppStore.screenIdentifier(for: $0) }
    }
    
    private var config: GridConfig {
        GridConfig(isFullscreen: appStore.isFullscreenMode,
                   columns: appStore.gridColumnsPerPage,
                   rows: appStore.gridRowsPerPage,
                   columnSpacing: CGFloat(appStore.iconColumnSpacing),
                   rowSpacing: CGFloat(appStore.iconRowSpacing))
    }

    private var backdropOpacity: Double {
        guard appStore.isFullscreenMode, effectiveBackgroundStyle != .unfiltered else { return 0.0 }
        return colorScheme == .dark ? 0.30 : 0.35
    }

    var filteredItems: [LaunchpadItem] {
        searchEngine.filter(items: appStore.items,
                            query: appStore.searchQuery,
                            fuzzyEnabled: appStore.fuzzySearchEnabled)
    }
    
    var pages: [[LaunchpadItem]] {
        let items = draggingItem != nil ? visualItems : filteredItems
        return makePages(from: items)
    }
    
    private var currentItems: [LaunchpadItem] {
        draggingItem != nil ? visualItems : filteredItems
    }
    
    private var visualItems: [LaunchpadItem] {
        guard let dragging = draggingItem, let pending = pendingDropIndex else { return filteredItems }
        let itemsPerPage = config.itemsPerPage
        var pageSlices: [[LaunchpadItem]] = makePages(from: filteredItems)

        let sourcePage = pageSlices.firstIndex { $0.contains(dragging) }
        let sourceIndexInPage = sourcePage.flatMap { pageSlices[$0].firstIndex(of: dragging) }
        let targetPage = max(0, pending / itemsPerPage)
        let localIndexDesired = pending % itemsPerPage

        if let sPage = sourcePage, sPage == targetPage, let sIdx = sourceIndexInPage {
            pageSlices[sPage].remove(at: sIdx)
        }

        while pageSlices.count <= targetPage { pageSlices.append([]) }
        let localIndex = max(0, min(localIndexDesired, pageSlices[targetPage].count))
        pageSlices[targetPage].insert(dragging, at: localIndex)

        var p = targetPage
        while p < pageSlices.count {
            if pageSlices[p].count > itemsPerPage {
                let spilled = pageSlices[p].removeLast()
                if p + 1 >= pageSlices.count { pageSlices.append([]) }
                pageSlices[p + 1].insert(spilled, at: 0)
                p += 1
            } else {
                p += 1
            }
        }

        var transformed = pageSlices
        for pageIndex in transformed.indices {
            for itemIndex in transformed[pageIndex].indices {
                if transformed[pageIndex][itemIndex] == dragging {
                    let placeholderToken = "dragging-placeholder-\(dragging.id)-\(pageIndex)-\(itemIndex)"
                    transformed[pageIndex][itemIndex] = .empty(placeholderToken)
                }
            }
        }

        return transformed.flatMap { $0 }
    }

    private func makePages(from items: [LaunchpadItem]) -> [[LaunchpadItem]] {
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: config.itemsPerPage).map { start in
            let end = min(start + config.itemsPerPage, items.count)
            return Array(items[start..<end])
        }
    }
    
    var body: some View {
        launchpadEventBoundView
         .task(id: appStore.layoutRevealRequest?.id) {
             guard let request = appStore.layoutRevealRequest else { return }
             // Search observers must see the pending request before navigation
             // completes; otherwise they can reset the destination selection.
             await withCheckedContinuation { continuation in
                 DispatchQueue.main.async { continuation.resume() }
             }
             await revealAppInLayout(request)
         }
         .onChange(of: appStore.searchText) { _, text in
             if !text.isEmpty {
                 appStore.layoutRevealRequest = nil
                 cancelLegacyItemDrag()
             }
         }
         .onChange(of: appStore.isSetting) { _, visible in
             if visible {
                 appStore.layoutRevealRequest = nil
                 cancelLegacyItemDrag()
             }
             updateSettingsPopupPresentation(isPresented: visible)
         }
         .onChange(of: appStore.openFolder?.id) { _, id in
             if id == nil { folderAppToReveal = nil }
             else { cancelLegacyItemDrag() }
         }
         .onChange(of: appStore.useCAGridRenderer) { _, _ in
             cancelLegacyItemDrag()
         }
         .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
             cancelLegacyItemDrag()
         }
    }

    private var launchpadEventBoundView: some View {
        launchpadBaseView
        .onChange(of: colorScheme) { _, _ in
            appStore.scheduleSystemAppearanceRefresh()
        }
        .overlay(alignment: .bottomTrailing) {
            if appStore.showFPSOverlay {
                Text(String(format: "%.0f FPS  %.1f ms", fpsValue, frameTimeMilliseconds))
                    .font(.caption.monospacedDigit()).bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(18)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appStore.showFPSOverlay)
         .onChange(of: appStore.items) {
             guard draggingItem == nil else { return }
             clampSelection()
             let maxPageIndex = max(pages.count - 1, 0)
             if appStore.currentPage > maxPageIndex {
                 appStore.currentPage = maxPageIndex
             }
          }
          .onChange(of: isSearchFieldFocused) { _, focused in
             if focused { isKeyboardNavigationActive = false }
         }
         .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
             WallpaperDiagnostics.record("context.spaceChanged")
             refreshBackgroundImage(reason: .contextChecked)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notification in
             guard let changedWindow = notification.object as? NSWindow,
                   changedWindow === AppDelegate.shared?.launchpadWindow else { return }
             // A window can report its screen again when it is shown. Validate
             // the display/context instead of discarding a settled frame.
             refreshBackgroundImage(reason: .contextChecked)
         }
         .onChange(of: appStore.backgroundImageEnabled) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onChange(of: appStore.launchpadBackgroundStyle) { old, new in
             guard (old == .unfiltered) != (new == .unfiltered) else { return }
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)
             .merge(with: NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification))
             .filter { notification in
                 guard let window = notification.object as? NSWindow else { return false }
                 return window === AppDelegate.shared?.launchpadWindow
             }
             .debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { notification in
             guard appStore.backgroundImageEnabled, appStore.launchpadBackgroundStyle == .unfiltered,
                   let window = notification.object as? NSWindow,
                   window === AppDelegate.shared?.launchpadWindow, !window.inLiveResize else { return }
             refreshBackgroundImage(reason: .viewportChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: .wallpaperCapturePermissionChanged)) { _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
             if appStore.backgroundImageEnabled,
                appStore.backgroundImageSource == .desktopWallpaper {
                 WallpaperCaptureAccess.shared.refresh()
             }
         }
         .onChange(of: appStore.backgroundImageSource) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }
         .onChange(of: appStore.customBackgroundImagePath) { _, _ in
             refreshBackgroundImage(reason: .settingsChanged)
         }

           .onAppear {
              if appStore.isSetting {
                  updateSettingsPopupPresentation(isPresented: true)
              }
              appStore.performInitialScanIfNeeded()
              checkCacheStatus()
              setupKeyHandlers()
              setupInitialSelection()
              setupWindowShownObserver()
              setupWindowHiddenObserver()
              let windowIsAlreadyVisible = AppDelegate.shared?.launchpadWindow?.isVisible == true
              isWindowVisible = windowIsAlreadyVisible
              if windowIsAlreadyVisible {
                  refreshBackgroundImage(reason: .windowShown)
              } else {
                  // Deliver the initial preference even for a login launch that
                  // starts hidden, so disabled snapshot caches are cleaned up.
                  refreshBackgroundImage(reason: .settingsChanged)
              }
              // 监听全局鼠标抬起，确保拖拽状态被正确清理（窗口外释放时）
               if let existing = globalMouseUpMonitor { NSEvent.removeMonitor(existing) }
               globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in
                   if legacyItemDragSession != nil {
                       endLegacyItemDrag()
                       return
                   }
                   if handoffEventMonitor != nil || draggingItem != nil {
                       finalizeHandoffDrag()
                   }
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                      if draggingItem != nil {
                          draggingItem = nil
                          pendingDropIndex = nil
                          appStore.isDragCreatingFolder = false
                          appStore.folderCreationTarget = nil
                          pageFlipManager.isCooldown = false
                          isHandoffDragging = false
                          clampSelection()
                      }
                  }
              }
               isKeyboardNavigationActive = false
               clampSelection()
              if appStore.showFPSOverlay {
                  startFPSMonitoring()
              }
           }
         .onDisappear {
             cancelLegacyItemDrag()
             [keyMonitor, handoffEventMonitor].forEach { monitor in
                 if let monitor = monitor { NSEvent.removeMonitor(monitor) }
             }
             if let monitor = globalMouseUpMonitor { NSEvent.removeMonitor(monitor) }
             [windowObserver, windowHiddenObserver].forEach { observer in
                 if let observer = observer { NotificationCenter.default.removeObserver(observer) }
             }
            keyMonitor = nil
            handoffEventMonitor = nil
            globalMouseUpMonitor = nil
            windowObserver = nil
            windowHiddenObserver = nil
            stopFPSMonitoring()
            backgroundImageController.clear()
         }
        .onChange(of: appStore.showFPSOverlay) { _, enabled in
            if enabled {
                startFPSMonitoring()
            } else {
                stopFPSMonitoring()
                fpsValue = 0
            }
        }
        .onChange(of: appStore.voiceFeedbackEnabled) { _, enabled in
            if enabled {
                if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                    let item = filteredItems[idx]
                    VoiceManager.shared.announceSelection(item: item)
                }
            } else {
                VoiceManager.shared.stop()
            }
        }
         .onChange(of: appStore.isLayoutLocked) { _, locked in
            guard locked else { return }
            cancelLegacyItemDrag()
            if let monitor = handoffEventMonitor {
                NSEvent.removeMonitor(monitor)
                handoffEventMonitor = nil
            }
            draggingItem = nil
            pendingDropIndex = nil
            dragPreviewPosition = .zero
            dragPointerOffset = .zero
            dragPreviewScale = 1.2
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            appStore.handoffDraggingApp = nil
            appStore.handoffDragScreenLocation = nil
            folderHoverCandidateIndex = nil
            folderHoverBeganAt = nil
            pageFlipManager.isCooldown = false
            isHandoffDragging = false
            blankDragStartPoint = nil
            blankDragShouldIgnore = false
            blankDragConsumed = false
            appStore.cleanupUnusedNewPage()
            appStore.removeEmptyPages()
            appStore.saveAllOrder()
            clampSelection()
        }
    }

    private var launchpadBaseView: some View {
        ZStack {
            LaunchpadBackgroundImageView(image: displayedBackgroundImage)
                .allowsHitTesting(false)

            launchpadBackdropLayer

            // Keep the transparent edge-to-dismiss hit regions below the
            // interactive content. Otherwise they can steal clicks from the
            // bottom controls, especially when organizing changes page count.
            launchpadEdgeDismissalLayer

            launchpadStyledContent
        }
        .ignoresSafeArea()
        .overlay(launchpadInteractionOverlay)
        .overlayPreferenceValue(SettingsButtonAnchorPreferenceKey.self) { buttonAnchor in
            GeometryReader { proxy in
                if settingsPopupIsMounted {
                    let rootFrame = proxy.frame(in: .global)
                    let buttonFrame = buttonAnchor.map {
                        proxy[$0].offsetBy(dx: rootFrame.minX, dy: rootFrame.minY)
                    } ?? .zero
                    LiquidSettingsPopup(
                        appStore: appStore,
                        progress: settingsPopupProgress,
                        buttonFrameInWindow: buttonFrame,
                        onDismiss: { appStore.isSetting = false }
                    )
                    .zIndex(100)
                }
            }
        }
        .overlay(alignment: .top) {
            if let autoOrganizationFeedback {
                HStack(spacing: 8 * LaunchpadUIMetrics.overallScale) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(autoOrganizationFeedback)
                        .font(.system(size: 13 * LaunchpadUIMetrics.overallScale, weight: .medium))
                }
                .padding(.horizontal, 16 * LaunchpadUIMetrics.overallScale)
                .padding(.vertical, 10 * LaunchpadUIMetrics.overallScale)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
                .padding(.top, 72 * LaunchpadUIMetrics.overallScale)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }
        }
    }

    private func updateSettingsPopupPresentation(isPresented: Bool) {
        if isPresented {
            settingsPopupDismissID = UUID()
            settingsPopupIsMounted = true
            settingsPopupProgress = 0
            DispatchQueue.main.async {
                guard appStore.isSetting else { return }
        withAnimation(.linear(duration: 1.45)) {
            settingsPopupProgress = 1
        }
            }
            return
        }

        guard settingsPopupIsMounted else {
            return
        }

        let dismissID = UUID()
        settingsPopupDismissID = dismissID
        withAnimation(.timingCurve(0.38, 0.02, 0.72, 0.30, duration: 0.38)) {
            settingsPopupProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            guard settingsPopupDismissID == dismissID, !appStore.isSetting else { return }
            settingsPopupIsMounted = false
        }
    }

    private var launchpadStyledContent: some View {
        GeometryReader { geo in
            launchpadMainContent(in: geo)
        }
        .padding()
        .launchpadBackgroundStyle(effectiveBackgroundStyle,
                                  cornerRadius: appStore.isFullscreenMode ? 0 : 30,
                                  forcedColor: appStore.developmentBackgroundOverride.color,
                                  maskColor: appStore.backgroundMaskColor(for: colorScheme))
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global)
                .onEnded { value in
                    // Let a control's Button action publish its state before
                    // this ancestor classifies the same pointer-up as blank.
                    DispatchQueue.main.async {
                        handleWindowBackgroundTap(at: value.location)
                    }
                },
            including: .all
        )
        .onChange(of: showBackgroundOptions) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            // A click that dismisses the popover may also reach the ancestor
            // SpatialTapGesture. Keep that same click from closing LaunchNext.
            pageControlButtonIsPressed = true
            let releaseID = UUID()
            pageControlButtonPressID = releaseID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard pageControlButtonPressID == releaseID else { return }
                pageControlButtonIsPressed = false
            }
        }
    }

    private var launchpadBackdropLayer: some View {
        ZStack {
            Color.black.opacity(backdropOpacity)
        }
        .animation(.easeInOut(duration: 0.22), value: colorScheme)
        .allowsHitTesting(false)
    }

    private var launchpadEdgeDismissalLayer: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let topSafe = max(0, headerTotalHeight)
            let bottomPad = max(config.isFullscreen ? height * config.bottomPadding : 0, 24)
            let sidePad = max(config.isFullscreen ? width * config.horizontalPadding : 0, 24)

            VStack(spacing: 0) {
                Rectangle().fill(Color.clear)
                    .frame(height: topSafe)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                Rectangle().fill(Color.clear)
                    .frame(height: bottomPad)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deferEdgeDismissal()
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                Rectangle().fill(Color.clear)
                    .frame(width: sidePad)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deferEdgeDismissal()
                    }
                Spacer(minLength: 0)
                Rectangle().fill(Color.clear)
                    .frame(width: sidePad)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        deferEdgeDismissal()
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private func deferEdgeDismissal() {
        DispatchQueue.main.async {
            guard appStore.openFolder == nil,
                  !appStore.isSetting,
                  !appStore.isFolderNameEditing,
                  !pageControlButtonIsPressed else { return }
            AppDelegate.shared?.hideWindow()
        }
    }

    private var displayedBackgroundImage: CGImage? {
        guard appStore.backgroundImageEnabled,
              appStore.developmentBackgroundOverride.color == nil else {
            return nil
        }
        return backgroundImageController.content?.image
    }

    private var resolvedBackgroundLabelSample: BackgroundLabelContrast? {
        displayedBackgroundImage == nil ? nil : backgroundImageController.content?.labelSample
    }

    private var resolvedWallpaperControlStyle: BackgroundLabelContrast.Style? {
        resolvedBackgroundLabelSample?.resolvedStyle(darkAppearance: colorScheme == .dark,
                                                     tints: backgroundLabelTints)
    }

    private func toolbarSymbol(_ name: String) -> some View {
        let scale = LaunchpadUIMetrics.overallScale
        let style = resolvedWallpaperControlStyle
        let foreground = style.map { AnyShapeStyle(($0.usesWhiteText ? Color.white : Color.black).opacity(0.75)) }
            ?? AnyShapeStyle(.placeholder.opacity(0.5))
        return Image(systemName: name)
            .font(.system(size: 22 * scale))
            .foregroundStyle(foreground)
    }

    private var backgroundLabelTints: [BackgroundLabelContrast.Tint] {
        var tints = [BackgroundLabelContrast.Tint(red: 0, green: 0, blue: 0, alpha: backdropOpacity),
]
        if appStore.backgroundMaskEnabled {
            let mask = colorScheme == .dark ? appStore.backgroundMaskDarkColor : appStore.backgroundMaskLightColor
            tints.append(.init(red: mask.red, green: mask.green, blue: mask.blue, alpha: mask.alpha))
        }
        return tints.filter { $0.alpha > 0 }
    }

    private var effectiveBackgroundStyle: AppStore.BackgroundStyle {
        // Preserve the saved choice, but keep a usable backdrop without an image.
        if appStore.launchpadBackgroundStyle == .unfiltered, displayedBackgroundImage == nil {
            return .glass
        }
        return appStore.launchpadBackgroundStyle
    }

    private func handleHeaderBackgroundTap() {
        DispatchQueue.main.async {
            guard appStore.openFolder == nil,
                  !appStore.isSetting,
                  !appStore.isFolderNameEditing,
                  draggingItem == nil,
                  !pageControlButtonIsPressed else { return }
            AppDelegate.shared?.hideWindow()
        }
    }

    private func handleWindowBackgroundTap(at point: CGPoint) {
        // The parent SpatialTapGesture also sees page-control button taps.
        // Suppress its dismissal path while either button owns the click.
        guard !pageControlButtonIsPressed, !showBackgroundOptions else { return }
        guard appStore.openFolder == nil,
              !appStore.isSetting,
              !appStore.isFolderNameEditing,
              draggingItem == nil,
              !appStore.isDragCreatingFolder else { return }

        // These areas contain controls with their own tap behavior. Header
        // whitespace already has its own dismissal catcher.
        if headerFrameInWindow.contains(point)
            || favoritesFrameInWindow.contains(point)
            || pageIndicatorFrameInWindow.contains(point)
            || removePageButtonFrameInWindow.contains(point)
            || addPageButtonFrameInWindow.contains(point)
            || autoOrganizeButtonFrameInWindow.contains(point)
            || backgroundButtonFrameInWindow.contains(point)
            || settingsButtonFrameInWindow.contains(point) {
            return
        }

        let gridFrame = CGRect(origin: gridOriginInWindow, size: currentContainerSize)
        if currentContainerSize != .zero, gridFrame.contains(point) {
            // Apply the same icon/label hit test for both grid renderers. The
            // native grid view may own the mouse event before SwiftUI sees it.
            closeIfTappedOnEmptyOrGap(
                at: CGPoint(x: point.x - gridOriginInWindow.x,
                            y: point.y - gridOriginInWindow.y),
                geoSize: currentContainerSize,
                columnWidth: currentColumnWidth,
                appHeight: currentAppHeight,
                iconSize: currentIconSize
            )
            return
        }

        AppDelegate.shared?.hideWindow()
    }

    private func launchpadMainContent(in geo: GeometryProxy) -> some View {
        let uiScale = LaunchpadUIMetrics.overallScale
        let actualTopPadding = config.isFullscreen ? geo.size.height * config.topPadding : 0
        let actualBottomPadding = config.isFullscreen ? geo.size.height * config.bottomPadding : 0
        let actualHorizontalPadding = config.isFullscreen ? geo.size.width * config.horizontalPadding : 0
        let indicatorTopPadding = appStore.effectivePageIndicatorTopPadding(for: currentScreenID)
        let indicatorOffset = appStore.effectivePageIndicatorOffset(for: currentScreenID)

        return VStack {
            // 在顶部添加动态padding（全屏模式）
            if config.isFullscreen {
                Spacer()
                    .frame(height: actualTopPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleHeaderBackgroundTap()
                    }
            }
            ZStack {
                HStack(spacing: 8 * uiScale) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13 * uiScale))
                        .foregroundStyle(.secondary)
                    TextField(appStore.localized(.searchPlaceholder), text: $appStore.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13 * uiScale))
                }
                .padding(.vertical, 8 * uiScale)
                .padding(.horizontal, 12 * uiScale)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 16 * uiScale, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16 * uiScale, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: 480 * uiScale)
                .disabled(isFolderOpen)
                .onChange(of: appStore.searchQuery) {
                    guard !isFolderOpen, appStore.layoutRevealRequest == nil else { return }
                    let query = appStore.searchQuery
                    // 避免在视图更新周期内直接发布变化，推迟到下一循环
                    let maxPageIndex = max(pages.count - 1, 0)
                    DispatchQueue.main.async {
                        guard appStore.searchQuery == query, appStore.layoutRevealRequest == nil else { return }
                        appStore.currentPage = 0
                        if appStore.currentPage > maxPageIndex {
                            appStore.currentPage = maxPageIndex
                        }
                    }
                    selectedIndex = filteredItems.isEmpty ? nil : 0
                    isKeyboardNavigationActive = false
                    clampSelection()
                }
                .focused($isSearchFieldFocused)
                .frame(maxWidth: .infinity)

                HStack(spacing: 8 * uiScale) {
                    Spacer()
                    if appStore.showQuickRefreshButton {
                        Button {
                            appStore.refresh()
                        } label: {
                            toolbarSymbol("arrow.clockwise.circle")
                        }
                        .buttonStyle(.plain)
                        .help(appStore.localized(.refresh))
                    }
                    Button {
                        appStore.isSetting = true
                    } label: {
                        toolbarSymbol("ellipsis.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top)
            .padding(.horizontal)
            .background(
                ZStack {
                    // Search and toolbar controls remain above this catcher, so
                    // only otherwise-empty header space closes LaunchNext.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleHeaderBackgroundTap()
                        }

                    GeometryReader { proxy in
                        // Track the total header height, including dynamic top padding and extra spacing.
                        Color.clear.onAppear {
                            let extra: CGFloat = 24
                            let total = (config.isFullscreen ? geo.size.height * config.topPadding : 0) + proxy.size.height + extra
                            let frame = proxy.frame(in: .global)
                            DispatchQueue.main.async {
                                headerTotalHeight = total
                                headerFrameInWindow = frame
                            }
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in
                            let extra: CGFloat = 24
                            let total = (config.isFullscreen ? geo.size.height * config.topPadding : 0) + proxy.size.height + extra
                            DispatchQueue.main.async {
                                headerTotalHeight = total
                                headerFrameInWindow = frame
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
            )
            .opacity(isFolderOpen ? 0.1 : 1)
            .allowsHitTesting(!isFolderOpen)

            // 保持原有上下留白，去掉可见的分割线
            Spacer()
                .frame(height: 16)

            GeometryReader { gridGeo in
                let adaptiveGridViewportSize = CGSize(
                    width: gridGeo.size.width,
                    height: max(0, gridGeo.size.height - actualTopPadding - actualBottomPadding)
                )
                gridRegion(in: gridGeo,
                           actualTopPadding: actualTopPadding,
                           actualBottomPadding: actualBottomPadding)
                .clipped()
                .onAppear {
                    appStore.updateAdaptiveGridMetrics(for: adaptiveGridViewportSize)
                }
                .onChange(of: adaptiveGridViewportSize) { _, size in
                    appStore.updateAdaptiveGridMetrics(for: size)
                }
            }

            LaunchpadFavoritesBar(appStore: appStore, onLaunch: launchApp)
                .padding(.top, 12)
                .reportWindowFrame { favoritesFrameInWindow = $0 }
                .opacity(isFolderOpen ? 0.1 : 1)
                .allowsHitTesting(!isFolderOpen)

            // Keep the page slider centered, with the compact organizer capsule
            // sitting beside it like a shorter Dynamic Island.
            ZStack {
                    // Keep the glass page bubble visible on a single page too;
                    // the organizer capsule remains anchored beside it.
                    LaunchpadPageIndicator(pageCount: pageControlCount,
                                          currentPage: currentPageForDisplay,
                                          isActive: !isFolderOpen && isWindowVisible,
                                          backgroundStyle: resolvedWallpaperControlStyle) { index in
                        navigateToPage(index)
                    }
                    .reportWindowFrame { pageIndicatorFrameInWindow = $0 }

                    addPageButton
                        .frame(width: PageControlMetrics.buttonSize, height: PageControlMetrics.buttonSize)
                        .offset(x: PageControlMetrics.addButtonOffset(pageCount: pageControlCount))
                        .reportWindowFrame { addPageButtonFrameInWindow = $0 }

                    removePageButton
                        .frame(width: PageControlMetrics.buttonSize, height: PageControlMetrics.buttonSize)
                        .offset(x: PageControlMetrics.removeButtonOffset(pageCount: pageControlCount))
                        .reportWindowFrame { removePageButtonFrameInWindow = $0 }

                    autoOrganizerButton
                        .frame(width: PageControlMetrics.organizerWidth, height: PageControlMetrics.organizerHeight)
                        .offset(x: PageControlMetrics.organizeButtonOffset(pageCount: pageControlCount))
                        .reportWindowFrame { autoOrganizeButtonFrameInWindow = $0 }

                    backgroundButton
                        .frame(width: PageControlMetrics.backgroundButtonWidth, height: PageControlMetrics.organizerHeight)
                        .offset(x: PageControlMetrics.backgroundButtonOffset(pageCount: pageControlCount))
                        .reportWindowFrame { backgroundButtonFrameInWindow = $0 }

                    settingsButton
                        .frame(width: PageControlMetrics.buttonSize, height: PageControlMetrics.buttonSize)
                        .offset(x: PageControlMetrics.settingsButtonOffset(pageCount: pageControlCount))
                        .reportWindowFrame { settingsButtonFrameInWindow = $0 }
                }
                .frame(maxWidth: .infinity)
                .frame(height: PageControlMetrics.rowHeight)
                .padding(.top, CGFloat(indicatorTopPadding))
                .padding(.bottom, CGFloat(indicatorOffset))
                .opacity(isFolderOpen ? 0.1 : 1)
                .allowsHitTesting(!isFolderOpen)

            // 在页面指示圆点下方添加动态padding
            if config.isFullscreen {
                Spacer()
                    .frame(height: actualBottomPadding)
            }
        }
        .padding(.horizontal, actualHorizontalPadding)
    }

    private var addPageButton: some View {
        PageControlCircleButton(
            symbol: "plus",
            title: appStore.localized(.addPageButton),
            isEnabled: canAddPage,
            onPressChanged: setPageControlButtonPressed,
            action: addPageToRight
        )
    }

    private var pageControlCount: Int { max(1, pages.count) }

    private var canAddPage: Bool {
        !appStore.isLayoutLocked && !isFolderOpen && !appStore.isSetting && appStore.searchQuery.isEmpty
    }

    private var currentPageIsEmpty: Bool {
        guard pageControlCount > 1 else { return false }
        return appStore.isGridPageEmpty(at: currentPageForDisplay)
    }

    private var currentPageForDisplay: Int {
        min(max(appStore.currentPage, 0), max(0, pages.count - 1))
    }

    private var canRemoveCurrentPage: Bool {
        !appStore.isLayoutLocked && !isFolderOpen && !appStore.isSetting
            && appStore.searchQuery.isEmpty && currentPageIsEmpty
    }

    private var removePageButton: some View {
        PageControlCircleButton(
            symbol: "minus",
            title: appStore.localized(.removePageButton),
            isEnabled: canRemoveCurrentPage,
            onPressChanged: setPageControlButtonPressed,
            action: removeCurrentPage
        )
    }

    private func removeCurrentPage() {
        guard canRemoveCurrentPage else { return }
        _ = withAnimation(LNAnimations.springFast) {
            appStore.removeCurrentPageIfEmpty()
        }
    }

    private func addPageToRight() {
        guard !appStore.isLayoutLocked, !isFolderOpen, !appStore.isSetting,
              appStore.searchQuery.isEmpty else { return }
        withAnimation(LNAnimations.springFast) {
            appStore.addUserPage()
        }
    }

    private var autoOrganizerButton: some View {
        Button(action: organizeAppsAutomatically) {
            HStack(spacing: 5 * LaunchpadUIMetrics.overallScale) {
                    Image(systemName: "sparkles")
                    .font(.system(size: 11 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                Text(appStore.localized(.autoOrganizeButton))
                    .font(.system(size: 11 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 9 * LaunchpadUIMetrics.overallScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule().fill(Color.clear).glassEffect(.regular, in: Capsule())
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressTrackingPlainButtonStyle(onPressChanged: setPageControlButtonPressed))
        .disabled(appStore.isLayoutLocked || isFolderOpen || appStore.isSetting)
        .opacity(appStore.isLayoutLocked ? 0.5 : 1)
        .help(appStore.localized(.autoOrganizeButton))
        .accessibilityLabel(Text(appStore.localized(.autoOrganizeButton)))
    }

    private var backgroundButton: some View {
        Button {
            showBackgroundOptions.toggle()
        } label: {
            HStack(spacing: 5 * LaunchpadUIMetrics.overallScale) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                Text(appStore.localized(.backgroundButton))
                    .font(.system(size: 11 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 9 * LaunchpadUIMetrics.overallScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule().fill(Color.clear).glassEffect(.regular, in: Capsule())
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(TapGuardPlainButtonStyle(onPressChanged: setPageControlButtonPressed))
        .disabled(isFolderOpen || appStore.isSetting)
        .help(appStore.localized(.backgroundButton))
        .accessibilityLabel(Text(appStore.localized(.backgroundButton)))
        .popover(isPresented: $showBackgroundOptions, arrowEdge: .bottom) {
            backgroundOptionsPopover
        }
    }

    private var settingsButton: some View {
        Button {
            appStore.isSetting = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12 * LaunchpadUIMetrics.overallScale, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Circle().fill(Color.clear).glassEffect(.regular, in: Circle())
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(TapGuardPlainButtonStyle(onPressChanged: setPageControlButtonPressed))
        .disabled(isFolderOpen || appStore.isSetting)
        .help(appStore.localized(.settingsButton))
        .accessibilityLabel(Text(appStore.localized(.settingsButton)))
        .anchorPreference(key: SettingsButtonAnchorPreferenceKey.self, value: .bounds) { $0 }
    }

    private var backgroundOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appStore.localized(.backgroundMenuTitle))
                .font(.headline)
                .padding(.bottom, 2)

            backgroundOptionRow(
                title: appStore.localized(.backgroundOptionClassic),
                subtitle: appStore.localized(.backgroundOptionClassicDescription),
                systemImage: "desktopcomputer",
                isSelected: appStore.backgroundImageEnabled
                    && appStore.backgroundImageSource != .customImage
            ) {
                withAnimation(LNAnimations.springFast) {
                    appStore.backgroundImageSource = .desktopPreview
                    appStore.backgroundImageEnabled = true
                    appStore.launchpadBackgroundStyle = .glass
                }
                showBackgroundOptions = false
            }

            backgroundOptionRow(
                title: appStore.localized(.backgroundOptionPhotos),
                subtitle: appStore.localized(.backgroundOptionPhotosDescription),
                systemImage: "photo",
                isSelected: appStore.backgroundImageEnabled
                    && appStore.backgroundImageSource == .customImage
            ) {
                showBackgroundOptions = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    choosePhotoBackground()
                }
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private func backgroundOptionRow(title: String,
                                     subtitle: String,
                                     systemImage: String,
                                     isSelected: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.8))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TapGuardPlainButtonStyle(onPressChanged: setPageControlButtonPressed))
    }

    private func choosePhotoBackground() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.image]
        panel.prompt = appStore.localized(.backgroundOptionPhotos)

        guard AppDelegate.withModalDialog({ panel.runModal() }) == .OK,
              let url = panel.url else { return }

        appStore.customBackgroundImagePath = url.standardizedFileURL.path
        appStore.backgroundImageSource = .customImage
        appStore.backgroundImageEnabled = true
        appStore.launchpadBackgroundStyle = .unfiltered
    }

    private func setPageControlButtonPressed(_ isPressed: Bool) {
        if isPressed {
            pageControlButtonIsPressed = true
            pageControlButtonPressID = UUID()
            return
        }

        let releaseID = UUID()
        pageControlButtonPressID = releaseID
        // Let the ancestor tap gesture finish processing this same mouse-up
        // before allowing it to treat later blank-area clicks as dismissals.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard pageControlButtonPressID == releaseID else { return }
            pageControlButtonIsPressed = false
        }
    }

    private func organizeAppsAutomatically() {
        let result = withAnimation(LNAnimations.gridUpdate) {
            appStore.organizeAppsAutomatically()
        }
        let message: String
        if result.appsOrganized > 0, result.foldersRenamed > 0 {
            message = String(format: appStore.localized(.autoOrganizeDoneWithRenamesFormat),
                             result.appsOrganized,
                             result.foldersCreated,
                             result.foldersRenamed)
        } else if result.appsOrganized > 0 {
            message = String(format: appStore.localized(.autoOrganizeDoneFormat),
                             result.appsOrganized,
                             result.foldersCreated)
        } else if result.foldersRenamed > 0 {
            message = String(format: appStore.localized(.autoOrganizeFoldersNamedFormat), result.foldersRenamed)
        } else {
            message = appStore.localized(.autoOrganizeNothingToDo)
        }
        let feedbackID = UUID()
        autoOrganizationFeedbackID = feedbackID
        withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
            autoOrganizationFeedback = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard autoOrganizationFeedbackID == feedbackID else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                autoOrganizationFeedback = nil
            }
        }
    }

    private var launchpadInteractionOverlay: some View {
        ZStack {
            // 全窗口滚动捕获层（不拦截点击，仅监听滚动）
            if !appStore.useCAGridRenderer {
                ScrollEventCatcher { deltaX, deltaY, phase, isMomentum, isPrecise in
                    guard !appStore.isSetting else { return }
                    let pageWidth = currentContainerSize.width + config.pageSpacing
                    handleScroll(deltaX: deltaX,
                                 deltaY: deltaY,
                                 phase: phase,
                                 isMomentum: isMomentum,
                                 isPrecise: isPrecise,
                                 pageWidth: pageWidth)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // 半透明背景：仅在文件夹打开时插入，使用淡入淡出过渡
            if isFolderOpen {
                Color.black
                    .opacity(0.1)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    // Native folder presentation owns dismissal during CA transitions.
                    .allowsHitTesting(!appStore.useCAGridRenderer)
                    .onTapGesture {
                        if !appStore.isFolderNameEditing {
                            let closingFolder = appStore.openFolder
                            withAnimation(LNAnimations.springFast) { appStore.openFolder = nil }
                            if let folder = closingFolder,
                               let idx = filteredItems.firstIndex(of: .folder(folder)) {
                                isKeyboardNavigationActive = true
                                selectedIndex = idx
                                let targetPage = idx / config.itemsPerPage
                                if targetPage != appStore.currentPage { appStore.currentPage = targetPage }
                            }
                            isSearchFieldFocused = true
                        }
                    }
            }

            if appStore.useCAGridRenderer {
                CAFolderPresentation(appStore: appStore, controller: folderPresentation,
                    iconSize: currentIconSize * CGFloat(min(max(appStore.iconScale, 0.6), 1.15)),
                    onClose: { closePresentedFolder() }, onLaunchApp: { launchApp($0) },
                    backgroundLabelSample: resolvedBackgroundLabelSample,
                    backgroundLabelTints: backgroundLabelTints,
                    initialRevealAppPath: folderAppToReveal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let openFolder = appStore.openFolder {
                GeometryReader { proxy in
                    let widthFactor: CGFloat = appStore.isFullscreenMode ? 0.7 : CGFloat(appStore.folderPopoverWidthFactor)
                    let heightFactor: CGFloat = appStore.isFullscreenMode ? 0.7 : CGFloat(appStore.folderPopoverHeightFactor)
                    let minWidth: CGFloat = appStore.isFullscreenMode ? 520 : 560
                    let minHeight: CGFloat = 420
                    let rawHorizontalMargin: CGFloat = appStore.isFullscreenMode ? max(proxy.size.width * 0.15, 120) : 32
                    let rawVerticalMargin: CGFloat = appStore.isFullscreenMode ? max(proxy.size.height * 0.15, 120) : 32
                    let horizontalMargin = min(rawHorizontalMargin, proxy.size.width / 2)
                    let verticalMargin = min(rawVerticalMargin, proxy.size.height / 2)

                    let proposedWidth = proxy.size.width * widthFactor
                    let proposedHeight = proxy.size.height * heightFactor

                    let maxAllowedWidth = max(proxy.size.width - horizontalMargin * 2, 0)
                    let maxAllowedHeight = max(proxy.size.height - verticalMargin * 2, 0)

                    let minAllowedWidth = min(minWidth, maxAllowedWidth)
                    let minAllowedHeight = min(minHeight, maxAllowedHeight)

                    let clampedWidth = max(min(proposedWidth, maxAllowedWidth), minAllowedWidth)
                    let clampedHeight = max(min(proposedHeight, maxAllowedHeight), minAllowedHeight)
                    let folderId = openFolder.id

                    // 使用计算属性来确保绑定能够正确响应folderUpdateTrigger的变化
                    let folderBinding = Binding<FolderInfo>(
                        get: {
                            // 每次访问都重新查找文件夹，确保获取最新状态
                            if let idx = appStore.folders.firstIndex(where: { $0.id == folderId }) {
                                return appStore.folders[idx]
                            }
                            return openFolder
                        },
                        set: { newValue in
                            if let idx = appStore.folders.firstIndex(where: { $0.id == folderId }) {
                                appStore.folders[idx] = newValue
                            }
                        }
                    )

                    FolderView(
                        appStore: appStore,
                        folder: folderBinding,
                        preferredIconSize: currentIconSize * CGFloat(min(max(appStore.iconScale, 0.6), 1.15)),
                        initialRevealAppPath: folderAppToReveal,
                        onClose: {
                            let closingFolder = appStore.openFolder
                            withAnimation(LNAnimations.springFast) {
                                appStore.openFolder = nil
                            }
                            // 关闭后将键盘导航选中项切换到该文件夹
                            if let folder = closingFolder,
                               let idx = filteredItems.firstIndex(of: .folder(folder)) {
                                isKeyboardNavigationActive = true
                                selectedIndex = idx
                                let targetPage = idx / config.itemsPerPage
                                if targetPage != appStore.currentPage {
                                    appStore.currentPage = targetPage
                                }
                            }
                            // 关闭文件夹后恢复搜索框焦点
                            isSearchFieldFocused = true
                        },
                        onLaunchApp: { app in
                            launchApp(app)
                        }
                    )
                    .frame(width: clampedWidth, height: clampedHeight)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .id("folder_\(folderId)") // 使用稳定ID，避免每次更新导致视图重建
                    .transition(LNAnimations.folderOpenTransition)
                }
            }

        }
    }
    
    private func gridRegion(in geo: GeometryProxy,
                            actualTopPadding: CGFloat,
                            actualBottomPadding: CGFloat) -> AnyView {
        let appCountPerRow = config.columns
        let maxRowsPerPage = Int(ceil(Double(config.itemsPerPage) / Double(appCountPerRow)))
        let availableWidth = geo.size.width
        let availableHeight = geo.size.height - (actualTopPadding + actualBottomPadding)

        let appHeight: CGFloat = {
            let totalRowSpacing = config.rowSpacing * CGFloat(maxRowsPerPage - 1)
            let height = (availableHeight - totalRowSpacing) / CGFloat(maxRowsPerPage)
            return max(56, height)
        }()

        let columnWidth: CGFloat = {
            let totalColumnSpacing = config.columnSpacing * CGFloat(appCountPerRow - 1)
            let width = (availableWidth - totalColumnSpacing) / CGFloat(appCountPerRow)
            return max(40, width)
        }()

        // Slightly larger icons in a denser grid that fills each page.
        let iconSize: CGFloat = min(columnWidth, appHeight) * CGFloat(min(max(appStore.iconScale, 0.6), 1.15)) * 0.85
        let effectivePageWidth = geo.size.width + config.pageSpacing

        if appStore.isInitialLoading {
            return AnyView(
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .progressViewStyle(.circular)
                    Text(appStore.localized(.loadingApplications))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        if filteredItems.isEmpty && !appStore.searchQuery.isEmpty {
            return AnyView(
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.placeholder)
                    Text(appStore.localized(.noAppsFound))
                        .font(.title)
                        .foregroundStyle(.placeholder)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        if appStore.useCAGridRenderer {
            let caInsets = NSEdgeInsets(top: actualTopPadding,
                                        left: 0,
                                        bottom: actualBottomPadding,
                                        right: 0)
            let caItems: [LaunchpadItem] = filteredItems
            let externalDragSourceIndex: Int? = draggingItem.flatMap { filteredItems.firstIndex(of: $0) }
            let externalDragHoverIndex: Int? = draggingItem != nil ? pendingDropIndex : nil

            return AnyView(
                ZStack(alignment: .topLeading) {
                    CAGridViewRepresentable(
                        appStore: appStore,
                        items: caItems,
                        iconSize: iconSize,
                        columnSpacing: config.columnSpacing,
                        rowSpacing: config.rowSpacing,
                        contentInsets: caInsets,
                        pageSpacing: config.pageSpacing,
                        onOpenApp: nil,
                        onOpenFolder: { folder in
                            withAnimation(LNAnimations.springFast) {
                                appStore.openFolder = folder
                            }
                        },
                        externalDragSourceIndex: externalDragSourceIndex,
                        externalDragHoverIndex: externalDragHoverIndex,
                        selectedIndex: isKeyboardNavigationActive ? selectedIndex : nil,
                        folderPresentation: folderPresentation,
                        backgroundLabelSample: resolvedBackgroundLabelSample,
                        backgroundLabelTints: backgroundLabelTints
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isFolderOpen ? 0.1 : 1)
                    .allowsHitTesting(!isFolderOpen)

                    if let draggingItem {
                        DragPreviewItem(item: draggingItem,
                                        iconSize: iconSize,
                                        labelWidth: columnWidth * 0.9,
                                        scale: dragPreviewScale)
                            .position(x: dragPreviewPosition.x, y: dragPreviewPosition.y)
                            .zIndex(100)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "grid")
                .onAppear {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
                .onChange(of: appStore.handoffDraggingApp) {
                    if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                        startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: appStore.openFolder) {
                    if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                        startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: geo.size) {
                    DispatchQueue.main.async {
                        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
                .onChange(of: appStore.gridRefreshTrigger) { _, _ in
                    DispatchQueue.main.async {
                        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                    }
                }
            )
        }

        let hStackOffset = -CGFloat(appStore.currentPage) * effectivePageWidth + scrollState.followOffset

        return AnyView(
            ZStack(alignment: .topLeading) {
                // 内容
                HStack(spacing: config.pageSpacing) {
                    ForEach(pages.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            // 在网格上方添加动态padding
                            if config.isFullscreen {
                                Spacer()
                                    .frame(height: actualTopPadding)
                            }
                            LazyVGrid(columns: config.gridItems, spacing: config.rowSpacing) {
                                let pageItems = pages[index]
                                ForEach(0..<pageItems.count, id: \.self) { localOffset in
                                    let item = pageItems[localOffset]
                                    let globalIndex = index * config.itemsPerPage + localOffset
                                    itemDraggable(
                                        item: item,
                                        globalIndex: globalIndex,
                                        pageIndex: index,
                                        containerSize: geo.size,
                                        columnWidth: columnWidth,
                                        iconSize: iconSize,
                                        appHeight: appHeight,
                                        labelWidth: columnWidth * 0.9,
                                        isSelected: (!isFolderOpen && isKeyboardNavigationActive && selectedIndex == globalIndex)
                                    )
                                }
                            }
                            .animation(LNAnimations.gridUpdate, value: pendingDropIndex)
                            .id("grid_\(index)_\(displayedGridRefreshID.uuidString)")
                            // 避免非必要的全局刷新动画，降低拖拽重绘
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: hStackOffset)
                .opacity(isFolderOpen ? 0.1 : 1)
                .allowsHitTesting(!isFolderOpen)

                // 将预览提升到外层坐标空间，避免受到 offset 影响
                if let draggingItem {
                    DragPreviewItem(item: draggingItem,
                                    iconSize: iconSize,
                                    labelWidth: columnWidth * 0.9,
                                    scale: dragPreviewScale)
                        .position(x: dragPreviewPosition.x, y: dragPreviewPosition.y)
                        .zIndex(100)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "grid")
            // 让整个网格容器都可命中，以捕获空白区域的点击
            .contentShape(Rectangle())
            .simultaneousGesture(blankDragGesture(geoSize: geo.size,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight,
                                                  iconSize: iconSize),
                                 including: draggingItem == nil ? .gesture : .subviews)
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .named("grid"))
                .onEnded { value in
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    closeIfTappedOnEmptyOrGap(at: value.location,
                                          geoSize: geo.size,
                                          columnWidth: columnWidth,
                                          appHeight: appHeight,
                                          iconSize: iconSize)
                })
            .onAppear {
                if draggingItem == nil { displayedGridRefreshID = appStore.gridRefreshTrigger }
            }
            .onChange(of: draggingItem?.id) { _, id in
                if id == nil { displayedGridRefreshID = appStore.gridRefreshTrigger }
            }
            .onChange(of: appStore.handoffDraggingApp) {
                if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                    startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
            }
            .onChange(of: appStore.openFolder) {
                if appStore.openFolder == nil, appStore.handoffDraggingApp != nil {
                    startHandoffDragIfNeeded(geo: geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
            }
            .onChange(of: appStore.currentPage) {
                DispatchQueue.main.async {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)

                    // 智能预加载当前页面和相邻页面的图标
                    AppCacheManager.shared.smartPreloadIcons(
                        for: appStore.items,
                        currentPage: appStore.currentPage,
                        itemsPerPage: config.itemsPerPage
                    )
                }
            }
            .onChange(of: appStore.gridRefreshTrigger) { _, _ in
                if draggingItem == nil { displayedGridRefreshID = appStore.gridRefreshTrigger }
                DispatchQueue.main.async {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
            }
            .onChange(of: geo.size) {
                DispatchQueue.main.async {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
            }
            .task {
                await MainActor.run {
                    captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                }
            }
        )
    }

    @MainActor
    private func revealAppInLayout(_ request: AppStore.LayoutRevealRequest) async {
        guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return }
        defer {
            if appStore.layoutRevealRequest?.id == request.id {
                appStore.layoutRevealRequest = nil
            }
        }
        guard appStore.searchText.isEmpty, appStore.searchQuery.isEmpty,
              let location = appStore.layoutLocation(ofAppAtPath: request.appPath) else { return }
        isSearchFieldFocused = false
        isKeyboardNavigationActive = false
        selectedIndex = location.index
        let destinationPage = location.index / max(1, config.itemsPerPage)
        folderAppToReveal = nil

        let cancelReveal = {
            if appStore.layoutRevealRequest?.id == request.id {
                appStore.layoutRevealRequest = nil
            }
        }
        let inputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { event in
            cancelReveal()
            return event
        }
        let inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: NSApp, queue: .main
        ) { _ in cancelReveal() }
        defer {
            if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
            NotificationCenter.default.removeObserver(inactiveObserver)
        }

        // Show the restored layout before moving. Waiting is bounded so a
        // missing icon cannot leave navigation pending forever.
        if appStore.useCAGridRenderer {
            let itemID = appStore.items[location.index].id
            var navigationGrid: CAGridView?
            _ = await waitForLayoutReveal(request, timeout: 1.5) {
                guard let grid = folderPresentation.grid, grid.window?.isVisible == true,
                      grid.items.count == appStore.items.count,
                      grid.items.indices.contains(location.index), grid.items[location.index].id == itemID,
                      grid.bounds.width > 0, grid.bounds.height > 0 else { return false }
                navigationGrid = grid
                return grid.revealIconsAreReady(from: grid.currentPage, through: destinationPage)
            }
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id,
                  let grid = navigationGrid else { return }
            let showsMotion = appStore.enableAnimations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let changesPage = grid.currentPage != destinationPage
            if showsMotion && changesPage {
                // Give the restored icons a few visible frames before the first movement.
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            guard appStore.layoutRevealRequest?.id == request.id else { return }
            let pageDuration = LayoutRevealFeedback.pageDuration(distance: abs(grid.currentPage - destinationPage))
            grid.navigateToPage(destinationPage, animated: showsMotion, revealDuration: pageDuration)
            let motionID = grid.layoutRevealPageMotion?.id
            defer {
                if let motionID, grid.layoutRevealPageMotion?.id == motionID {
                    // A cancelled reveal leaves ordinary paging in charge.
                    grid.layoutRevealPageMotion = nil
                }
            }
            appStore.currentPage = destinationPage
            let arrived = await waitForLayoutReveal(request, timeout: pageDuration + 0.6) {
                !grid.isScrollAnimating
            }
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return }
            if !arrived { grid.navigateToPage(destinationPage, animated: false) }
            if showsMotion {
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            }
            guard appStore.layoutRevealRequest?.id == request.id else { return }
            let feedbackLayer = grid.presentationContainer(at: location.index)
            if let feedbackLayer,
               LayoutRevealFeedback.animate(on: feedbackLayer,
                    pressScale: CGFloat(appStore.activePressScale), enabled: appStore.enableAnimations) {
                let hasGlass = location.folder != nil && grid.usesLiquidGlassFolders
                if hasGlass {
                    grid.folderGlassAnimationDeadline = max(grid.folderGlassAnimationDeadline,
                        CACurrentMediaTime() + LayoutRevealFeedback.duration)
                    grid.syncFolderGlass()
                }
                defer {
                    feedbackLayer.removeAnimation(forKey: LayoutRevealFeedback.animationKey)
                    if hasGlass { grid.syncFolderGlass() }
                }
                do { try await Task.sleep(for: .seconds(LayoutRevealFeedback.duration)) } catch { return }
            }
        } else {
            appStore.currentPage = destinationPage
        }
        guard let folder = location.folder else { return }
        guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id,
              appStore.searchText.isEmpty, appStore.searchQuery.isEmpty,
              appStore.openFolder == nil, !appStore.isSetting,
              let currentLocation = appStore.layoutLocation(ofAppAtPath: request.appPath),
              currentLocation.index == location.index, currentLocation.folder?.id == folder.id,
              appStore.currentPage == location.index / max(1, config.itemsPerPage),
              selectedIndex == location.index else { return }
        folderAppToReveal = request.appPath
        appStore.openFolderActivatedByKeyboard = false
        appStore.openFolder = currentLocation.folder
    }

    @MainActor
    private func waitForLayoutReveal(_ request: AppStore.LayoutRevealRequest,
                                     timeout: TimeInterval, until ready: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        repeat {
            guard !Task.isCancelled, appStore.layoutRevealRequest?.id == request.id else { return false }
            if ready() { return true }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
        } while CACurrentMediaTime() < deadline
        return false
    }

    private func closePresentedFolder() {
        let closingFolder = appStore.openFolder
        withAnimation(LNAnimations.springFast) { appStore.openFolder = nil }
        if let folder = closingFolder,
           let index = filteredItems.firstIndex(where: { $0.id == "folder_\(folder.id)" }) {
            isKeyboardNavigationActive = true
            selectedIndex = index
            let page = index / max(1, config.itemsPerPage)
            if page != appStore.currentPage { appStore.currentPage = page }
        }
        isSearchFieldFocused = true
    }

    private func launchApp(_ app: AppInfo) {
        AppDelegate.shared?.hideWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if !NSWorkspace.shared.open(app.url) {
                NSSound.beep()
            }
        }
    }
    
    private func handleItemTap(_ item: LaunchpadItem) {
        guard draggingItem == nil else { return }
        switch item {
        case .app(let app):
            launchApp(app)
        case .folder(let folder):
            withAnimation(LNAnimations.springFast) {
                appStore.openFolder = folder
            }
        case .missingApp:
            NSSound.beep()
        case .empty:
            break
        }
    }
    
    

    // MARK: - Handoff drag from folder
    private func startHandoffDragIfNeeded(geo: GeometryProxy, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        guard draggingItem == nil, let app = appStore.handoffDraggingApp else { return }
        if appStore.isLayoutLocked {
            appStore.handoffDraggingApp = nil
            appStore.handoffDragScreenLocation = nil
            return
        }
        // 更新几何上下文
        captureGridGeometry(geo, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)

        // 初始位置：屏幕 -> 网格局部
        let screenPoint = appStore.handoffDragScreenLocation ?? NSEvent.mouseLocation
        let localPoint = convertScreenToGrid(screenPoint)

        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { draggingItem = .app(app) }
        isKeyboardNavigationActive = false
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        dragPreviewScale = 1.2
        dragPreviewPosition = localPoint
        // 使接力拖拽与普通拖拽一致：预创建新页面以支持边缘翻页
        isHandoffDragging = true

        // 智能跳页：根据拖拽位置决定是否跳转到合适的页面
        if let targetIndex = indexAt(point: localPoint,
                                     in: currentContainerSize,
                                     pageIndex: appStore.currentPage,
                                     columnWidth: columnWidth,
                                     appHeight: appHeight),
           currentItems.indices.contains(targetIndex) {
            let targetPage = targetIndex / config.itemsPerPage
            if targetPage != appStore.currentPage && targetPage < pages.count {
                appStore.currentPage = targetPage
            }
        }

        if let existing = handoffEventMonitor { NSEvent.removeMonitor(existing) }
        handoffEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { event in
            switch event.type {
            case .leftMouseDragged:
                let lp = convertScreenToGrid(NSEvent.mouseLocation)
                // 复用与普通拖拽相同的核心更新逻辑
                applyDragUpdate(at: lp,
                                containerSize: currentContainerSize,
                                columnWidth: currentColumnWidth,
                                appHeight: currentAppHeight,
                                iconSize: currentIconSize)
                return nil
            case .leftMouseUp:
                finalizeHandoffDrag()
                return nil
            default:
                return event
            }
        }

        appStore.handoffDraggingApp = nil
        appStore.handoffDragScreenLocation = nil
    }

    private func convertScreenToGrid(_ screenPoint: CGPoint) -> CGPoint {
        guard let window = NSApp.keyWindow else { return screenPoint }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        // SwiftUI 的 .global 顶部为原点，AppKit 窗口坐标底部为原点，需要翻转 y
        let windowHeight = window.contentView?.bounds.height ?? window.frame.size.height
        let x = windowPoint.x - gridOriginInWindow.x
        let yFromTop = windowHeight - windowPoint.y
        let y = yFromTop - gridOriginInWindow.y
        return CGPoint(x: x, y: y)
    }

    private func handleHandoffDragMove(to localPoint: CGPoint) {
        guard !appStore.isLayoutLocked else { return }
        // 复用与普通拖拽完全一致的更新逻辑
        applyDragUpdate(at: localPoint,
                        containerSize: currentContainerSize,
                        columnWidth: currentColumnWidth,
                        appHeight: currentAppHeight,
                        iconSize: currentIconSize)
    }

    private func finalizeHandoffDrag() {
        guard draggingItem != nil else { return }
        defer {
            if let monitor = handoffEventMonitor { NSEvent.removeMonitor(monitor); handoffEventMonitor = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                draggingItem = nil
                pendingDropIndex = nil
                dragPointerOffset = .zero
                clampSelection()
                // 重置翻页状态
                pageFlipManager.isCooldown = false
                isHandoffDragging = false
                // 重置拖拽创建文件夹相关状态，确保后续拖拽功能正常
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
                // 与普通拖拽结束保持一致的清理
                appStore.cleanupUnusedNewPage()
                appStore.removeEmptyPages()
                appStore.saveAllOrder()
                // 触发网格刷新，确保拖拽手势被正确重新添加
                appStore.triggerGridRefresh()
            }
        }
        if appStore.isLayoutLocked {
            appStore.triggerGridRefresh()
            return
        }
        // 在接力拖拽模式下，落点时再计算目标索引，过程中不展示吸附
        if isHandoffDragging && pendingDropIndex == nil {
            let pointerPoint = dragPreviewPosition
            if let idx = indexAt(point: pointerPoint,
                                  in: currentContainerSize,
                                  pageIndex: appStore.currentPage,
                                  columnWidth: currentColumnWidth,
                                  appHeight: currentAppHeight) {
                pendingDropIndex = idx
            } else {
                pendingDropIndex = predictedDropIndex(for: pointerPoint,
                                                      in: currentContainerSize,
                                                      columnWidth: currentColumnWidth,
                                                      appHeight: currentAppHeight)
            }
        }

        // 使用统一的拖拽结束处理逻辑
        finalizeDragOperation(containerSize: currentContainerSize, columnWidth: currentColumnWidth, appHeight: currentAppHeight, iconSize: currentIconSize)
        
        // 立即触发网格刷新，确保拖拽手势被正确重新添加
        appStore.triggerGridRefresh()
    }

    private func navigateToPage(_ targetPage: Int, animated: Bool = true) {
        guard targetPage >= 0 && targetPage < pages.count else { return }
        if animated {
            withAnimation(LNAnimations.springFast) {
                appStore.currentPage = targetPage
            }
        } else {
            appStore.currentPage = targetPage
        }
        
        if isKeyboardNavigationActive, selectedIndex != nil,
           let target = desiredIndexForPageKeepingPosition(targetPage: targetPage) {
            selectedIndex = target
        }
    }

    private func navigateToNextPage() {
        navigateToPage(appStore.currentPage + 1)
    }
    
    private func navigateToPreviousPage() {
        navigateToPage(appStore.currentPage - 1)
    }
    
}

// MARK: - FPS Monitoring
extension LaunchpadView {
    private func startFPSMonitoring() {
        stopFPSMonitoring()
        if let monitor = FPSMonitor { fps, frameDelta in
            let clamped = max(0, min(fps, 240))
            DispatchQueue.main.async {
                let smoothed = fpsValue * 0.8 + clamped * 0.2
                fpsValue = smoothed
                frameTimeMilliseconds = frameDelta * 1000
            }
        } {
            fpsMonitor = monitor
        }
    }

    private func stopFPSMonitoring() {
        fpsMonitor?.invalidate()
        fpsMonitor = nil
        fpsValue = 0
        frameTimeMilliseconds = 0
    }
}

// MARK: - Blank area drag to flip pages
extension LaunchpadView {
    private func blankDragGesture(geoSize: CGSize,
                                  columnWidth: CGFloat,
                                  appHeight: CGFloat,
                                  iconSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
            .onChanged { value in
                handleBlankAreaDragChange(value,
                                          geoSize: geoSize,
                                          columnWidth: columnWidth,
                                          appHeight: appHeight,
                                          iconSize: iconSize)
            }
            .onEnded { _ in resetBlankDragState() }
    }

    private func handleBlankAreaDragChange(_ value: DragGesture.Value,
                                           geoSize: CGSize,
                                           columnWidth: CGFloat,
                                           appHeight: CGFloat,
                                           iconSize: CGFloat) {
        guard draggingItem == nil, !isFolderOpen else { return }
        if blankDragConsumed { return }

        if blankDragStartPoint == nil {
            blankDragStartPoint = value.startLocation
            blankDragShouldIgnore = isPointOnInteractiveItem(value.startLocation,
                                                             geoSize: geoSize,
                                                             columnWidth: columnWidth,
                                                             appHeight: appHeight,
                                                             iconSize: iconSize)
            blankDragConsumed = false
        // let ignoreReason = blankDragShouldIgnore ? "hit item" : "blank"
        // print("[Launchpad] blank drag began at \(value.startLocation) -> \(ignoreReason)")
        }

        guard !blankDragShouldIgnore, let start = blankDragStartPoint else { return }

        let translationX = value.location.x - start.x
        let threshold = blankDragThreshold(for: geoSize.width)
        // print("[Launchpad] blank drag change translation=\(translationX), threshold=\(threshold)")

        if translationX <= -threshold {
            navigateToNextPage()
            blankDragStartPoint = value.location
            blankDragConsumed = true
            // print("[Launchpad] blank drag translation \(translationX) <= -\(threshold), flipped to next page")
        } else if translationX >= threshold {
            navigateToPreviousPage()
            blankDragStartPoint = value.location
            blankDragConsumed = true
            // print("[Launchpad] blank drag translation \(translationX) >= \(threshold), flipped to previous page")
        }
    }

    private func blankDragThreshold(for width: CGFloat) -> CGFloat {
        max(width * 0.08, 60)
    }

    private func resetBlankDragState() {
        blankDragStartPoint = nil
        blankDragShouldIgnore = false
        blankDragConsumed = false
    }

    private func isPointOnInteractiveItem(_ point: CGPoint,
                                          geoSize: CGSize,
                                          columnWidth: CGFloat,
                                          appHeight: CGFloat,
                                          iconSize: CGFloat) -> Bool {
        guard let index = indexAt(point: point,
                                  in: geoSize,
                                  pageIndex: appStore.currentPage,
                                  columnWidth: columnWidth,
                                  appHeight: appHeight) else { return false }

        guard currentItems.indices.contains(index) else { return false }
        if case .empty = currentItems[index] { return false }

        let rect = itemInteractiveRect(for: index,
                                       geoSize: geoSize,
                                       columnWidth: columnWidth,
                                       appHeight: appHeight,
                                       iconSize: iconSize)

        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 8
        let hasLabel = appStore.showLabels
        let iconLabelSpacing: CGFloat = hasLabel ? 8 : 0

        let iconRect = CGRect(
            x: rect.midX - iconSize / 2 + 16,
            y: rect.minY + verticalPadding + 16,
            width: iconSize - 32,
            height: iconSize - 32
        ).standardized

        var labelRect = CGRect.null
        if hasLabel {
            let labelTop = iconRect.maxY + iconLabelSpacing
            let labelBottom = rect.maxY - verticalPadding
            let labelHeight = max(0, labelBottom - labelTop)
            labelRect = CGRect(
                x: rect.minX + horizontalPadding + 12,
                y: labelTop,
                width: rect.width - horizontalPadding * 2 - 24,
                height: labelHeight
            ).standardized
        }

        let isIconHit = iconRect.contains(point)
        let isLabelHit = labelRect.contains(point)
        // print("[Launchpad] hit-test at \(point) -> iconRect=\(iconRect), labelRect=\(labelRect), iconHit=\(isIconHit), labelHit=\(isLabelHit)")
        return isIconHit || isLabelHit
    }
}

// MARK: - Tap close helper
extension LaunchpadView {
    fileprivate func closeIfTappedOnEmptyOrGap(at point: CGPoint,
                                               geoSize: CGSize,
                                               columnWidth: CGFloat,
                                               appHeight: CGFloat,
                                               iconSize: CGFloat) {
        guard appStore.openFolder == nil, draggingItem == nil else { return }
        if let idx = indexAt(point: point,
                             in: geoSize,
                             pageIndex: appStore.currentPage,
                             columnWidth: columnWidth,
                             appHeight: appHeight) {
            guard currentItems.indices.contains(idx) else {
                AppDelegate.shared?.hideWindow()
                return
            }

            if case .empty = currentItems[idx] {
                AppDelegate.shared?.hideWindow()
                return
            }

            let interactiveRect = itemInteractiveRect(for: idx,
                                                      geoSize: geoSize,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight,
                                                      iconSize: iconSize)

            if !interactiveRect.contains(point) {
                AppDelegate.shared?.hideWindow()
            }
        } else {
            AppDelegate.shared?.hideWindow()
        }
    }
}

// MARK: - Keyboard Navigation
extension LaunchpadView {
    private func refreshBackgroundImage(reason: BackgroundImageController.RefreshReason) {
        let window = AppDelegate.shared?.launchpadWindow
        backgroundImageController.refresh(
            for: window?.screen ?? NSScreen.main,
            enabled: appStore.backgroundImageEnabled,
            source: appStore.backgroundImageSource,
            customImagePath: appStore.customBackgroundImagePath,
            unfiltered: appStore.launchpadBackgroundStyle == .unfiltered,
            targetSize: appStore.isFullscreenMode ? nil : window?.contentView?.bounds.size,
            reason: reason
        )
    }

    private func setupWindowShownObserver() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        windowObserver = NotificationCenter.default.addObserver(forName: .launchpadWindowShown, object: nil, queue: .main) { _ in
            isWindowVisible = true
            refreshBackgroundImage(reason: .windowShown)
            isKeyboardNavigationActive = false
            selectedIndex = 0
            isSearchFieldFocused = true
            if !appStore.apps.isEmpty {
                appStore.applyOrderAndFolders()
            }
        }
    }
    
    private func setupWindowHiddenObserver() {
        if let observer = windowHiddenObserver {
            NotificationCenter.default.removeObserver(observer)
            windowHiddenObserver = nil
        }
        windowHiddenObserver = NotificationCenter.default.addObserver(forName: .launchpadWindowHidden, object: nil, queue: .main) { _ in
            cancelLegacyItemDrag()
            isWindowVisible = false
            appStore.layoutRevealRequest = nil
            MainActor.assumeIsolated {
                folderPresentation.dismissImmediately()
                backgroundImageController.windowDidHide()
            }
            selectedIndex = 0
        }
    }
    
    private func setupInitialSelection() {
        if selectedIndex == nil, let firstIndex = filteredItems.indices.first {
            selectedIndex = firstIndex
        }
    }

    private func setupKeyHandlers() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if isFolderOpen {
            if event.keyCode == 53 { // esc
                let closingFolder = appStore.openFolder
                withAnimation(LNAnimations.springFast) {
                    appStore.openFolder = nil
                }
                if let folder = closingFolder,
                   let idx = filteredItems.firstIndex(of: .folder(folder)) {
                    isKeyboardNavigationActive = true
                    selectedIndex = idx
                    let targetPage = idx / config.itemsPerPage
                    if targetPage != appStore.currentPage {
                        appStore.currentPage = targetPage
                    }
                }
                // 关闭文件夹后恢复搜索框焦点
                isSearchFieldFocused = true
                return nil
            }
            return event
        }
        
        guard !filteredItems.isEmpty else { return event }
        let code = event.keyCode

        if draggingItem != nil {
            switch code {
            case 123, 124, 125, 126, 48, 36: return nil
            default: return event
            }
        }

        if code == 53 { // esc
            AppDelegate.shared?.hideWindow()
            return nil
        }

        if code == 36 { // return
            if isSearchFieldFocused, isIMEComposing() { return event }

            let trimmedQuery = appStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                if selectedIndex == nil || !(selectedIndex.map { filteredItems.indices.contains($0) } ?? false) {
                    selectedIndex = filteredItems.indices.first
                }
                if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                    isKeyboardNavigationActive = true
                    let sel = filteredItems[idx]
                    if case .folder = sel {
                        appStore.openFolderActivatedByKeyboard = true
                    }
                    handleItemTap(sel)
                    return nil
                }
                return event
            }

            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }

            if let idx = selectedIndex, filteredItems.indices.contains(idx) {
                let sel = filteredItems[idx]
                if case .folder = sel {
                    appStore.openFolderActivatedByKeyboard = true
                }
                handleItemTap(sel)
                return nil
            }
            return event
        }

        if code == 48 { // tab
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }
            // 已激活时保留原有翻页行为（Shift 反向）
            let backward = event.modifierFlags.contains(.shift)
            if backward {
                navigateToPreviousPage()
            } else {
                navigateToNextPage()
            }
            setSelectionToPageStart(appStore.currentPage)
            return nil
        }

        // Shift + 方向键翻页
        if event.modifierFlags.contains(.shift) {
            switch code {
            case 123: // left arrow - 向前翻页
                guard isKeyboardNavigationActive else { return event }
                navigateToPreviousPage()
                setSelectionToPageStart(appStore.currentPage)
                return nil
            case 124: // right arrow - 向后翻页
                guard isKeyboardNavigationActive else { return event }
                navigateToNextPage()
                setSelectionToPageStart(appStore.currentPage)
                return nil
            default:
                break
            }
        }

        if code == 125 { // down arrow activates navigation first
            if isSearchFieldFocused, isIMEComposing() { return event }
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToPageStart(appStore.currentPage)
                clampSelection()
                return nil
            }
            moveSelection(dx: 0, dy: 1)
            return nil
        }

        if code == 126 { // up arrow
            guard isKeyboardNavigationActive else { return event }
            if let idx = selectedIndex {
                let columns = config.columns
                let itemsPerPage = config.itemsPerPage
                let rowInPage = (idx % itemsPerPage) / columns
                if rowInPage == 0 {
                    isKeyboardNavigationActive = false
                    selectedIndex = nil
                    return nil
                }
            }
            moveSelection(dx: 0, dy: -1)
            return nil
        }

        // 普通方向键导航（仅在非Shift状态下）
        if !event.modifierFlags.contains(.shift), let (dx, dy) = arrowDelta(for: code) {
            guard isKeyboardNavigationActive else { return event }
            moveSelection(dx: dx, dy: dy)
            return nil
        }

        return event
    }

    private func moveSelection(dx: Int, dy: Int) {
        guard let current = selectedIndex else { return }
        let columns = config.columns
        let newIndex: Int = dy == 0 ? current + dx : current + dy * columns
        guard filteredItems.indices.contains(newIndex) else { return }
        guard newIndex != current else { return }
        selectedIndex = newIndex
        let item = filteredItems[newIndex]
        SoundManager.shared.play(.navigation)
        VoiceManager.shared.announceSelection(item: item)
        
        let page = newIndex / config.itemsPerPage
        if page != appStore.currentPage {
            navigateToPage(page, animated: true)
        }
    }

    private func setSelectionToPageStart(_ page: Int) {
        let startIndex = page * config.itemsPerPage
        if filteredItems.indices.contains(startIndex) {
            selectedIndex = startIndex
        } else if let last = filteredItems.indices.last {
            selectedIndex = last
        } else {
            selectedIndex = nil
        }
    }

    private func desiredIndexForPageKeepingPosition(targetPage: Int) -> Int? {
        guard let current = selectedIndex else { return nil }
        let columns = config.columns
        let itemsPerPage = config.itemsPerPage
        let currentOffsetInPage = current % itemsPerPage
        let currentRow = currentOffsetInPage / columns
        let currentCol = currentOffsetInPage % columns
        let targetOffset = currentRow * columns + currentCol
        let candidate = targetPage * itemsPerPage + targetOffset

        if filteredItems.indices.contains(candidate) {
            return candidate
        }

        let startOfPage = targetPage * itemsPerPage
        let endExclusive = min((targetPage + 1) * itemsPerPage, filteredItems.count)
        let lastIndexInPage = endExclusive - 1
        return lastIndexInPage >= startOfPage ? lastIndexInPage : nil
    }
}

// MARK: - Key mapping helpers
extension LaunchpadView {
    private func isIMEComposing() -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }
}

// MARK: - View builders
extension LaunchpadView {
    @ViewBuilder
    private func itemDraggable(item: LaunchpadItem,
                               globalIndex: Int,
                               pageIndex: Int,
                               containerSize: CGSize,
                               columnWidth: CGFloat,
                               iconSize: CGFloat,
                               appHeight: CGFloat,
                               labelWidth: CGFloat,
                               isSelected: Bool) -> some View {
        if case .empty = item {
            Rectangle().fill(Color.clear)
                .frame(height: appHeight)
        } else {
            let shouldAllowHover = draggingItem == nil

            let isCenterCreatingTarget: Bool = {
                guard let draggingItem, let idx = currentItems.firstIndex(of: item) else { return false }
                guard case .app = draggingItem else { return false }
                guard appStore.isDragCreatingFolder else { return false }
                switch item {
                case .app(let targetApp):
                    return appStore.folderCreationTarget?.id == targetApp.id
                case .folder:
                    return folderHoverCandidateIndex == idx
                case .missingApp:
                    return false
                case .empty:
                    return false
                }
            }()

            let base = LaunchpadItemButton(
                    item: item,
                    iconSize: iconSize,
                    labelWidth: labelWidth,
                    isSelected: isSelected,
                    showLabel: appStore.showLabels,
                    labelFontSize: CGFloat(appStore.iconLabelFontSize),
                    labelFontWeight: appStore.iconLabelFontWeightValue,
                    shouldAllowHover: shouldAllowHover,
                    externalScale: isCenterCreatingTarget ? 1.2 : nil,
                    hoverMagnificationEnabled: appStore.enableHoverMagnification,
                    hoverMagnificationScale: CGFloat(appStore.hoverMagnificationScale),
                    activePressEffectEnabled: appStore.enableActivePressEffect,
                    activePressScale: CGFloat(appStore.activePressScale),
                    onTap: { if draggingItem == nil { handleItemTap(item) } }
                )
                .frame(height: appHeight)
                // 保持稳定的视图身份，避免在文件夹更新后中断拖拽手势
                .id(item.id)
            if appStore.searchText.isEmpty && !isFolderOpen && !appStore.isLayoutLocked {
                let isDraggingThisTile = (draggingItem == item)

                base
                    .opacity(isDraggingThisTile ? 0 : 1)
                    .allowsHitTesting(!isDraggingThisTile)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("grid"))
                            .onChanged { value in
                                handleDragChange(value, item: item, in: containerSize, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
                            }
                            .onEnded { value in
                                guard draggingItem == item else { return }
                                endLegacyItemDrag(at: value.location)
                            }
                    )
                    .launchNextHideAppContextMenu(app: item.contextMenuApp, folder: item.contextMenuFolder, appStore: appStore)
            } else {
                base
                    .launchNextHideAppContextMenu(app: item.contextMenuApp, folder: item.contextMenuFolder, appStore: appStore)
            }
        }
    }

}

// MARK: - Drag math helpers
extension LaunchpadView {
    private func pageOf(index: Int) -> Int { index / config.itemsPerPage }

    private func cellOrigin(for globalIndex: Int,
                            in containerSize: CGSize,
                            pageIndex: Int,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        let columns = config.columns
        let displayedOffsetInPage: Int = {
            guard pages.indices.contains(pageIndex), currentItems.indices.contains(globalIndex) else {
                return globalIndex % config.itemsPerPage
            }
            let pageItems = pages[pageIndex]
            let item = currentItems[globalIndex]
            return pageItems.firstIndex(of: item) ?? (globalIndex % config.itemsPerPage)
        }()
        
        return GeometryUtils.cellOrigin(for: displayedOffsetInPage,
                                      containerSize: containerSize,
                                      pageIndex: pageIndex,
                                      columnWidth: columnWidth,
                                      appHeight: appHeight,
                                      columns: columns,
                                      columnSpacing: config.columnSpacing,
                                      rowSpacing: config.rowSpacing,
                                      pageSpacing: config.pageSpacing,
                                      currentPage: appStore.currentPage)
    }

    private func cellCenter(for globalIndex: Int,
                            in containerSize: CGSize,
                            pageIndex: Int,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        // Cache geometry to avoid repeating layout math.
        let cacheKey = "center_\(globalIndex)_\(pageIndex)_\(containerSize.width)_\(containerSize.height)_\(columnWidth)_\(appHeight)"
        
        // 检查缓存是否有效
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) < geometryCacheTimeout,
           let cached = Self.geometryCache[cacheKey] {
            return cached
        }
        
        let origin = cellOrigin(for: globalIndex, in: containerSize, pageIndex: pageIndex, columnWidth: columnWidth, appHeight: appHeight)
        let center = CGPoint(x: origin.x + columnWidth / 2, y: origin.y + appHeight / 2)
        
        // Update cache on the next run loop to avoid state writes during layout.
        DispatchQueue.main.async {
            Self.geometryCache[cacheKey] = center
            Self.lastGeometryUpdate = now
        }
        
        return center
    }

    private func indexAt(point: CGPoint,
                         in containerSize: CGSize,
                         pageIndex: Int,
                         columnWidth: CGFloat,
                         appHeight: CGFloat) -> Int? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let pageItems = pages[pageIndex]

        guard let offsetInPage = GeometryUtils.indexAt(point: point,
                                                      containerSize: containerSize,
                                                      pageIndex: pageIndex,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight,
                                                      columns: config.columns,
                                                      columnSpacing: config.columnSpacing,
                                                      rowSpacing: config.rowSpacing,
                                                      pageSpacing: config.pageSpacing,
                                                      currentPage: appStore.currentPage,
                                                      itemsPerPage: config.itemsPerPage,
                                                      pageItems: pageItems) else { return nil }

        let startIndexInCurrentItems = pages.prefix(pageIndex).reduce(0) { $0 + $1.count }
        let globalIndex = startIndexInCurrentItems + offsetInPage
        return currentItems.indices.contains(globalIndex) ? globalIndex : nil
    }

    private func itemInteractiveRect(for globalIndex: Int,
                                      geoSize: CGSize,
                                      columnWidth: CGFloat,
                                      appHeight: CGFloat,
                                      iconSize: CGFloat) -> CGRect {
        let pageIndex = max(0, globalIndex / config.itemsPerPage)
        let localIndex = globalIndex % config.itemsPerPage
        let cellOrigin = GeometryUtils.cellOrigin(for: localIndex,
                                                  containerSize: geoSize,
                                                  pageIndex: pageIndex,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight,
                                                  columns: config.columns,
                                                  columnSpacing: config.columnSpacing,
                                                  rowSpacing: config.rowSpacing,
                                                  pageSpacing: config.pageSpacing,
                                                  currentPage: appStore.currentPage)
        let cellRect = CGRect(x: cellOrigin.x,
                              y: cellOrigin.y,
                              width: columnWidth,
                              height: appHeight)

        // 与 LaunchpadItemButton 中的布局保持一致：按钮内容有 8pt 内边距，图标与标签垂直间距 8pt
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 8
        let labelWidth = columnWidth * 0.9
        let hasLabel = appStore.showLabels
        let iconLabelSpacing: CGFloat = hasLabel ? 8 : 0
        let contentWidth = min(columnWidth, max(iconSize, labelWidth) + horizontalPadding * 2)
        let rawLabelHeight = max(0, appHeight - iconSize - verticalPadding * 2 - iconLabelSpacing)
        let labelHeight = hasLabel ? rawLabelHeight : 0
        let contentHeight = min(appHeight, iconSize + iconLabelSpacing + labelHeight + verticalPadding * 2)

        let insetX = max(0, (columnWidth - contentWidth) / 2)
        let insetY = max(0, (appHeight - contentHeight) / 2)

        return cellRect.insetBy(dx: insetX, dy: insetY)
    }

    private func iconCenter(for globalIndex: Int,
                             geoSize: CGSize,
                             columnWidth: CGFloat,
                             appHeight: CGFloat,
                             iconSize: CGFloat) -> CGPoint {
        let pageIndex = max(0, globalIndex / config.itemsPerPage)
        let localIndex = globalIndex % config.itemsPerPage
        let cellOrigin = GeometryUtils.cellOrigin(for: localIndex,
                                                  containerSize: geoSize,
                                                  pageIndex: pageIndex,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight,
                                                  columns: config.columns,
                                                  columnSpacing: config.columnSpacing,
                                                  rowSpacing: config.rowSpacing,
                                                  pageSpacing: config.pageSpacing,
                                                  currentPage: appStore.currentPage)

        let hasLabel = appStore.showLabels
        let verticalPadding: CGFloat = 8
        let iconLabelSpacing: CGFloat = hasLabel ? 8 : 0
        let contentHeight = iconSize + iconLabelSpacing + (hasLabel ? max(0, appHeight - iconSize - verticalPadding * 2 - iconLabelSpacing) : 0) + verticalPadding * 2
        let insetY = max(0, (appHeight - contentHeight) / 2)

        let iconCenterX = cellOrigin.x + columnWidth / 2
        let iconCenterY = cellOrigin.y + insetY + verticalPadding + iconSize / 2
        return CGPoint(x: iconCenterX, y: iconCenterY)
    }

    private func clampPointWithinBounds(_ point: CGPoint, containerSize: CGSize) -> CGPoint {
        let maxX = max(containerSize.width - 0.1, 0)
        let maxY = max(containerSize.height - 0.1, 0)
        let clampedX = min(max(point.x, 0), maxX)
        let clampedY = min(max(point.y, 0), maxY)
        return CGPoint(x: clampedX, y: clampedY)
    }

    private func isPointInCenterArea(point: CGPoint,
                                      targetIndex: Int,
                                      containerSize: CGSize,
                                      pageIndex: Int,
                                      columnWidth: CGFloat,
                                      appHeight: CGFloat,
                                      iconSize: CGFloat) -> Bool {
        // 性能优化：使用缓存避免重复计算
        let cacheKey = "centerArea_\(targetIndex)_\(pageIndex)_\(containerSize.width)_\(containerSize.height)_\(columnWidth)_\(appHeight)_\(iconSize)"
        
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) < geometryCacheTimeout,
           let cached = Self.geometryCache[cacheKey] {
            let scale = CGFloat(appStore.folderDropZoneScale)
            let centerAreaSize = iconSize * scale
            let centerAreaRect = CGRect(
                x: cached.x - centerAreaSize / 2,
                y: cached.y - centerAreaSize / 2,
                width: centerAreaSize,
                height: centerAreaSize
            )
            return centerAreaRect.contains(point)
        }
        
        let targetCenter = cellCenter(for: targetIndex, in: containerSize, pageIndex: pageIndex, columnWidth: columnWidth, appHeight: appHeight)
        let scale = CGFloat(appStore.folderDropZoneScale)
        let centerAreaSize = iconSize * scale
        let centerAreaRect = CGRect(
            x: targetCenter.x - centerAreaSize / 2,
            y: targetCenter.y - centerAreaSize / 2,
            width: centerAreaSize,
            height: centerAreaSize
        )
        
        // 异步更新缓存，避免在视图更新期间修改状态
        DispatchQueue.main.async {
            Self.geometryCache[cacheKey] = targetCenter
            Self.lastGeometryUpdate = now
        }
        
        return centerAreaRect.contains(point)
    }
}

// MARK: - Scroll handling (mouse wheel and trackpad)
extension LaunchpadView {
    private func rubberbandOffset(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let factor: CGFloat = 0.5
        let distance = abs(value)
        let scaled = (factor * distance) / (distance + limit)
        return scaled * (value >= 0 ? 1 : -1) * limit
    }

    private func handleWheelScroll(_ primaryDelta: CGFloat) {
        if primaryDelta == 0 { return }
        let direction = primaryDelta > 0 ? 1 : -1
        if scrollState.wheelLastDirection != direction { scrollState.wheelAccumulated = 0 }
        scrollState.wheelLastDirection = direction
        scrollState.wheelAccumulated += abs(primaryDelta)
        let baselineSensitivity = max(AppStore.defaultScrollSensitivity, 0.0001)
        let relativeSensitivity = max(appStore.scrollSensitivity, 0.0001) / baselineSensitivity
        // Scale wheel threshold by sensitivity.
        let threshold: CGFloat = 2.0 / CGFloat(relativeSensitivity)
        let now = Date()
        if scrollState.wheelAccumulated >= threshold {
            if let last = scrollState.wheelLastFlipAt, now.timeIntervalSince(last) < wheelFlipCooldown { return }
            if direction > 0 { navigateToNextPage() } else { navigateToPreviousPage() }
            scrollState.wheelLastFlipAt = now
            // Reset so one tick flips at most once.
            scrollState.wheelAccumulated = 0
        }
    }

    private func flipThreshold(_ pageWidth: CGFloat) -> CGFloat {
        let baseline = max(AppStore.defaultScrollSensitivity, 0.001)
        return pageWidth * ((baseline * baseline) / max(appStore.scrollSensitivity, 0.001))
    }

    private func resetFollowOffset(animated: Bool) {
        guard scrollState.followOffset != 0 else { return }
        if animated && appStore.enableAnimations {
            withAnimation(LNAnimations.springFast) { scrollState.followOffset = 0 }
        } else {
            scrollState.followOffset = 0
        }
    }

    private func handleScroll(deltaX: CGFloat,
                              deltaY: CGFloat,
                              phase: NSEvent.Phase,
                              isMomentum: Bool,
                              isPrecise: Bool,
                              pageWidth: CGFloat) {
        guard !isFolderOpen else { return }

        let verticalDelta = isPrecise ? deltaY : -deltaY
        let primaryDelta = abs(deltaX) >= abs(deltaY) ? deltaX : verticalDelta

        // Non-precise wheel: accumulate deltas and apply a short cooldown.
        if !isPrecise {
            handleWheelScroll(primaryDelta)
            return
        }

        // Drag-like page tracking while scrolling, then settle.
        if phase == [] {
            handleWheelScroll(primaryDelta)
            return
        }
        if isMomentum && phase != .ended && phase != .cancelled { return }
        // Treat vertical input as horizontal paging.
        let delta = primaryDelta
        switch phase {
        case .began:
            scrollState.isUserSwiping = true
            scrollState.accumulatedX = 0
            scrollState.followOffset = 0
            scrollState.followLastUpdateAt = 0
            scrollState.followLastOffset = 0
        case .changed:
            scrollState.isUserSwiping = true
            scrollState.accumulatedX += delta
            var proposed = scrollState.accumulatedX
            let atFirstPage = appStore.currentPage <= 0
            let atLastPage = appStore.currentPage >= max(pages.count - 1, 0)
            if atFirstPage && proposed > 0 {
                proposed = rubberbandOffset(proposed, limit: pageWidth)
            } else if atLastPage && proposed < 0 {
                proposed = rubberbandOffset(proposed, limit: pageWidth)
            } else {
                let maxOffset = pageWidth * 0.95
                proposed = max(-maxOffset, min(maxOffset, proposed))
            }
            let now = CFAbsoluteTimeGetCurrent()
            let minInterval = 1.0 / 90.0
            let minDelta: CGFloat = 0.6
            if abs(proposed - scrollState.followLastOffset) >= minDelta || (now - scrollState.followLastUpdateAt) >= minInterval {
                scrollState.followOffset = proposed
                scrollState.followLastUpdateAt = now
                scrollState.followLastOffset = proposed
            }
        case .ended, .cancelled:
            let threshold = flipThreshold(pageWidth)
            if scrollState.accumulatedX <= -threshold {
                navigateToNextPage()
            } else if scrollState.accumulatedX >= threshold {
                navigateToPreviousPage()
            }
            resetFollowOffset(animated: true)
            scrollState.accumulatedX = 0
            scrollState.isUserSwiping = false
            scrollState.followLastUpdateAt = 0
            scrollState.followLastOffset = 0
        default:
            break
        }
    }
}

// MARK: - AppKit Scroll catcher
struct ScrollEventCatcher: NSViewRepresentable {
    typealias NSViewType = ScrollEventCatcherView
    let onScroll: (CGFloat, CGFloat, NSEvent.Phase, Bool, Bool) -> Void

    func makeNSView(context: Context) -> ScrollEventCatcherView {
        let view = ScrollEventCatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollEventCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollEventCatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat, NSEvent.Phase, Bool, Bool) -> Void)?
        private var eventMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            // Prefer primary phase; fallback to momentum
            let phase = event.phase != [] ? event.phase : event.momentumPhase
            let isMomentum = event.momentumPhase != []
            let isPreciseOrTrackpad = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
            onScroll?(event.scrollingDeltaX,
                      event.scrollingDeltaY,
                      phase,
                      isMomentum,
                      isPreciseOrTrackpad)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
            // 全局监听当前窗口的滚动事件，不消费事件
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                let phase = event.phase != [] ? event.phase : event.momentumPhase
                let isMomentum = event.momentumPhase != []
                let isPreciseOrTrackpad = event.hasPreciseScrollingDeltas || event.phase != [] || event.momentumPhase != []
                self?.onScroll?(event.scrollingDeltaX,
                                event.scrollingDeltaY,
                                phase,
                                isMomentum,
                                isPreciseOrTrackpad)
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // 不拦截命中测试，让下层视图处理点击/拖拽等
            return nil
        }

        deinit {
            if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// MARK: - Drag preview view


// MARK: - Selection Helpers
extension LaunchpadView {
    private func clampSelection() {
        guard isKeyboardNavigationActive else { return }
        let count = filteredItems.count
        if count == 0 {
            selectedIndex = nil
            return
        }
        if let idx = selectedIndex {
            if idx >= count { selectedIndex = count - 1 }
            if idx < 0 { selectedIndex = 0 }
        } else {
            selectedIndex = 0
        }
        
        if let idx = selectedIndex, filteredItems.indices.contains(idx) {
            let page = idx / config.itemsPerPage
            if page != appStore.currentPage {
                navigateToPage(page, animated: true)
            }
        } else {
            selectedIndex = filteredItems.isEmpty ? nil : 0
        }
    }
}

// MARK: - Geometry & Drag helpers
extension LaunchpadView {
    fileprivate func captureGridGeometry(_ geo: GeometryProxy, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        gridOriginInWindow = geo.frame(in: .global).origin
        currentContainerSize = geo.size
        currentColumnWidth = columnWidth
        currentAppHeight = appHeight
        currentIconSize = iconSize
        
        // 性能优化：清理过期的几何缓存
        let now = Date()
        if now.timeIntervalSince(Self.lastGeometryUpdate) > geometryCacheTimeout * 2 {
            // 异步清理缓存，避免在视图更新期间修改状态
            DispatchQueue.main.async {
                Self.geometryCache.removeAll()
                Self.lastGeometryUpdate = now
            }
        }
    }

    fileprivate func flipPageIfNeeded(iconCenter: CGPoint,
                                      pointer: CGPoint,
                                      iconSize: CGFloat,
                                      in containerSize: CGSize) -> Bool {
        let edgeMargin: CGFloat = config.pageNavigation.edgeFlipMargin
        
        // 检查翻页冷却状态
        pageFlipManager.autoFlipInterval = config.pageNavigation.autoFlipInterval
        guard pageFlipManager.canFlip() else { return false }

        let verticalTolerance = max(iconSize * 0.8, 60)
        if pointer.y < -verticalTolerance || pointer.y > containerSize.height + verticalTolerance {
            return false
        }
                
        if iconCenter.x <= edgeMargin && appStore.currentPage > 0 {
            navigateToPreviousPage()
            pageFlipManager.recordFlip()
            return true
        } else if iconCenter.x >= containerSize.width - edgeMargin {
            // 检查是否需要创建新页面
            let nextPage = appStore.currentPage + 1
            let itemsPerPage = config.itemsPerPage
            let nextPageStart = nextPage * itemsPerPage
            
            // 如果拖拽到新页面，确保有足够的空间
            if nextPageStart >= currentItems.count {
                let neededItems = nextPageStart + itemsPerPage - currentItems.count
                for _ in 0..<neededItems {
                    appStore.items.append(.empty(UUID().uuidString))
                }
            }
            
            navigateToNextPage()
            pageFlipManager.recordFlip()
            return true
        }
        
        return false
    }

    fileprivate func predictedDropIndex(for pointer: CGPoint, in containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat) -> Int? {
        let queryPoint = appStore.enableDropPrediction
            ? clampPointWithinBounds(pointer, containerSize: containerSize)
            : pointer

        if let predicted = indexAt(point: queryPoint,
                                   in: containerSize,
                                   pageIndex: appStore.currentPage,
                                   columnWidth: columnWidth,
                                   appHeight: appHeight) {
            return predicted
        }
        
        let edgeMargin: CGFloat = config.pageNavigation.edgeFlipMargin
        let itemsPerPage = config.itemsPerPage
        
        if queryPoint.x <= edgeMargin && appStore.currentPage > 0 {
            let prevPage = appStore.currentPage - 1
            let prevPageStart = prevPage * itemsPerPage
            let prevPageEnd = min(prevPageStart + itemsPerPage, currentItems.count)
            return max(prevPageStart, prevPageEnd - 1)
        } else if queryPoint.x >= containerSize.width - edgeMargin {
            let nextPage = appStore.currentPage + 1
            let nextPageStart = nextPage * itemsPerPage

            // 如果拖拽到新页面，确保能够正确预测到新页面的第一个位置
            if nextPageStart >= currentItems.count {
                // 拖拽到全新页面，返回新页面的第一个位置
                return nextPageStart
            } else {
                return min(nextPageStart, currentItems.count - 1)
            }
        } else {
            if queryPoint.x <= edgeMargin {
                return appStore.currentPage * itemsPerPage
            } else {
                let currentPageEnd = min((appStore.currentPage + 1) * itemsPerPage, currentItems.count)
                return max(appStore.currentPage * itemsPerPage, currentPageEnd - 1)
            }
        }
    }
}

struct GridConfig {
    let isFullscreen: Bool
    private let columnCount: Int
    private let rowCount: Int
    private let columnSpacingValue: CGFloat
    private let rowSpacingValue: CGFloat

    init(isFullscreen: Bool = false,
         columns: Int = 7,
         rows: Int = 5,
         columnSpacing: CGFloat = 20,
         rowSpacing: CGFloat = 14) {
        self.isFullscreen = isFullscreen
        self.columnCount = max(1, columns)
        self.rowCount = max(1, rows)
        self.columnSpacingValue = max(0, columnSpacing)
        self.rowSpacingValue = max(0, rowSpacing)
    }

    var itemsPerPage: Int { columnCount * rowCount }
    var columns: Int { columnCount }
    var rows: Int { rowCount }
    var columnSpacing: CGFloat { columnSpacingValue }
    var rowSpacing: CGFloat { rowSpacingValue }

    let maxBounce: CGFloat = 80
    let pageSpacing: CGFloat = 80

    struct PageNavigation {
        let edgeFlipMargin: CGFloat = 48
        let autoFlipInterval: TimeInterval = 0.55 // 拖拽贴边时稍快响应，同时避免连续误翻
        let scrollPageThreshold: CGFloat = 0.75
        let scrollFinishThreshold: CGFloat = 0.5
    }
    
    let pageNavigation = PageNavigation()
    let folderCreateDwell: TimeInterval = 0
    
    var horizontalPadding: CGFloat { isFullscreen ? 0.04 : 0 }
    var topPadding: CGFloat { isFullscreen ? 0.035 : 0 }
    var bottomPadding: CGFloat { isFullscreen ? 0.06 : 0 }
    
    var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: columns)
    }
}
 

//

struct DragPreviewItem: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let labelWidth: CGFloat
    var scale: CGFloat = 1.2

    // 性能优化：使用计算属性避免状态修改
    private var displayIcon: NSImage {
        switch item {
        case .app(let app):
            let pathExists = FileManager.default.fileExists(atPath: app.url.path)
            let icon = IconStore.shared.icon(for: app)
            if pathExists && icon.size.width > 0 && icon.size.height > 0 {
                return icon
            }
            return MissingAppPlaceholder.defaultIcon
        case .missingApp(let placeholder):
            let pathExists = FileManager.default.fileExists(atPath: placeholder.bundlePath)
            let icon = placeholder.icon
            if pathExists && icon.size.width > 0 && icon.size.height > 0 {
                return icon
            }
            return MissingAppPlaceholder.defaultIcon
        case .folder(let folder):
            return folder.icon(of: iconSize)
        case .empty:
            return item.icon
        }
    }

    private var isMissing: Bool {
        switch item {
        case .missingApp:
            return true
        case .app(let app):
            return !FileManager.default.fileExists(atPath: app.url.path)
        default:
            return false
        }
    }

    var body: some View {
        switch item {
        case .app(let app):
            VStack(spacing: 6) {
                Image(nsImage: displayIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(isMissing ? 0.65 : 1.0)
                    .overlay(alignment: .topTrailing) {
                        if isMissing {
                            Circle()
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: iconSize * 0.22, height: iconSize * 0.22)
                                .overlay(
                                    Image(systemName: "exclamationmark")
                                        .font(.system(size: iconSize * 0.14, weight: .bold))
                                        .foregroundStyle(Color.white)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(iconSize * 0.1)
                        }
                    }
                Text(app.name)
                    .font(.default)
                    .foregroundColor(isMissing ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)

        case .missingApp(let placeholder):
            VStack(spacing: 6) {
                Image(nsImage: displayIcon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(0.65)
                    .overlay(
                        Circle()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: iconSize * 0.22, height: iconSize * 0.22)
                            .overlay(
                                Image(systemName: "exclamationmark")
                                    .font(.system(size: iconSize * 0.14, weight: .bold))
                                    .foregroundStyle(Color.white)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(iconSize * 0.1)
                    )
                Text(placeholder.displayName)
                    .font(.default)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)

        case .folder(let folder):
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .foregroundStyle(Color.clear)
                        .frame(width: iconSize * 0.8, height: iconSize * 0.8)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: iconSize * 0.2))
                        .shadow(radius: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: iconSize * 0.2)
                                .stroke(Color.launchpadBorder.opacity(0.5), lineWidth: 1)
                        )
                    Image(nsImage: folder.icon(of: iconSize))
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: iconSize, height: iconSize)
                }
                
                Text(folder.name)
                    .font(.default)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: labelWidth)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .scaleEffect(scale)
            .animation(LNAnimations.springFast, value: scale)
            
        case .empty:
            EmptyView()
        }
    }
}

func arrowDelta(for keyCode: UInt16) -> (dx: Int, dy: Int)? {
    switch keyCode {
    case 123: return (-1, 0) // left
    case 124: return (1, 0)  // right
    case 126: return (0, -1) // up
    case 125: return (0, 1)  // down
    default: return nil
    }
}

// MARK: - 缓存管理扩展

extension LaunchpadView {
    /// 检查缓存状态
    private func checkCacheStatus() {
        // 如果缓存无效，触发重新扫描
        if !AppCacheManager.shared.isCacheValid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.appStore.performInitialScanIfNeeded()
            }
        }
    }
    
    // MARK: - 简化的拖拽处理函数
    private func handleDragChange(_ value: DragGesture.Value, item: LaunchpadItem, in containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        guard !appStore.useCAGridRenderer, !appStore.isLayoutLocked,
              appStore.searchText.isEmpty, !isFolderOpen,
              legacyItemDragSession?.isEnding != true else { return }
        // 初始化拖拽
        if draggingItem == nil {
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { draggingItem = item }
            isKeyboardNavigationActive = false
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil

            if let idx = filteredItems.firstIndex(of: item) {
                let center = iconCenter(for: idx,
                                         geoSize: containerSize,
                                         columnWidth: columnWidth,
                                         appHeight: appHeight,
                                         iconSize: iconSize)
                dragPointerOffset = CGPoint(x: value.location.x - center.x,
                                             y: value.location.y - center.y)
                dragPreviewPosition = center
            } else {
                dragPointerOffset = .zero
                dragPreviewPosition = value.location
            }
            startLegacyItemDragMonitoring()
        }
        guard draggingItem == item, let session = legacyItemDragSession,
              !session.usesMouseMonitor else { return }
        session.lastGestureUpdate = ProcessInfo.processInfo.systemUptime
        applyDragUpdate(at: value.location,
                        containerSize: containerSize,
                        columnWidth: columnWidth,
                        appHeight: appHeight,
                        iconSize: iconSize)
    }

    private func startLegacyItemDragMonitoring() {
        let session = LegacyItemDragSession(window: NSApp.currentEvent?.window ?? NSApp.keyWindow)
        legacyItemDragSession = session
        session.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak session] event in
            guard let session, legacyItemDragSession === session, !session.isEnding else { return event }
            guard !appStore.useCAGridRenderer, !appStore.isLayoutLocked else {
                cancelLegacyItemDrag()
                return event
            }
            guard let window = session.window else {
                cancelLegacyItemDrag()
                return event
            }
            // Local monitors see events for every app window. Only this window owns the drag.
            guard event.window === window else { return event }
            let point = CGPoint(x: event.locationInWindow.x - gridOriginInWindow.x,
                                y: (window.contentView?.bounds.height ?? window.frame.height)
                                    - event.locationInWindow.y - gridOriginInWindow.y)
            if event.type == .leftMouseUp {
                endLegacyItemDrag(at: point)
            } else if session.usesMouseMonitor
                        || ProcessInfo.processInfo.systemUptime - session.lastGestureUpdate > 0.1 {
                session.usesMouseMonitor = true
                handleHandoffDragMove(to: point)
            }
            // Keep AppKit/SwiftUI's mouse sequence balanced, including its normal onEnded.
            return event
        }
    }

    private func endLegacyItemDrag(at point: CGPoint? = nil) {
        guard let session = legacyItemDragSession, !session.isEnding, draggingItem != nil else { return }
        guard !appStore.useCAGridRenderer, !appStore.isLayoutLocked else {
            cancelLegacyItemDrag()
            return
        }
        // The monitor runs before onEnded; claim completion before changing the layout.
        session.isEnding = true
        session.stopMonitoring()
        if let point {
            applyDragUpdate(at: point, containerSize: currentContainerSize,
                            columnWidth: currentColumnWidth, appHeight: currentAppHeight,
                            iconSize: currentIconSize, isFinalUpdate: true)
        }
        finalizeDragOperation(containerSize: currentContainerSize, columnWidth: currentColumnWidth,
                              appHeight: currentAppHeight, iconSize: currentIconSize)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            // A cancelled drag's delayed cleanup must not clear a subsequent drag.
            guard legacyItemDragSession === session else { return }
            clearLegacyItemDrag(session)
            appStore.cleanupUnusedNewPage()
            appStore.removeEmptyPages()
            appStore.saveAllOrder()
        }
    }

    private func cancelLegacyItemDrag() {
        guard let session = legacyItemDragSession else { return }
        clearLegacyItemDrag(session)
        appStore.cleanupUnusedNewPage()
        appStore.removeEmptyPages()
    }

    private func clearLegacyItemDrag(_ session: LegacyItemDragSession) {
        session.isEnding = true
        session.stopMonitoring()
        legacyItemDragSession = nil
        draggingItem = nil
        pendingDropIndex = nil
        dragPointerOffset = .zero
        dragPreviewScale = 1.2
        clearHoveringState()
        pageFlipManager.isCooldown = false
        blankDragStartPoint = nil
        blankDragShouldIgnore = false
        blankDragConsumed = false
        displayedGridRefreshID = appStore.gridRefreshTrigger
        clampSelection()
    }

    // 统一的拖拽结束处理逻辑（普通拖拽与接力拖拽共用）
    private func finalizeDragOperation(containerSize: CGSize, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        guard let dragging = draggingItem else { return }
        defer { dragPointerOffset = .zero }

        if appStore.isLayoutLocked {
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            pendingDropIndex = nil
            return
        }

        // 处理文件夹创建逻辑
        if appStore.isDragCreatingFolder, case .app(let app) = dragging {
            if let targetApp = appStore.folderCreationTarget {
                if let insertAt = filteredItems.firstIndex(of: .app(targetApp)) {
                    let newFolder = appStore.createFolder(with: [app, targetApp], insertAt: insertAt)
                    if let folderIndex = filteredItems.firstIndex(of: .folder(newFolder)) {
                        let targetCenter = cellCenter(for: folderIndex,
                                                      in: containerSize,
                                                      pageIndex: appStore.currentPage,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight)
                        withAnimation(LNAnimations.springFast) {
                            dragPreviewPosition = targetCenter
                            dragPreviewScale = 1.0
                        }
                    }
                } else {
                    let newFolder = appStore.createFolder(with: [app, targetApp])
                    if let folderIndex = filteredItems.firstIndex(of: .folder(newFolder)) {
                        let targetCenter = cellCenter(for: folderIndex,
                                                      in: containerSize,
                                                      pageIndex: appStore.currentPage,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight)
                        withAnimation(LNAnimations.springFast) {
                            dragPreviewPosition = targetCenter
                            dragPreviewScale = 1.0
                        }
                    }
                }
            } else {
                let pointerPoint = dragPreviewPosition
                if let hoveringIndex = indexAt(point: pointerPoint,
                                               in: containerSize,
                                               pageIndex: appStore.currentPage,
                                               columnWidth: columnWidth,
                                               appHeight: appHeight),
                   filteredItems.indices.contains(hoveringIndex),
                   case .folder(let folder) = filteredItems[hoveringIndex] {
                    appStore.addAppToFolder(app, folder: folder)
                    let targetCenter = cellCenter(for: hoveringIndex,
                                                  in: containerSize,
                                                  pageIndex: appStore.currentPage,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight)
                    withAnimation(LNAnimations.springFast) {
                        dragPreviewPosition = targetCenter
                        dragPreviewScale = 1.0
                    }
                }
            }
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            return
        }
        
        // 处理普通拖拽逻辑
        if let finalIndex = pendingDropIndex,
           let _ = filteredItems.firstIndex(of: dragging) {
            // 检查是否为跨页拖拽
            let sourceIndexInItems = appStore.items.firstIndex(of: dragging) ?? 0
            let targetPage = finalIndex / config.itemsPerPage
            let sourcePage = sourceIndexInItems / config.itemsPerPage
            
            // 视觉吸附到目标格中心
            let dropDisplayIndex = finalIndex
            let finalPage = pageOf(index: dropDisplayIndex)
            let targetCenter = cellCenter(for: dropDisplayIndex,
                                          in: containerSize,
                                          pageIndex: finalPage,
                                          columnWidth: columnWidth,
                                          appHeight: appHeight)
            withAnimation(LNAnimations.springFast) {
                dragPreviewPosition = targetCenter
                dragPreviewScale = 1.0
            }
            
            if targetPage == sourcePage {
                // 同页内移动：使用原有的页内排序逻辑
                let pageStart = (finalIndex / config.itemsPerPage) * config.itemsPerPage
                let pageEnd = min(pageStart + config.itemsPerPage, appStore.items.count)
                var newItems = appStore.items
                var pageSlice = Array(newItems[pageStart..<pageEnd])
                let localFrom = sourceIndexInItems - pageStart
                let moving = pageSlice.remove(at: localFrom)
                let desiredLocal = max(0, finalIndex - pageStart)
                let clampedLocal = min(desiredLocal, pageSlice.count)
                pageSlice.insert(moving, at: clampedLocal)
                newItems.replaceSubrange(pageStart..<pageEnd, with: pageSlice)
                withAnimation(LNAnimations.springFast) {
                    appStore.items = newItems
                }
                appStore.triggerGridRefresh()
                appStore.saveAllOrder()
                
                // 同页内拖拽结束后也进行压缩，确保empty项目移动到页面末尾
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appStore.compactItemsWithinPages()
                }
            } else {
                // 跨页拖拽：使用级联插入逻辑
                appStore.moveItemAcrossPagesWithCascade(item: dragging, to: finalIndex)
            }
        } else {
            // 兜底逻辑：如果没有有效的目标索引，将应用放置到当前页的末尾
            if filteredItems.contains(dragging) {
                let currentPageStart = appStore.currentPage * config.itemsPerPage
                let currentPageEnd = min(currentPageStart + config.itemsPerPage, appStore.items.count)
                let targetIndex = currentPageEnd
                
                // 使用级联插入确保应用能正确放置
                appStore.moveItemAcrossPagesWithCascade(item: dragging, to: targetIndex)
            }
        }
    }

    // 统一的拖拽更新逻辑（普通拖拽与接力拖拽共用）
    private func applyDragUpdate(at point: CGPoint,
                                 containerSize: CGSize,
                                 columnWidth: CGFloat,
                                 appHeight: CGFloat,
                                 iconSize: CGFloat,
                                 isFinalUpdate: Bool = false) {
        guard !appStore.isLayoutLocked else { return }
        let rawIconCenter = CGPoint(x: point.x - dragPointerOffset.x,
                                     y: point.y - dragPointerOffset.y)
        var iconCenter = rawIconCenter
        var hoverPoint = rawIconCenter
        if appStore.enableDropPrediction {
            let clamped = clampPointWithinBounds(rawIconCenter, containerSize: containerSize)
            iconCenter = clamped
            hoverPoint = clamped
        }
        // 性能优化：减少频繁的位置更新
        let distance = sqrt(pow(dragPreviewPosition.x - iconCenter.x, 2) + pow(dragPreviewPosition.y - iconCenter.y, 2))
        if !isFinalUpdate && distance < 2.0 { return } // 如果移动距离小于2像素，跳过更新

        dragPreviewPosition = iconCenter
        
        // 性能优化：使用节流机制减少计算频率
        let now = Date()
        if !isFinalUpdate && now.timeIntervalSince(Self.lastGeometryUpdate) < 0.016 { // 约60fps
            return
        }
        
        Self.lastGeometryUpdate = now
        
        if let hoveringIndex = indexAt(point: hoverPoint,
                                       in: containerSize,
                                       pageIndex: appStore.currentPage,
                                       columnWidth: columnWidth,
                                       appHeight: appHeight),
           currentItems.indices.contains(hoveringIndex) {
            handleHoveringLogic(hoveringIndex: hoveringIndex, columnWidth: columnWidth, appHeight: appHeight, iconSize: iconSize)
        } else {
            clearHoveringState()
        }

        if !isFinalUpdate && flipPageIfNeeded(iconCenter: iconCenter,
                            pointer: point,
                            iconSize: iconSize,
                            in: containerSize) {
            let dropPoint = appStore.enableDropPrediction ? iconCenter : point
            pendingDropIndex = predictedDropIndex(for: dropPoint,
                                                  in: containerSize,
                                                  columnWidth: columnWidth,
                                                  appHeight: appHeight)
        }
    }
    
    private func handleHoveringLogic(hoveringIndex: Int, columnWidth: CGFloat, appHeight: CGFloat, iconSize: CGFloat) {
        let hoveringItem = currentItems[hoveringIndex]
        guard pageOf(index: hoveringIndex) == appStore.currentPage else {
            clearHoveringState()
            return
        }

        let pointerPoint = dragPreviewPosition
        let isInCenterArea = isPointInCenterArea(
            point: pointerPoint,
            targetIndex: hoveringIndex,
            containerSize: currentContainerSize,
            pageIndex: appStore.currentPage,
            columnWidth: columnWidth,
            appHeight: appHeight,
            iconSize: iconSize
        )

        guard let dragging = draggingItem else { return }

        switch hoveringItem {
        case .app(let targetApp):
            handleAppHover(dragging: dragging, targetApp: targetApp, hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea)
        case .missingApp(let placeholder):
            handleMissingHover(dragging: dragging,
                                placeholder: placeholder,
                                hoveringIndex: hoveringIndex,
                                isInCenterArea: isInCenterArea)
        case .folder(_):
            handleFolderHover(dragging: dragging, hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea)
        case .empty:
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
            pendingDropIndex = hoveringIndex
        }
    }

    private func handleAppHover(dragging: LaunchpadItem, targetApp: AppInfo, hoveringIndex: Int, isInCenterArea: Bool) {
        if dragging == .app(targetApp) {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        } else if case .app = dragging {
            handleAppToAppHover(hoveringIndex: hoveringIndex, isInCenterArea: isInCenterArea, targetApp: targetApp)
        } else {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        }
    }

    private func handleMissingHover(dragging: LaunchpadItem,
                                     placeholder: MissingAppPlaceholder,
                                     hoveringIndex: Int,
                                     isInCenterArea: Bool) {
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        if case .missingApp(let draggingPlaceholder) = dragging,
           draggingPlaceholder.id == placeholder.id {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        } else {
            pendingDropIndex = hoveringIndex
        }
    }
    
    private func handleAppToAppHover(hoveringIndex: Int, isInCenterArea: Bool, targetApp: AppInfo) {
        let now = Date()
        let candidateChanged = folderHoverCandidateIndex != hoveringIndex || !isInCenterArea
        
        if candidateChanged {
            folderHoverCandidateIndex = isInCenterArea ? hoveringIndex : nil
            folderHoverBeganAt = isInCenterArea ? now : nil
            appStore.isDragCreatingFolder = false
            appStore.folderCreationTarget = nil
        }
        
        if isInCenterArea {
            appStore.isDragCreatingFolder = true
            appStore.folderCreationTarget = targetApp
            pendingDropIndex = nil
        } else {
            if !isInCenterArea || folderHoverCandidateIndex == nil {
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
                pendingDropIndex = hoveringIndex
            } else {
                pendingDropIndex = nil
            }
        }
    }
    
    private func handleFolderHover(dragging: LaunchpadItem, hoveringIndex: Int, isInCenterArea: Bool) {
        if case .app = dragging {
            let now = Date()
            let candidateChanged = folderHoverCandidateIndex != hoveringIndex || !isInCenterArea
            
            if candidateChanged {
                folderHoverCandidateIndex = isInCenterArea ? hoveringIndex : nil
                folderHoverBeganAt = isInCenterArea ? now : nil
                appStore.isDragCreatingFolder = false
                appStore.folderCreationTarget = nil
            }
            
            if isInCenterArea {
                appStore.isDragCreatingFolder = true
                appStore.folderCreationTarget = nil
                pendingDropIndex = nil
            } else {
                if !isInCenterArea || folderHoverCandidateIndex == nil {
                    appStore.isDragCreatingFolder = false
                    appStore.folderCreationTarget = nil
                    pendingDropIndex = hoveringIndex
                } else {
                    pendingDropIndex = nil
                }
            }
        } else {
            clearHoveringState()
            pendingDropIndex = hoveringIndex
        }
    }
    
    private func clearHoveringState() {
        appStore.isDragCreatingFolder = false
        appStore.folderCreationTarget = nil
        pendingDropIndex = nil
        folderHoverCandidateIndex = nil
        folderHoverBeganAt = nil
    }
    
    // 性能监控辅助函数
    private func measurePerformance<T>(_ operation: String, _ block: () -> T) -> T {
        guard enablePerformanceMonitoring else { return block() }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        performanceMetrics[operation] = timeElapsed
        if timeElapsed > 0.016 { // 超过16ms（60fps阈值）
            print("⚠️ 性能警告: \(operation) 耗时 \(String(format: "%.3f", timeElapsed * 1000))ms")
        }
        
        return result
    }
}
