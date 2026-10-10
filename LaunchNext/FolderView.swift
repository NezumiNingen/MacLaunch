import SwiftUI
import AppKit
import Combine

struct FolderView: View {
    @ObservedObject var appStore: AppStore
    @Binding var folder: FolderInfo
    // 若提供，将强制使用与外层一致的图标尺寸
    var preferredIconSize: CGFloat? = nil
    var presentationState: CAFolderPresentationState? = nil
    var labelColorOverride: NSColor? = nil
    var labelShadow: BackgroundLabelContrast.Shadow = .none
    var initialRevealAppPath: String? = nil
    @State private var folderName: String = ""
    @State private var isEditingName = false
    @State private var forceRefreshTrigger: UUID = UUID()
    @State private var folderCurrentPage: Int = 0
    @State private var folderPageCount: Int = 1
    @State private var fallbackItemsPerPage: Int = 30
    @State private var fallbackScrollPosition: Int? = 0
    @FocusState private var isTextFieldFocused: Bool
    // 键盘导航
    @State private var selectedIndex: Int? = nil
    @State private var isKeyboardNavigationActive: Bool = false
    @State private var keyMonitor: Any?
    // 拖拽相关状态
    @State private var draggingApp: AppInfo? = nil
    @State private var dragPreviewPosition: CGPoint = .zero
    @State private var dragPreviewScale: CGFloat = 1.2
    @State private var pendingDropIndex: Int? = nil
    @State private var outOfBoundsBeganAt: Date? = nil
    @State private var hasHandedOffDrag: Bool = false
    private let outOfBoundsDwell: TimeInterval = 0.0
    
    let onClose: () -> Void
    let onLaunchApp: (AppInfo) -> Void

    private func canLaunch(_ app: AppInfo) -> Bool {
        FileManager.default.fileExists(atPath: app.url.path)
    }
    
    // Layout metrics scale with the current display instead of inheriting fixed row/column counts.
    private var uiScale: CGFloat { LaunchpadUIMetrics.overallScale }
    private var spacing: CGFloat { 30 * uiScale }
    @State private var columnsCount: Int = 6
    private var gridPadding: CGFloat { 16 * uiScale }
    private var titlePadding: CGFloat { 16 * uiScale }
    private var folderTitleHeight: CGFloat { 72 * uiScale }

    private var visualApps: [AppInfo] {
        guard let dragging = draggingApp, let pending = pendingDropIndex else { return folder.apps }
        var apps = folder.apps
        if let from = apps.firstIndex(of: dragging) {
            apps.remove(at: from)
            let insertIndex = pending
            let clamped = min(max(0, insertIndex), apps.count)
            apps.insert(dragging, at: clamped)
        }
        return apps
    }
    
    var body: some View {
        folderContent
        .padding(8 * uiScale)
        .modifier(FolderSurfaceModifier(isNativePresentation: presentationState != nil))
        .onTapGesture {
            // 当点击文件夹视图的非编辑区域时，如果正在编辑名称，则退出编辑模式
            if isEditingName {
                finishEditing()
            }
        }
        .onAppear {
            resetFolderPagingState()
            folderName = folder.name
            setupKeyHandlers()
            setupInitialSelection()
            // 如果是通过回车键打开的文件夹，则自动启用导航并选中第一项
            if appStore.openFolderActivatedByKeyboard {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                appStore.openFolderActivatedByKeyboard = false
            } else {
                isKeyboardNavigationActive = false
            }
            if let path = initialRevealAppPath,
               let index = folder.apps.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
                selectedIndex = index
                isKeyboardNavigationActive = false
            }
            consumeRenameRequestIfNeeded()
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if !focused && isEditingName {
                finishEditing()
            }
        }
        .onChange(of: folder.apps) {
            clampSelection()
            // 当应用列表变化时，强制刷新视图
            forceRefreshTrigger = UUID()
        }
        .onChange(of: folder.id) {
            resetFolderPagingState()
        }
        .onChange(of: selectedIndex) { _, index in
            guard !appStore.useCAGridRenderer,
                  let index,
                  fallbackItemsPerPage > 0 else { return }
            let page = index / fallbackItemsPerPage
            if page != folderCurrentPage {
                folderCurrentPage = page
            }
        }
        .onChange(of: appStore.voiceFeedbackEnabled) { _, enabled in
            if enabled {
                announceSelectedAppIfNeeded()
            } else {
                VoiceManager.shared.stop()
            }
        }
        .onChange(of: folder.name) {
            // 监听文件夹名称变化，确保界面立即更新
            if !isEditingName {
                folderName = folder.name
                // 强制刷新视图
                forceRefreshTrigger = UUID()
            }
        }
        .onChange(of: appStore.folderUpdateTrigger) {
            // 强制刷新文件夹视图，确保图标和名称显示最新状态
            forceRefreshTrigger = UUID()
            // 触发视图重新渲染
            folderName = folder.name
        }
        .onChange(of: appStore.gridRefreshTrigger) {
            // 强制刷新网格视图，确保应用图标和布局显示最新状态
            forceRefreshTrigger = UUID()
            // 触发视图重新渲染
            folderName = folder.name
        }
        .onChange(of: appStore.folderRenameRequestID) {
            consumeRenameRequestIfNeeded()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    @ViewBuilder
    private var folderContent: some View {
        VStack(spacing: 0) {
            folderTitleSection
                .frame(height: folderTitleHeight)

            GeometryReader { geo in
                appGridSection(geometry: geo)
            }

            if shouldShowFolderPageIndicator {
                folderPageIndicator
            }
        }
    }
    
    @ViewBuilder
    private var folderTitleSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 8 * uiScale) {
                if isEditingName {
                    TextField(appStore.localized(.folderNamePlaceholder), text: $folderName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 28 * uiScale))
                        .foregroundColor(labelColorOverride.map { Color(nsColor: $0) } ?? .primary)
                        .shadow(color: .black.opacity(Double(labelShadow.opacity)),
                            radius: labelShadow.radius, x: 0, y: labelShadow.offset)
                        .focused($isTextFieldFocused)
                        .padding()
                        .onSubmit {
                            finishEditing()
                        }
                        .onTapGesture(count: 2) {
                            finishEditing()
                        }
                        .onTapGesture {
                            finishEditing()
                        }
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    // 点击编辑框时阻止事件冒泡到父视图
                                }
                        )
                } else {
                    Text(folder.name)
                        .font(.system(size: 28 * uiScale))
                        .foregroundColor(labelColorOverride.map { Color(nsColor: $0) } ?? .primary)
                        .shadow(color: .black.opacity(Double(labelShadow.opacity)),
                            radius: labelShadow.radius, x: 0, y: labelShadow.offset)
                        .padding()
                        .contentShape(Rectangle()) // 确保整个区域都可以点击
                        .onTapGesture(count: 2) {
                            startEditing()
                        }
                        .onTapGesture {
                            // 单击时不做任何操作，避免意外触发
                        }
                        .id(forceRefreshTrigger) // 使用forceRefreshTrigger强制刷新
                }
            }
            Spacer()
        }
        .padding(.horizontal, titlePadding)
    }

    private var shouldShowFolderPageIndicator: Bool {
        folderPageCount > 1
    }

    private var safeFolderCurrentPage: Int {
        min(max(0, folderCurrentPage), max(folderPageCount - 1, 0))
    }

    private var folderPageIndicator: some View {
        HStack(spacing: 8 * uiScale) {
            ForEach(0..<folderPageCount, id: \.self) { index in
                Circle()
                    .fill((labelColorOverride.map { Color(nsColor: $0) } ?? .gray)
                        .opacity(safeFolderCurrentPage == index ? 1 : (labelColorOverride == nil ? 0.3 : 0.55)))
                    .frame(width: 8 * uiScale, height: 8 * uiScale)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        folderCurrentPage = index
                    }
            }
        }
        .padding(.top, 2 * uiScale)
        .padding(.bottom, 4 * uiScale)
    }

    private func resetFolderPagingState() {
        folderCurrentPage = 0
        folderPageCount = 1
    }
    
    @ViewBuilder
    private func appGridSection(geometry geo: GeometryProxy) -> some View {
        let availableGridWidth = max(1, geo.size.width - 2 * gridPadding)
        let availableGridHeight = max(1, geo.size.height - 2 * gridPadding)
        let baselineColumnWidth = computeColumnWidth(containerWidth: availableGridWidth, columns: 6)
        let baselineAppHeight = computeAppHeight(containerHeight: availableGridHeight, columns: 6)
        let iconSize: CGFloat = preferredIconSize ?? min(baselineColumnWidth, baselineAppHeight) * 0.75
        let labelHeight = appStore.showLabels ? CGFloat(appStore.iconLabelFontSize) + 8 : 0
        let labelTopSpacing: CGFloat = appStore.showLabels ? 6 : 0
        let totalItemHeight = iconSize + labelTopSpacing + labelHeight
        let minimumCellWidth = max(iconSize + 18, iconSize * 1.32)
        let desiredColumns = max(1, min(8, Int((availableGridWidth + spacing) / (minimumCellWidth + spacing))))
        let recomputedColumnWidth = computeColumnWidth(containerWidth: availableGridWidth, columns: desiredColumns)
        let recomputedAppHeight = computeAppHeight(containerHeight: availableGridHeight, columns: desiredColumns)
        // 保障单元格至少能容纳传入的图标尺寸与标签区域
        let columnWidth = max(recomputedColumnWidth, iconSize)
        let appHeight = max(recomputedAppHeight, iconSize + 32 * uiScale)
        let labelWidth: CGFloat = columnWidth * 0.9
        let minimumCellHeight = max(totalItemHeight + 12, iconSize * 1.28)
        let rowsPerPage = max(1, min(5, Int((availableGridHeight + spacing) / (minimumCellHeight + spacing))))
        let itemsPerPage = max(1, desiredColumns * rowsPerPage)
        let fallbackPageCount = max(1, (visualApps.count + itemsPerPage - 1) / itemsPerPage)

        if appStore.useCAGridRenderer {
            CAFolderGridViewRepresentable(
                appStore: appStore,
                folder: $folder,
                currentPage: $folderCurrentPage,
                pageCount: $folderPageCount,
                iconSize: iconSize,
                onClose: onClose,
                onLaunchApp: onLaunchApp,
                presentationState: presentationState,
                labelColorOverride: labelColorOverride,
                labelShadow: labelShadow,
                initialRevealAppPath: initialRevealAppPath
            )
            .id("ca_folder_grid_\(folder.id)")
            .onAppear { columnsCount = desiredColumns }
            .onChange(of: desiredColumns) { _, newValue in columnsCount = newValue }
        } else {
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(0..<fallbackPageCount, id: \.self) { pageIndex in
                            let pageStart = pageIndex * itemsPerPage
                            let pageEnd = min(pageStart + itemsPerPage, visualApps.count)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: desiredColumns), spacing: spacing) {
                                ForEach(pageStart..<pageEnd, id: \.self) { idx in
                                    let app = visualApps[idx]
                                    appDraggable(
                                        app: app,
                                        pageIndex: pageIndex,
                                        itemsPerPage: itemsPerPage,
                                        containerSize: geo.size,
                                        columnWidth: columnWidth,
                                        appHeight: appHeight,
                                        iconSize: iconSize,
                                        labelWidth: labelWidth,
                                        isSelected: isKeyboardNavigationActive && selectedIndex == idx
                                    )
                                    .id(app.url.standardizedFileURL.path)
                                }
                            }
                            .animation(LNAnimations.gridUpdate, value: pendingDropIndex)
                            .id(forceRefreshTrigger)
                            .padding(EdgeInsets(top: gridPadding, leading: gridPadding, bottom: gridPadding, trailing: gridPadding))
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                            .id(pageIndex)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $fallbackScrollPosition, anchor: .leading)
                .disabled(isEditingName)
                .onAppear {
                    columnsCount = desiredColumns
                    updateFallbackPaging(itemsPerPage: itemsPerPage, pageCount: fallbackPageCount)
                    fallbackScrollPosition = folderCurrentPage
                }
                .onChange(of: desiredColumns) { _, newValue in columnsCount = newValue }
                .onChange(of: fallbackScrollPosition) { _, newValue in
                    guard let newValue, newValue != folderCurrentPage else { return }
                    folderCurrentPage = newValue
                }
                .onChange(of: folderCurrentPage) { _, newValue in
                    guard fallbackScrollPosition != newValue else { return }
                    fallbackScrollPosition = newValue
                }
                .onChange(of: itemsPerPage) { _, newValue in
                    updateFallbackPaging(itemsPerPage: newValue, pageCount: fallbackPageCount)
                }
                .onChange(of: fallbackPageCount) { _, newValue in
                    updateFallbackPaging(itemsPerPage: itemsPerPage, pageCount: newValue)
                }

            // 拖拽预览层
            if let draggingApp {
                DragPreviewItem(item: .app(draggingApp),
                                iconSize: iconSize,
                                labelWidth: labelWidth,
                                scale: dragPreviewScale)
                    .position(x: dragPreviewPosition.x, y: dragPreviewPosition.y)
                    .zIndex(100)
                    .allowsHitTesting(false)
            }
        }
            .coordinateSpace(name: "folderGrid")
        }
    }

    private func updateFallbackPaging(itemsPerPage: Int, pageCount: Int) {
        fallbackItemsPerPage = max(1, itemsPerPage)
        folderPageCount = max(1, pageCount)
        folderCurrentPage = min(max(folderCurrentPage, 0), folderPageCount - 1)
        fallbackScrollPosition = folderCurrentPage
    }
    
    // 拖拽视觉重排
    
    private func startEditing() {
        isEditingName = true
        folderName = folder.name
        isTextFieldFocused = true
        appStore.isFolderNameEditing = true
    }

    private func consumeRenameRequestIfNeeded() {
        guard appStore.folderRenameRequestID == folder.id else { return }
        appStore.folderRenameRequestID = nil
        DispatchQueue.main.async {
            startEditing()
        }
    }
    
    private func finishEditing() {
        isEditingName = false
        appStore.isFolderNameEditing = false
        // 允许名称为纯空格（用户自定义视觉占位），仅阻止完全空字符串
        if !folderName.isEmpty {
            let newName = folderName
            if newName != folder.name {
                appStore.renameFolder(folder, newName: newName)
            }
        } else {
            folderName = folder.name
        }
    }
    
}

// MARK: - Drag helpers & builders (mirror outer logic, without folder creation)
extension FolderView {
    private func computeAppHeight(containerHeight: CGFloat, columns: Int) -> CGFloat {
        let maxRowsPerPage = Int(ceil(Double(folder.apps.count) / Double(max(columns, 1))))
        let totalRowSpacing = spacing * CGFloat(max(0, maxRowsPerPage - 1))
        let height = (containerHeight - totalRowSpacing) / CGFloat(maxRowsPerPage == 0 ? 1 : maxRowsPerPage)
        return max(60, min(120, height))
    }
    
    private func computeColumnWidth(containerWidth: CGFloat, columns: Int) -> CGFloat {
        let cols = max(columns, 1)
        let totalColumnSpacing = spacing * CGFloat(max(0, cols - 1))
        let width = (containerWidth - totalColumnSpacing) / CGFloat(cols)
        return max(50, width) // 优化最小宽度
    }

    // 拖拽命中与单元格几何计算（在下方扩展中实现）

    @ViewBuilder
    private func appDraggable(app: AppInfo,
                              pageIndex: Int,
                              itemsPerPage: Int,
                              containerSize: CGSize,
                              columnWidth: CGFloat,
                              appHeight: CGFloat,
                              iconSize: CGFloat,
                              labelWidth: CGFloat,
                              isSelected: Bool) -> some View {
        let base = LaunchpadItemButton(
            item: .app(app),
            iconSize: iconSize,
            labelWidth: labelWidth,
            isSelected: isSelected,
            showLabel: appStore.showLabels,
            labelFontSize: CGFloat(appStore.iconLabelFontSize),
            labelFontWeight: appStore.iconLabelFontWeightValue,
            shouldAllowHover: draggingApp == nil,
            hoverMagnificationEnabled: appStore.enableHoverMagnification,
            hoverMagnificationScale: CGFloat(appStore.hoverMagnificationScale),
            activePressEffectEnabled: appStore.enableActivePressEffect,
            activePressScale: CGFloat(appStore.activePressScale),
            onTap: {
                // 在编辑状态下不启动应用
                if draggingApp == nil && !isEditingName {
                    if canLaunch(app) {
                        onLaunchApp(app)
                    } else {
                        NSSound.beep()
                    }
                }
            }
        )
        .frame(height: appHeight)
        // 移除 matchedGeometryEffect 以降低滚动开销

        let isDraggingThisTile = (draggingApp == app)

        if appStore.isLayoutLocked {
            base
                .launchNextHideAppContextMenu(app: app, appStore: appStore)
        } else {
            base
                .opacity(isDraggingThisTile ? 0 : 1)
                .allowsHitTesting(!isDraggingThisTile)
                .animation(LNAnimations.springFast, value: isSelected)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("folderGrid"))
                        .onChanged { value in
                            guard !appStore.isLayoutLocked else { return }
                            // 在编辑状态下禁用拖拽
                            if isEditingName { return }
                        
                        if draggingApp == nil {
                            var tx = Transaction(); tx.disablesAnimations = true
                            withTransaction(tx) { draggingApp = app }
                            isKeyboardNavigationActive = false // 禁用键盘导航

                            // 让拖拽预览中心与指针位置一致，避免任何偏移
                            dragPreviewPosition = value.location
                        }

                        // 预览跟随指针位置（不引入起始偏移），确保光标与图标中心对齐
                        dragPreviewPosition = value.location

                        // 检测是否拖出文件夹范围并驻留
                        let isOutside: Bool = (value.location.x < 0 || value.location.y < 0 ||
                                               value.location.x > containerSize.width ||
                                               value.location.y > containerSize.height)
                        let now = Date()
                        if isOutside {
                            if outOfBoundsBeganAt == nil { outOfBoundsBeganAt = now }
                            if !hasHandedOffDrag, let start = outOfBoundsBeganAt, now.timeIntervalSince(start) >= outOfBoundsDwell, let dragging = draggingApp {
                                // 接力到外层：将应用移出文件夹并关闭文件夹
                                hasHandedOffDrag = true
                                pendingDropIndex = nil
                                appStore.handoffDraggingApp = dragging
                                appStore.handoffDragScreenLocation = NSEvent.mouseLocation
                                appStore.removeAppFromFolder(dragging, folder: folder)
                                // 清理内部拖拽状态并关闭文件夹
                                draggingApp = nil
                                outOfBoundsBeganAt = nil
                                withAnimation(LNAnimations.springFast) {
                                    onClose()
                                }
                                return
                            }
                        } else {
                            outOfBoundsBeganAt = nil
                        }

                        if let hoveringIndex = indexAt(point: dragPreviewPosition,
                                                       containerSize: containerSize,
                                                       pageIndex: pageIndex,
                                                       itemsPerPage: itemsPerPage,
                                                       columnWidth: columnWidth,
                                                       appHeight: appHeight) {
                            // 将"悬停在最后一个格子"视为插入到末尾，从而推动最后一个向前让位
                            let count = visualApps.count
                            if count > 0,
                               hoveringIndex == count - 1,
                               let dragging = draggingApp,
                               dragging != visualApps[hoveringIndex] {
                                pendingDropIndex = count // 末尾插槽
                            } else {
                                // 若命中的是"末尾插槽"（== count），保持为 count；其余为格子索引
                                pendingDropIndex = hoveringIndex
                            }
                        } else {
                            pendingDropIndex = nil
                        }
                    }
                    .onEnded { _ in
                        if appStore.isLayoutLocked { return }
                        // 在编辑状态下不处理拖拽结束
                        if isEditingName { return }
                        
                        guard let dragging = draggingApp else { return }
                        defer {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                draggingApp = nil
                                pendingDropIndex = nil
                                // 拖拽结束后不自动恢复键盘导航，保持一致体验
                            }
                        }

                        // 若已接力到外层，则不在此处处理落点
                        if hasHandedOffDrag {
                            hasHandedOffDrag = false
                            outOfBoundsBeganAt = nil
                            return
                        }

                        if let finalIndex = pendingDropIndex {
                            // 视觉吸附位置：直接使用finalIndex，确保准确吸附到目标位置
                            let dropDisplayIndex = finalIndex
                            let targetCenter = cellCenter(for: dropDisplayIndex,
                                                          pageIndex: pageIndex,
                                                          itemsPerPage: itemsPerPage,
                                                          containerSize: containerSize,
                                                          columnWidth: columnWidth,
                                                          appHeight: appHeight)
                            withAnimation(LNAnimations.dragPreview) {
                                dragPreviewPosition = targetCenter
                                dragPreviewScale = 1.0
                            }
                            if let from = folder.apps.firstIndex(of: dragging) {
                                var apps = folder.apps
                                apps.remove(at: from)
                                // 与视觉预览完全一致：直接使用悬停索引
                                let insertIndex = finalIndex
                                let clamped = min(max(0, insertIndex), apps.count)
                                apps.insert(dragging, at: clamped)
                                folder.apps = apps
                                appStore.notifyFolderContentChanged(folder)
                                
                                // 文件夹内拖拽结束后也触发压缩，确保主界面的empty项目移动到页面末尾
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    appStore.compactItemsWithinPages()
                                }
                            }
                        }
                    }
                )
                .launchNextHideAppContextMenu(app: app, appStore: appStore)
        }
    }
}

// MARK: - Drag geometry & hit-testing (folder internal)
extension FolderView {
    private func cellOrigin(for index: Int,
                            containerSize: CGSize,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        return GeometryUtils.cellOrigin(for: index,
                                      containerSize: containerSize,
                                      pageIndex: 0,
                                      columnWidth: columnWidth,
                                      appHeight: appHeight,
                                      columns: max(columnsCount, 1),
                                      columnSpacing: spacing,
                                      rowSpacing: spacing,
                                      pageSpacing: 0,
                                      currentPage: 0,
                                      gridPadding: gridPadding)
    }

    private func cellCenter(for index: Int,
                            pageIndex: Int,
                            itemsPerPage: Int,
                            containerSize: CGSize,
                            columnWidth: CGFloat,
                            appHeight: CGFloat) -> CGPoint {
        let localIndex = max(0, index - pageIndex * itemsPerPage)
        let origin = cellOrigin(for: localIndex, containerSize: containerSize, columnWidth: columnWidth, appHeight: appHeight)
        return CGPoint(x: origin.x + columnWidth / 2, y: origin.y + appHeight / 2)
    }

    private func indexAt(point: CGPoint,
                         containerSize: CGSize,
                         pageIndex: Int,
                         itemsPerPage: Int,
                         columnWidth: CGFloat,
                         appHeight: CGFloat) -> Int? {
        guard let offsetInPage = GeometryUtils.indexAt(point: point,
                                                      containerSize: containerSize,
                                                      pageIndex: 0,
                                                      columnWidth: columnWidth,
                                                      appHeight: appHeight,
                                                      columns: max(columnsCount, 1),
                                                      columnSpacing: spacing,
                                                      rowSpacing: spacing,
                                                      pageSpacing: 0,
                                                      currentPage: 0,
                                                      itemsPerPage: itemsPerPage,
                                                      gridPadding: gridPadding) else { return nil }
        
        let count = visualApps.count
        // 允许返回 count 作为"末尾插槽"，实现拖到最后一个之后的让位
        if count == 0 { return 0 }
        return min(max(pageIndex * itemsPerPage + offsetInPage, 0), count)
    }
}
// MARK: - Keyboard navigation (mirror outer behavior)
extension FolderView {
    private func setupKeyHandlers() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func setupInitialSelection() {
        if selectedIndex == nil, folder.apps.indices.first != nil {
            selectedIndex = 0
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // 正在编辑文件夹名时，放行输入
        if isTextFieldFocused { return event }
        if appStore.useCAGridRenderer { return event }

        // Esc 关闭文件夹
        if event.keyCode == 53 {
            onClose()
            return nil
        }

        // 回车：激活或启动选择
        if event.keyCode == 36 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            if let idx = selectedIndex, folder.apps.indices.contains(idx) {
                let targetApp = folder.apps[idx]
                if canLaunch(targetApp) {
                    onLaunchApp(targetApp)
                } else {
                    NSSound.beep()
                }
                return nil
            }
            return event
        }

        // Tab：与回车一致，先激活键盘导航
        if event.keyCode == 48 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            return event
        }

        // 向下：先激活导航
        if event.keyCode == 125 {
            if !isKeyboardNavigationActive {
                isKeyboardNavigationActive = true
                setSelectionToStart()
                clampSelection()
                announceSelectedAppIfNeeded()
                return nil
            }
            moveSelection(dx: 0, dy: 1)
            return nil
        }

        // 左右/一般箭头
        if let (dx, dy) = arrowDelta(for: event.keyCode) {
            guard isKeyboardNavigationActive else { return event }
            moveSelection(dx: dx, dy: dy)
            return nil
        }

        return event
    }

    private func moveSelection(dx: Int, dy: Int) {
        guard let current = selectedIndex else { return }
        let columnsCount = max(columnsCount, 1)
        let newIndex: Int = dy == 0 ? current + dx : current + dy * columnsCount
        guard folder.apps.indices.contains(newIndex) else { return }
        selectedIndex = newIndex
        announceSelectedAppIfNeeded()
    }

    private func setSelectionToStart() {
        if let first = folder.apps.indices.first {
            selectedIndex = first
        } else {
            selectedIndex = nil
        }
    }

    private func clampSelection() {
        let count = folder.apps.count
        if count == 0 { selectedIndex = nil; return }
        if let idx = selectedIndex {
            if idx >= count { selectedIndex = count - 1 }
            if idx < 0 { selectedIndex = 0 }
        } else {
            selectedIndex = 0
        }
    }

    private func announceSelectedAppIfNeeded() {
        guard appStore.voiceFeedbackEnabled,
              let index = selectedIndex,
              folder.apps.indices.contains(index) else { return }
        VoiceManager.shared.announceSelection(item: .app(folder.apps[index]))
    }
}

private struct FolderSurfaceModifier: ViewModifier {
    let isNativePresentation: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if isNativePresentation {
            content
        } else {
            content.liquidGlass(in: RoundedRectangle(cornerRadius: 30))
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .transition(LNAnimations.folderOpenTransition)
        }
    }
}
