import SwiftUI
import AppKit
import Darwin
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var appStore: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: SettingsSection
    @State private var hasHiddenAppEntries: Bool = false
    @State private var hasNotHiddenAppEntries: Bool = false
    @State private var hiddenSearch: String = ""
    @State private var notHiddenSearch: String = ""
    @State private var hiddenSearchDebounceID: Int = 0
    @State private var notHiddenSearchDebounceID: Int = 0
    @State private var hasHiddenAppEntriesSearchResult: Bool = false
    @State private var hasNotHiddenAppEntriesSearchResult: Bool = false
    @State private var cachedHiddenAppEntries: [AppEntry] = []
    @State private var cachedNotHiddenAppEntries: [AppEntry] = []
    @State private var showHiddenApps = true
    @State private var showNotHiddenApps = false
    @State private var hiddenVisibleLimit: Int = 10
    @State private var notHiddenVisibleLimit: Int = 10
    private let listPageSize = 10
    @State private var editingDrafts: [String: String] = [:]
    @State private var editingEntries: Set<String> = []
    @State private var iconImportError: String? = nil
    @State private var showAppSourcesResetDialog = false
    @State private var showPerformanceRestartPrompt = false
    @State private var showAdvancedSettings = false
    @State private var cachedAllAppEntries: [AppEntry] = []
    @State private var allAppsVisibleLimit: Int = 10
    @State private var allAppsSearch: String = ""
    @State private var allAppsSearchDebounceID: Int = 0
    @State private var hasAllAppEntries:Bool = false
    @State private var hasAllAppEntriesSearchResult: Bool = false
    @State private var showOnlyEditedTittleApps: Bool = true
    @State private var showCLIInfoPopover = false
    @State private var showCLIRemoveInfoPopover = false
    @State private var showCLIFullPathCommand = false
    @State private var showQuarantineRemovalInfoPopover = false
    @State private var showHideMenuBarInfoPopover = false
    @State private var copiedCLICommand: String? = nil
    @State private var cliCommandActionMessage: String? = nil
    private var uiScale: CGFloat { LaunchpadUIMetrics.overallScale }

    init(appStore: AppStore) {
        self.appStore = appStore
        _selectedSection = State(initialValue: .general)
    }

    // Sidebar sizing presets
    private var sidebarIconFrame: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 26 * uiScale
        case .medium: return 24 * uiScale
        }
    }

    private var sidebarIconFontSize: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 13 * uiScale
        case .medium: return 12 * uiScale
        }
    }

    private var sidebarRowVerticalPadding: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 2 * uiScale
        case .medium: return 1 * uiScale
        }
    }

    private var sidebarHeaderIconFrame: CGFloat {
        return 36 * uiScale
    }

    private var sidebarHeaderCornerRadius: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 3
        case .medium: return 3
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView {
                List(selection: $selectedSection) {
                    HStack(alignment: .center, spacing: 2 * uiScale) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: sidebarHeaderIconFrame, height: sidebarHeaderIconFrame)
                            .cornerRadius(sidebarHeaderCornerRadius)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appStore.localized(.appTitle))
                                .font(.headline.weight(.semibold))
                            Text("\(appStore.localized(.versionPrefix))\(getVersion(fallback: appStore.localized(.versionFallback)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                    .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 15, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(SettingsSection.allCases) { section in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(section.iconGradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.06))
                                        .blendMode(.multiply)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.45),
                                                    .white.opacity(0.08),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .blendMode(.screen)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                                        .blendMode(.screen)
                                }
                                .overlay(
                                    Image(systemName: section.iconName)
                                        .font(.system(size: sidebarIconFontSize, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                                .frame(width: sidebarIconFrame, height: sidebarIconFrame)
                                .liquidGlass()
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)

                            Text(appStore.localized(section.localizationKey))
                                .font(.system(size: 13.5 * uiScale, weight: .regular))
                        }
                        .padding(.vertical, sidebarRowVerticalPadding)
                        .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
                .navigationSplitViewColumnWidth(min: 180 * uiScale, ideal: 205 * uiScale, max: 250 * uiScale)
            } detail: {
                detailView(for: selectedSection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)

            Button {
                appStore.isSetting = false
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .liquidGlass()
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .frame(minWidth: 820 * uiScale, minHeight: 640 * uiScale)
        .environment(\.controlSize, .large)
        .alert(appStore.localized(.customIconTitle), isPresented: Binding(get: { iconImportError != nil }, set: { if !$0 { iconImportError = nil } })) {
            Button(appStore.localized(.okButton), role: .cancel) { iconImportError = nil }
        } message: {
            Text(iconImportError ?? "")
        }
    }

    private var systemVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return String(format: appStore.localized(.aboutInfoMacOSValueFormat),
                      v.majorVersion, v.minorVersion, v.patchVersion)
    }

    private var chipText: String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var nameBuffer = [CChar](repeating: 0, count: Int(size))
        if sysctlbyname("machdep.cpu.brand_string", &nameBuffer, &size, nil, 0) == 0 {
            return String(cString: nameBuffer)
        }
        return appStore.localized(.aboutInfoUnknownChip)
    }

    private var displayResolutionText: String {
        guard let screen = NSScreen.main else { return appStore.localized(.aboutInfoUnknownDisplay) }
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        return "\(width)×\(height)"
    }

    private var displayNameText: String {
        if let name = NSScreen.main?.localizedName, !name.isEmpty {
            return name
        }
        return appStore.localized(.aboutInfoDisplayGeneric)
    }

private func getVersion(fallback: String) -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case performance
    case titles
    case appSources
    case hiddenApps
    case about

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .appSources: return "externaldrive"
        case .appearance: return "paintbrush"
        case .performance: return "speedometer"
        case .titles: return "text.badge.plus"
        case .hiddenApps: return "eye.slash"
        case .about: return "info.circle"
        }
    }

    var iconGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .general:
            colors = [Color(red: 0.12, green: 0.52, blue: 0.96), Color(red: 0.22, green: 0.72, blue: 0.94)]
        case .appSources:
            colors = [Color(nsColor: .systemGray), Color(nsColor: .lightGray)]
        case .appearance:
            colors = [Color(red: 0.73, green: 0.25, blue: 0.96), Color(red: 0.98, green: 0.43, blue: 0.80)]
        case .performance:
            colors = [Color(red: 0.02, green: 0.70, blue: 0.46), Color(red: 0.31, green: 0.93, blue: 0.69)]
        case .titles:
            colors = [Color(red: 0.95, green: 0.37, blue: 0.32), Color(red: 0.98, green: 0.55, blue: 0.44)]
        case .hiddenApps:
            colors = [Color(red: 0.29, green: 0.39, blue: 0.96), Color(red: 0.11, green: 0.67, blue: 0.91)]
        case .about:
            colors = [Color(red: 0.54, green: 0.55, blue: 0.70), Color(red: 0.42, green: 0.44, blue: 0.60)]
        }
        return LinearGradient(gradient: Gradient(colors: colors), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var localizationKey: LocalizationKey {
        switch self {
        case .general: return .settingsSectionGeneral
        case .appSources: return .settingsSectionAppSources
        case .appearance: return .settingsSectionAppearance
        case .performance: return .settingsSectionPerformance
        case .titles: return .settingsSectionTitles
        case .hiddenApps: return .settingsSectionHiddenApps
        case .about: return .settingsSectionAbout
        }
    }
}

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(1), Color.white.opacity(0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 16) {
                    Text(appStore.localized(section.localizationKey))
                        .font(.title3.bold())
                        .padding(.horizontal, 24)

                    ScrollView(showsIndicators: false) {
                        scrollContent(for: section)
                            // Keep glass overflow inside the scroll viewport,
                            // rather than clipping it at the card's side edges.
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollBounceBehavior(.basedOnSize)

                    if section == .general {
                        // Reserve the controls' native height and anchor them
                        // to the panel bottom independently of the cards above.
                        generalActions
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                }
                .padding(.top, 16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func scrollContent(for section: SettingsSection) -> some View {
        if section == .appearance {
            appearanceSection
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                content(for: section)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func content(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .performance:
            performanceSection
        case .titles:
            titlesSection
        case .appSources:
            appSourcesSection
        case .hiddenApps:
            hiddenAppsSection
        case .about:
            aboutSection
        }
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $appStore.soundEffectsEnabled) {
                Text(appStore.localized(.soundToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.soundToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                soundPickerRow(title: .soundEventLaunchpadOpen, binding: $appStore.soundLaunchpadOpenSound)
                soundPickerRow(title: .soundEventLaunchpadClose, binding: $appStore.soundLaunchpadCloseSound)
                soundPickerRow(title: .soundEventNavigation, binding: $appStore.soundNavigationSound)
            }

            Divider()

            Toggle(isOn: $appStore.voiceFeedbackEnabled) {
                Text(appStore.localized(.voiceToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.voiceToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(appStore.localized(.voiceNoteMutualExclusive))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private func soundPickerRow(title: LocalizationKey, binding: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(title))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 24)

            Picker("", selection: binding) {
                Text(appStore.localized(.soundOptionNone)).tag("")
                ForEach(SoundManager.systemSoundOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 140)

            Button(appStore.localized(.soundPreviewButton)) {
                SoundManager.shared.preview(systemSoundNamed: binding.wrappedValue)
            }
            .disabled(binding.wrappedValue.isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.developmentPlaceholderTitle))
                .font(.headline)
            Text(appStore.localized(.developmentPlaceholderSubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(appStore.localized(.developmentQuarantineRemovalTitle))
                    .font(.subheadline.weight(.semibold))
                Button {
                    showQuarantineRemovalInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showQuarantineRemovalInfoPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appStore.localized(.developmentQuarantineRemovalInfoTitle))
                            .font(.headline)
                        Text(appStore.localized(.developmentQuarantineRemovalInfoBody))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(width: 390, alignment: .leading)
                }
                Spacer()
                Toggle("", isOn: $appStore.showQuarantineRemovalAction)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Toggle(appStore.localized(.developmentWallpaperDiagnosticsTitle),
                   isOn: $appStore.wallpaperDiagnosticsEnabled)
                .font(.subheadline.weight(.semibold))
                .toggleStyle(.switch)
            Text(appStore.localized(.developmentWallpaperDiagnosticsHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                Text(currentMemoryUsageString())
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Toggle(appStore.localized(.showFPSOverlay), isOn: $appStore.showFPSOverlay)
                .toggleStyle(.switch)
            Text(appStore.localized(.showFPSOverlayDisclaimer))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appStore.localized(.showFPSOverlayWarning))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text(appStore.localized(.modifiedFrom))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var performanceSection: some View {
        let isLeanMode = appStore.performanceMode == .lean
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                Text(appStore.localized(.performanceModeTitle))
                    .font(.headline)
                performanceModePicker()

                Divider()

                Toggle(isOn: $appStore.useCAGridRenderer) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appStore.localized(.performanceRendererTitle))
                            .font(.body.weight(.medium))
                        Text(appStore.localized(!isLeanMode ? .performanceRendererSubtitle :
                            (appStore.useCAGridRenderer ? .performanceRendererWarning : .performanceRendererRecommendation)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .tint(PerformanceEngineSelector.accent)
                .disabled(!isLeanMode)
                .help(appStore.localized(.performanceRendererBadge))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(appStore.localized(.performanceCacheTitle))
                        .font(.headline)
                    Spacer(minLength: 8)
                    cacheStatusLabel(isValid: appStore.cacheStatistics.isCacheValid)
                }
                .help(appStore.localized(.performanceCacheCountsHint))
                Divider()
                performanceCacheDetails
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onChange(of: appStore.performanceMode) { _, _ in
            showPerformanceRestartPrompt = true
        }
        .alert(appStore.localized(.performanceModeRestartTitle), isPresented: $showPerformanceRestartPrompt) {
            Button(appStore.localized(.okButton), role: .cancel) {}
        } message: {
            Text(appStore.localized(.performanceModeRestartMessage))
        }
    }

    private var performanceCacheDetails: some View {
        let stats = appStore.cacheStatistics
        let isLeanMode = appStore.performanceMode == .lean
        return VStack(alignment: .leading, spacing: 0) {
            cacheDetailRow(title: appStore.localized(.performanceCacheIconLabel),
                           valueText: isLeanMode ? appStore.localized(.performanceCacheIconsDisabled) : "\(stats.iconCacheSize)")
                .help(appStore.localized(isLeanMode ? .performanceCacheLeanHint : .performanceCacheCountsHint))
            Divider()
            cacheDetailRow(title: appStore.localized(.performanceCacheAppInfoLabel),
                           valueText: "\(stats.appInfoCacheSize)")
            Divider()
            cacheDetailRow(title: appStore.localized(.performanceCacheGridLabel),
                           valueText: "\(stats.gridLayoutCacheSize)")
            Divider()
            cacheDetailRow(title: appStore.localized(.performanceCacheLastUpdateLabel),
                           valueText: formattedCacheUpdate(stats.lastUpdate))

            HStack {
                Spacer(minLength: 0)
                Button {
                    appStore.clearCache()
                    IconStore.shared.clear()
                    FolderPreviewCache.shared.clear()
                } label: {
                    Label(appStore.localized(.performanceCacheClearButton), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.top, 12)
        }
    }

    private var hiddenAppsSection: some View {
        return LazyVStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    presentHiddenAppPicker()
                } label: {
                    Label(appStore.localized(.hiddenAppsAddButton), systemImage: "eye.slash")
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: $showHiddenApps) {
                LazyVStack(alignment: .leading, spacing: 16){
                    if hasHiddenAppEntries {
                        Text(appStore.localized(.hiddenAppsHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("", text: $hiddenSearch, prompt: Text(appStore.localized(.hiddenAppsSearchPlaceholder)))
                            .textFieldStyle(.roundedBorder)
                            .padding(3)

                        if hasHiddenAppEntriesSearchResult {
                            LazyVStack(spacing: 12) {
                                ForEach(cachedHiddenAppEntries.prefix(hiddenVisibleLimit)) { entry in
                                    hiddenAppRow(for: entry)
                                }
                                if cachedHiddenAppEntries.count > hiddenVisibleLimit {
                                    Button(appStore.localized(.loadMore)) {
                                        hiddenVisibleLimit = min(hiddenVisibleLimit + listPageSize,
                                                                 cachedHiddenAppEntries.count)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            Text(appStore.localized(.customTitleNoResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        }
                    } else {
                        hiddenAppsEmptyState
                    }
                }
                // Leave room for glass outside the cards within the disclosure content.
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } label: {
                Label(appStore.localized(.settingsSectionHiddenApps), systemImage: "eye.slash")
                    .font(.headline)
            }

            DisclosureGroup(isExpanded: $showNotHiddenApps) {
                LazyVStack(alignment: .leading, spacing: 16){
                    if hasNotHiddenAppEntries{
                        Spacer()
                        Text(appStore.localized(.notHiddenAppsHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("", text: $notHiddenSearch, prompt: Text(appStore.localized(.notHiddenAppsSearchPlaceholder)))
                            .textFieldStyle(.roundedBorder)
                            .padding(3)

                        if hasNotHiddenAppEntriesSearchResult{
                            LazyVStack(spacing: 12) {
                                ForEach(cachedNotHiddenAppEntries.prefix(notHiddenVisibleLimit)) { entry in
                                    notHiddenAppRow(for: entry)
                                }
                                if cachedNotHiddenAppEntries.count > notHiddenVisibleLimit {
                                    Button(appStore.localized(.loadMore)) {
                                        notHiddenVisibleLimit = min(notHiddenVisibleLimit + listPageSize,
                                                                    cachedNotHiddenAppEntries.count)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        } else {
                            Text(appStore.localized(.customTitleNoResults))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } label: {
                Label(appStore.localized(.notHiddenAppsTitle), systemImage: "eye")
                    .font(.headline)
            }

        }
        .onAppear(perform: updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: hiddenSearch, initial: false) { _, _ in
            hiddenVisibleLimit = listPageSize
            scheduleHiddenSearchUpdate()
        }
        .onChange(of: notHiddenSearch, initial: false) { _, _ in
            notHiddenVisibleLimit = listPageSize
            if showNotHiddenApps {
                scheduleNotHiddenSearchUpdate()
            }
        }
        .onChange(of: showNotHiddenApps, initial: false) { _, isExpanded in
            if isExpanded {
                notHiddenVisibleLimit = listPageSize
                updateCachedNotHiddenAppEntries()
            }
        }
        .onChange(of: appStore.apps, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: appStore.folders, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
        .onChange(of: appStore.hiddenAppPaths, initial: false, updateCachedHiddenAndNotHiddenAppEntries)
    }

    private var hiddenAppEntries: [AppEntry] {
        appStore.hiddenAppPaths
            .map { path in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }

    private var notHiddenAppEntries: [AppEntry] {
        visibleNonHiddenApps
            .map { info in
                let path = info.url.path
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }

    private var visibleNonHiddenApps: [AppInfo] {
        var dedupedByPath: [String: AppInfo] = [:]
        for app in appStore.apps {
            dedupedByPath[standardizePath(app.url.path)] = app
        }
        for folder in appStore.folders {
            for app in folder.apps {
                let key = standardizePath(app.url.path)
                if dedupedByPath[key] == nil {
                    dedupedByPath[key] = app
                }
            }
        }
        return Array(dedupedByPath.values)
    }

    private func matches(_ entry: AppEntry, query: String) -> Bool {
        let options: String.CompareOptions = [
            .caseInsensitive,
            .diacriticInsensitive,
            .widthInsensitive
        ]

        return entry.appInfo.name.range(of: query, options: options) != nil
            || entry.defaultName.range(of: query, options: options) != nil
            || entry.id.range(of: query, options: options) != nil
    }

    private func filter(_ base: [AppEntry], by rawQuery: String) -> [AppEntry] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            matches(entry, query: query)
        }
    }

    private var hiddenAppsEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.hiddenAppsEmptyTitle))
                .font(.headline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hiddenAppRow(for entry: AppEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.appInfo.name)
                    .font(.callout.weight(.semibold))
                Text(entry.defaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appStore.unhideApp(path: entry.id)
            } label: {
                Text(appStore.localized(.hiddenAppsRemoveButton))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notHiddenAppRow(for entry: AppEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.appInfo.name)
                    .font(.callout.weight(.semibold))
                Text(entry.defaultName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appStore.hideApp(atPath: entry.id)
            } label: {
                Text(appStore.localized(.hiddenAppsAddButton))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct AppEntry: Identifiable {
        let id: String
        let appInfo: AppInfo
        let defaultName: String
    }

    private func updateCachedHiddenAppEntries() {
        cachedHiddenAppEntries.removeAll()
        hasHiddenAppEntries = !hiddenAppEntries.isEmpty
        let filteredHiddenAppEntries = filter(hiddenAppEntries, by: hiddenSearch)
        hasHiddenAppEntriesSearchResult = !filteredHiddenAppEntries.isEmpty
        cachedHiddenAppEntries.append(contentsOf: filteredHiddenAppEntries)
    }

    private func updateCachedNotHiddenAppEntries() {
        guard showNotHiddenApps else {
            cachedNotHiddenAppEntries.removeAll()
            hasNotHiddenAppEntries = false
            hasNotHiddenAppEntriesSearchResult = false
            return
        }

        cachedNotHiddenAppEntries.removeAll()
        hasNotHiddenAppEntries = !notHiddenAppEntries.isEmpty
        let filteredNotHiddenAppEntries = filter(notHiddenAppEntries, by: notHiddenSearch)
        hasNotHiddenAppEntriesSearchResult = !filteredNotHiddenAppEntries.isEmpty
        cachedNotHiddenAppEntries.append(contentsOf: filteredNotHiddenAppEntries)
    }

    private func updateCachedHiddenAndNotHiddenAppEntries() {
        updateCachedHiddenAppEntries()
        updateCachedNotHiddenAppEntries()
    }

    private func scheduleHiddenSearchUpdate() {
        hiddenSearchDebounceID += 1
        let token = hiddenSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if hiddenSearchDebounceID == token {
                updateCachedHiddenAppEntries()
            }
        }
    }

    private func scheduleNotHiddenSearchUpdate() {
        notHiddenSearchDebounceID += 1
        let token = notHiddenSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if notHiddenSearchDebounceID == token {
                updateCachedNotHiddenAppEntries()
            }
        }
    }

    private var uninstallSection: some View {
        let rawPath = appStore.uninstallToolAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolURL = appStore.uninstallToolAppURL
        let hasSelection = !rawPath.isEmpty
        let isMissing = appStore.uninstallToolConfiguredButMissing
        let fallbackName = rawPath.isEmpty ? "" : URL(fileURLWithPath: rawPath).deletingPathExtension().lastPathComponent
        let displayName = toolURL == nil ? fallbackName : appStore.uninstallToolAppDisplayName

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(appStore.localized(.settingsSectionUninstall), systemImage: "trash.fill")
                        .font(.headline)
                    Text(appStore.localized(.uninstallSectionDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.14), Color.orange.opacity(0.10)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Image(nsImage: appStore.uninstallToolAppIcon)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: 38, height: 38)
                            .cornerRadius(10)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(hasSelection ? (displayName.isEmpty ? rawPath : displayName) : appStore.localized(.uninstallToolNotConfigured))
                                .font(.headline)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            uninstallToolStatusBadge(isMissing: isMissing, hasSelection: hasSelection)
                        }

                        if hasSelection {
                            if !rawPath.isEmpty {
                                Text(rawPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 8) {
                                if !appStore.uninstallToolBundleIdentifier.isEmpty {
                                    uninstallToolMetaPill(appStore.uninstallToolBundleIdentifier, systemImage: "number")
                                }
                                if !appStore.uninstallToolVersionText.isEmpty {
                                    uninstallToolMetaPill(appStore.uninstallToolVersionText, systemImage: "tag")
                                }
                            }
                        } else {
                            Text(appStore.localized(.uninstallToolPathLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if isMissing {
                            Text(appStore.localized(.uninstallToolMissing))
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.10 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        presentUninstallToolPicker()
                    } label: {
                        Label(appStore.localized(.uninstallToolChooseButton), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if !appStore.openConfiguredUninstallTool() {
                            NSSound.beep()
                        }
                    } label: {
                        Label(appStore.localized(.uninstallToolOpenButton), systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(appStore.uninstallToolAppURL == nil)

                    Button(role: .destructive) {
                        _ = appStore.setUninstallToolApplication(url: nil)
                    } label: {
                        Label(appStore.localized(.uninstallToolClearButton), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasSelection)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        }
    }

    private func uninstallToolStatusBadge(isMissing: Bool, hasSelection: Bool) -> some View {
        let title: String
        let symbol: String
        let fillColor: Color
        let foreground: Color

        if isMissing {
            title = appStore.localized(.uninstallToolMissing)
            symbol = "exclamationmark.triangle.fill"
            fillColor = Color.red.opacity(colorScheme == .dark ? 0.22 : 0.14)
            foreground = .red
        } else if hasSelection {
            title = appStore.localized(.uninstallToolOpenButton)
            symbol = "checkmark.circle.fill"
            fillColor = Color.green.opacity(colorScheme == .dark ? 0.20 : 0.12)
            foreground = .green
        } else {
            title = appStore.localized(.uninstallToolChooseButton)
            symbol = "circle.dashed"
            fillColor = Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
            foreground = .secondary
        }

        return Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fillColor, in: Capsule())
            .foregroundStyle(foreground)
    }

    private func uninstallToolMetaPill(_ text: String, systemImage: String) -> some View {
        return Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var titlesSection: some View {
        LazyVStack(alignment: .leading, spacing: 16){
            HStack {
                Button {
                    presentCustomTitlePicker()
                } label: {
                    Label(appStore.localized(.customTitleAddFromFolder), systemImage: "plus")
                }
                Spacer()
            }

            Text(appStore.localized(.customTitleHint))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(){
                Text(appStore.localized(.customTitleOnly))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $showOnlyEditedTittleApps)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(appStore.customTitles.isEmpty)
                    .onChange(of: appStore.customTitles.isEmpty, initial: true) { _, isEmply in
                        if isEmply {
                            showOnlyEditedTittleApps = false
                        }
                    }
            }

            if hasAllAppEntries{
                TextField("", text: $allAppsSearch, prompt: Text(appStore.localized(.renameSearchPlaceholder)))
                    .textFieldStyle(.roundedBorder)
                    .padding(3)

                if hasAllAppEntriesSearchResult{
                    let visibleEntries: [AppEntry] = showOnlyEditedTittleApps
                        ? cachedAllAppEntries
                        : Array(cachedAllAppEntries.prefix(allAppsVisibleLimit))
                    LazyVStack(spacing: 12) {
                        ForEach(visibleEntries){ entry in
                            customTitleRow(for: entry)
                        }
                        if !showOnlyEditedTittleApps && cachedAllAppEntries.count > allAppsVisibleLimit {
                            Button(appStore.localized(.loadMore)) {
                                allAppsVisibleLimit = min(allAppsVisibleLimit + listPageSize,
                                                          cachedAllAppEntries.count)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Text(appStore.localized(.customTitleNoResults))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                }
            }
        }
        .onAppear(perform: updateCachedAllAppEntries)
        .onChange(of: allAppsSearch, initial: false) { _, _ in
            allAppsVisibleLimit = listPageSize
            scheduleAllAppsSearchUpdate()
        }
        .onChange(of: showOnlyEditedTittleApps, initial: false) { _, _ in
            allAppsVisibleLimit = listPageSize
            updateCachedAllAppEntries()
        }
        .onChange(of: appStore.customTitles, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.apps, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.folders, initial: false, updateCachedAllAppEntries)
        .onChange(of: appStore.hiddenAppPaths, initial: false, updateCachedAllAppEntries)
    }

    private var customTitleEntries: [AppEntry] {
        appStore.customTitles
            .map { (path, _) in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return AppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
            }
    }

    private var allAppEntries: [AppEntry] {
        var allEntries: [AppEntry] = []
        allEntries.append(contentsOf: notHiddenAppEntries)
        allEntries.append(contentsOf: hiddenAppEntries)
        allEntries.sort { lhs, rhs in
            lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name) == .orderedAscending
        }
        return allEntries
    }

    private func updateCachedAllAppEntries() {
        cachedAllAppEntries.removeAll()

        if (showOnlyEditedTittleApps){
            hasAllAppEntries = !customTitleEntries.isEmpty
            let filteredCustomTitleEntries = filter(customTitleEntries, by: allAppsSearch)
            hasAllAppEntriesSearchResult = !filteredCustomTitleEntries.isEmpty
            cachedAllAppEntries.append(contentsOf: filteredCustomTitleEntries)
        } else {
            hasAllAppEntries = !allAppEntries.isEmpty
            let filteredAllAppEntries = filter(allAppEntries, by: allAppsSearch)
            hasAllAppEntriesSearchResult = !filteredAllAppEntries.isEmpty
            cachedAllAppEntries.append(contentsOf: filteredAllAppEntries)
        }
    }

    private func scheduleAllAppsSearchUpdate() {
        allAppsSearchDebounceID += 1
        let token = allAppsSearchDebounceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if allAppsSearchDebounceID == token {
                updateCachedAllAppEntries()
            }
        }
    }

    @ViewBuilder
    private func customTitleRow(for entry: AppEntry) -> some View {
        let isEditing = editingEntries.contains(entry.id)
        let currentDraft = editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name
        let trimmedDraft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = appStore.customTitles[entry.id] ?? entry.defaultName
        let draftBinding = Binding(
            get: { editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name },
            set: { editingDrafts[entry.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.appInfo.name)
                        .font(.callout.weight(.semibold))
                    Text(String(format: appStore.localized(.customTitleDefaultFormat), entry.defaultName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    if isEditing {
                        Button(appStore.localized(.customTitleSave)) {
                            saveCustomTitle(entry)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedDraft.isEmpty || trimmedDraft == originalValue)
                        Button(appStore.localized(.customTitleCancel)) {
                            cancelEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleReset))
                            }
                            .buttonStyle(.bordered)
                        }

                    } else {
                        Button(appStore.localized(.customTitleEdit)) {
                            beginEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleReset))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if isEditing {
                TextField("", text: draftBinding, prompt: Text(appStore.localized(.customTitlePlaceholder)))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentHiddenAppPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = appStore.localized(.hiddenAppsAddButton)
        panel.title = appStore.localized(.hiddenAppsAddButton)

        if AppDelegate.withModalDialog({ panel.runModal() }) == .OK {
            if !appStore.hideApps(at: panel.urls) {
                NSSound.beep()
            }
        }
    }

    private func presentUninstallToolPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = appStore.localized(.uninstallToolPanelTitle)
        panel.prompt = appStore.localized(.uninstallToolChooseButton)

        if AppDelegate.withModalDialog({ panel.runModal() }) == .OK, let url = panel.url {
            if !appStore.setUninstallToolApplication(url: url) {
                NSSound.beep()
            }
        }
    }

    private func presentCustomTitlePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = appStore.localized(.customTitleAddButton)
        panel.message = appStore.localized(.customTitlePickerMessage)
        panel.prompt = appStore.localized(.chooseButton)

        if AppDelegate.withModalDialog({ panel.runModal() }) == .OK, let url = panel.url, let info = appStore.ensureCustomTitleEntry(for: url) {
            let path = info.url.path
            editingEntries.insert(path)
            editingDrafts[path] = appStore.customTitles[path] ?? info.name
            if !showOnlyEditedTittleApps {
                showOnlyEditedTittleApps = true
                allAppsSearch = ""
            }
        }
    }

    private func presentAppIconPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.icns, .png, .jpeg, .tiff]
        panel.prompt = appStore.localized(.customIconChoose)
        panel.title = appStore.localized(.customIconTitle)

        if AppDelegate.withModalDialog({ panel.runModal() }) == .OK, let url = panel.url {
            if !appStore.setCustomAppIcon(from: url) {
                iconImportError = appStore.localized(.customIconError)
            }
        }
    }

    private func presentAppSourcePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = appStore.localized(.chooseButton)

        if AppDelegate.withModalDialog({ panel.runModal() }) == .OK {
            var addedAny = false
            for url in panel.urls {
                if appStore.addCustomAppSource(path: url.path) {
                    addedAny = true
                }
            }
            if !addedAny && !panel.urls.isEmpty {
                NSSound.beep()
            }
        }
    }

    private func pathExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func displayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    @ViewBuilder
    private func appSourceRow(icon: String, path: String, isAvailable: Bool, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(displayName(for: path))
                        .font(.body)
                    if !isAvailable {
                        Text(appStore.localized(.scanSourcesMissingBadge))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }
                }
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

//    private struct CustomTitleEntry: Identifiable {
//        let id: String
//        let appInfo: AppInfo
//        let defaultName: String
//    }

    private func beginEditing(_ entry: AppEntry) {
        editingEntries.insert(entry.id)
        editingDrafts[entry.id] = appStore.customTitles[entry.id] ?? entry.appInfo.name
    }

    private func cancelEditing(_ entry: AppEntry) {
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func saveCustomTitle(_ entry: AppEntry) {
        let draft = (editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        let original = appStore.customTitles[entry.id] ?? entry.defaultName
        if draft == original {
            editingEntries.remove(entry.id)
            editingDrafts.removeValue(forKey: entry.id)
            return
        }
        appStore.setCustomTitle(draft, for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func removeCustomTitle(_ entry: AppEntry) {
        appStore.clearCustomTitle(for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    @ViewBuilder
    private var headlineGlass: some View {
        PressableGlassTitle(text: appStore.localized(.appTitle))
    }

    private struct PressableGlassTitle: View {
        let text: String

        @GestureState private var isPressed = false
        @State private var bounce = false

        private var scale: CGFloat {
            if isPressed { return 0.97 }
            if bounce { return 1.01 }
            return 1.0
        }

        private var shadowOpacity: Double {
            isPressed ? 0.18 : 0.0
        }

        private var shadowRadius: CGFloat {
            isPressed ? 8 : 0
        }

        private var shadowOffsetY: CGFloat {
            isPressed ? 4 : 0
        }

        var body: some View {
            let label = Text(text)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            label
                .glassEffect(.clear, in: Capsule())
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowOffsetY)
                .scaleEffect(scale)
                .contentShape(Capsule())
                .gesture(pressGesture)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: bounce)
        }

        private var pressGesture: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if bounce { bounce = false }
                }
                .updating($isPressed) { _, state, _ in
                    state = true
                }
                .onEnded { _ in
                    bounce = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        bounce = false
                    }
                }
        }
    }


    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .center) {
                Image("AboutBackground")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(16.0/9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(spacing: 12) {
                    headlineGlass

                    Text(String(format: appStore.localized(.versionLabelFormat),
                                getVersion(fallback: appStore.localized(.versionFallback))))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(appStore.localized(.modifiedFrom))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
            )
            .padding(.bottom, 12)

            HStack(alignment: .bottom, spacing: 12) {
                TicTacToeBoard()
                    .frame(width: 130)

                infoCard
            }

            Spacer(minLength: 32)

            HStack(spacing: 12) {
                aboutActionButton(.aboutProjectHome,
                                  systemImage: "arrow.up.right.square",
                                  url: "https://github.com/NezumiNingen/MacLaunch")
                aboutActionButton(.aboutFeedback,
                                  systemImage: "bubble.left.and.bubble.right",
                                  url: "https://github.com/NezumiNingen/MacLaunch/issues")
                aboutActionButton(.aboutContribute,
                                  systemImage: "hands.sparkles",
                                  url: "https://github.com/NezumiNingen/MacLaunch/pulls")
            }

        }
        .frame(maxWidth: .infinity, minHeight: 550, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func aboutActionButton(_ titleKey: LocalizationKey,
                                   systemImage: String,
                                   url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                Text(appStore.localized(titleKey))
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.38), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(appStore.localized(titleKey))
    }

    @ViewBuilder
    private var infoCard: some View {
        let cardFill = colorScheme == .light ? Color.white : Color.white.opacity(0.05)
        VStack(alignment: .leading, spacing: 10) {
            Text(appStore.localized(.aboutInfoSystemTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoMacOSLabel), value: systemVersionText)

            Divider()

            Text(appStore.localized(.aboutInfoProcessorTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoChipLabel), value: chipText)

            Divider()

            Text(appStore.localized(.aboutInfoDisplayTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: displayNameText, value: displayResolutionText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private struct TicTacToeBoard: View {
        private enum Mark: String {
            case x = "X", o = "O", empty = ""
        }

        @State private var cells: [Mark] = Array(repeating: .empty, count: 9)
        @State private var isPlayerTurn: Bool = true
        @State private var statusText: String = "Your turn"
        @State private var gameOver: Bool = false

        var body: some View {
            VStack(spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(0..<9) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                            Text(cells[index].rawValue)
                                .font(.system(size: 28, weight: .bold))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture {
                            guard !gameOver, isPlayerTurn, cells[index] == .empty else { return }
                            makeMove(at: index, mark: .x)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                aiTurn()
                            }
                        }
                    }
                }
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: resetGame) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }

        private func makeMove(at index: Int, mark: Mark) {
            cells[index] = mark
            if let winner = evaluateWinner() {
                statusText = winner == .x ? "You win!" : "AI wins!"
                gameOver = true
            } else if !cells.contains(.empty) {
                statusText = "Draw"
                gameOver = true
            } else {
                isPlayerTurn.toggle()
                statusText = isPlayerTurn ? "Your turn" : "AI thinking..."
            }
        }

        private func aiTurn() {
            guard !gameOver else { return }
            guard !isPlayerTurn else { return }

            let emptyCells = cells.enumerated().filter { $0.element == .empty }.map { $0.offset }
            guard let choice = emptyCells.randomElement() else { return }
            makeMove(at: choice, mark: .o)
        }

        private func evaluateWinner() -> Mark? {
            let lines = [
                [0,1,2],[3,4,5],[6,7,8],
                [0,3,6],[1,4,7],[2,5,8],
                [0,4,8],[2,4,6]
            ]
            for line in lines {
                let marks = line.map { cells[$0] }
                if marks.allSatisfy({ $0 == .x }) { return .x }
                if marks.allSatisfy({ $0 == .o }) { return .o }
            }
            return nil
        }

        private func resetGame() {
            cells = Array(repeating: .empty, count: 9)
            isPlayerTurn = true
            statusText = "Your turn"
            gameOver = false
        }
    }

    private func currentMemoryUsageValue() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kern = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard kern == KERN_SUCCESS else { return "--" }

        let usedBytes = info.phys_footprint
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(usedBytes))
    }

    private func currentMemoryUsageString() -> String {
        "Memory: \(currentMemoryUsageValue())"
    }

    private func formattedCacheUpdate(_ date: Date) -> String {
        if date == .distantPast {
            return appStore.localized(.performanceCacheNever)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func performanceModePicker() -> some View {
        PerformanceEngineSelector(
            selection: $appStore.performanceMode,
            nextTitle: appStore.localized(.performanceModeLean),
            legacyTitle: appStore.localized(.performanceModeFull),
            nextDescription: appStore.localized(.performanceModeDescriptionLean),
            legacyDescription: appStore.localized(.performanceModeDescriptionFull),
            restartHint: appStore.localized(.performanceModeRestartHint)
        )
    }

    private func cacheStatusLabel(isValid: Bool) -> some View {
        let title = appStore.localized(isValid ? .performanceCacheStatusValid : .performanceCacheStatusInvalid)
        let color = isValid ? Color.green : Color.orange
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cacheDetailRow(title: String, valueText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(valueText)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearanceModeCard

            loginLayoutCard
                .padding(.top, -10)

            Text(appStore.localized(.lockLayoutDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, -20)

            applicationIconCard
                .padding(.top, -15)

            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 18) {
                    uninstallSection

                    Divider()
                    developmentSection
                }
                .padding(.top, 12)
            } label: {
                Label(appStore.localized(.settingsAdvancedOptions), systemImage: "slider.horizontal.3")
                    .font(.headline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var generalActions: some View {
        HStack {
            Button { appStore.refresh() } label: {
                Label(appStore.localized(.refresh), systemImage: "arrow.clockwise")
            }
            Spacer()
        }
    }

    private var loginLayoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                HStack {
                    Text(appStore.localized(.launchAtLoginTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.isStartOnLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!appStore.canConfigureStartOnLogin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(appStore.localized(.showQuickRefreshButton))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.showQuickRefreshButton)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                HStack {
                    Text(appStore.localized(.lockLayoutTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.isLayoutLocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(appStore.localized(.developmentEnableCLICodeTitle))
                        .font(.subheadline.weight(.semibold))
                    Button {
                        if !showCLIInfoPopover {
                            copiedCLICommand = nil
                            cliCommandActionMessage = nil
                            showCLIRemoveInfoPopover = false
                            showCLIFullPathCommand = false
                        }
                        showCLIInfoPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline.weight(.regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCLIInfoPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appStore.localized(.commandLineInterfaceHelpTitle))
                                .font(.headline)
                            Text(appStore.localized(.commandLineInterfaceHelpBody))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(appStore.localized(.commandLineInterfaceAgentHint))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            cliCommandRow("maclaunch --cli help")
                            cliCommandRow("maclaunch --tui")
                            DisclosureGroup(
                                isExpanded: $showCLIFullPathCommand,
                                content: {
                                    cliCommandRow("\(Bundle.main.executableURL?.path ?? "maclaunch") --tui")
                                        .padding(.top, 4)
                                },
                                label: {
                                    Text(appStore.localized(.commandLineInterfaceShowFullPathCommand))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            )
                            Divider()
                            HStack(spacing: 8) {
                                Button(role: .destructive) {
                                    if appStore.developmentEnableCLICode {
                                        appStore.developmentEnableCLICode = false
                                        cliCommandActionMessage = appStore.localized(.commandLineInterfaceRemoveCommandDone)
                                    } else {
                                        let removed = appStore.removeInstalledCLICommand()
                                        cliCommandActionMessage = removed
                                            ? appStore.localized(.commandLineInterfaceRemoveCommandDone)
                                            : appStore.localized(.commandLineInterfaceRemoveCommandMissing)
                                    }
                                } label: {
                                    Label(appStore.localized(.commandLineInterfaceRemoveCommandButton), systemImage: "trash")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    showCLIRemoveInfoPopover.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showCLIRemoveInfoPopover, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(appStore.localized(.commandLineInterfaceRemoveCommandInfoTitle))
                                            .font(.headline)
                                        Text(appStore.localized(.commandLineInterfaceRemoveCommandInfoBody))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    }
                                    .padding(12)
                                    .frame(width: 390, alignment: .leading)
                                }
                            }
                            if let cliCommandActionMessage {
                                Text(cliCommandActionMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(width: 360, alignment: .leading)
                    }
                    Spacer()
                    Toggle("", isOn: $appStore.developmentEnableCLICode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var applicationIconCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appStore.localized(.customIconTitle))
                    .font(.headline)
                let hint = appStore.localized(.customIconHint)
                Text(twoLineHint(hint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        presentAppIconPicker()
                    } label: {
                        Label(appStore.localized(.customIconChoose), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appStore.resetCustomAppIcon()
                    } label: {
                        Label(appStore.localized(.customIconReset), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!appStore.hasCustomAppIcon)
                }

                Image(nsImage: appStore.currentAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 66, height: 66)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    @ViewBuilder
    private func cliCommandRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 6)
            Button {
                copyCLICommand(command)
            } label: {
                Image(systemName: copiedCLICommand == command ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(copiedCLICommand == command ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func copyCLICommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copiedCLICommand = command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedCLICommand == command {
                copiedCLICommand = nil
            }
        }
    }

    private func twoLineHint(_ text: String) -> String {
        let separators = [". ", "。", "！", "？", "；", ";", "，", ",", "、"]
        for sep in separators {
            if let range = text.range(of: sep) {
                let before = text[..<range.upperBound]
                let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if after.isEmpty {
                    return String(before)
                }
                return String(before) + "\n" + after
            }
        }

        let words = text.split(separator: " ")
        if words.count >= 2 {
            let mid = words.count / 2
            let first = words[..<mid].joined(separator: " ")
            let second = words[mid...].joined(separator: " ")
            return first + "\n" + second
        }

        return text
    }

    @ViewBuilder
    private var appearanceModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(appStore.localized(.appearanceModeTitle))
                    .font(.headline)
                    .frame(minWidth: 90, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeFollowSystem),
                        imageName: "AppearanceAuto",
                        mode: .system
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeLight),
                        imageName: "AppearanceLight",
                        mode: .light
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeDark),
                        imageName: "AppearanceDark",
                        mode: .dark
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            languageRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func appearanceOptionCard(title: String, imageName: String, mode: AppearancePreference) -> some View {
        let isSelected = appStore.appearancePreference == mode
        return Button {
            appStore.appearancePreference = mode
        } label: {
            VStack(spacing: 2) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(minWidth: 52, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var languageRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(.languagePickerTitle))
                .font(.headline)
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Picker("", selection: $appStore.preferredLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(appStore.localizedLanguageName(for: language)).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appSourcesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.scanSourcesIntroTitle))
                    .font(.headline)
                Text(appStore.localized(.scanSourcesIntroDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.scanSourcesDefaultListTitle))
                    .font(.subheadline.weight(.semibold))
                ForEach(appStore.builtinAppSourcePaths, id: \.self) { path in
                    appSourceRow(icon: "internaldrive", path: path, isAvailable: true, accessory: { EmptyView() })
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(appStore.localized(.scanSourcesCustomListTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        presentAppSourcePicker()
                    } label: {
                        Label(appStore.localized(.scanSourcesAddButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showAppSourcesResetDialog = true
                    } label: {
                        Label(appStore.localized(.scanSourcesResetButton), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appStore.customAppSourcePaths.isEmpty)
                }

                if appStore.customAppSourcePaths.isEmpty {
                    Text(appStore.localized(.scanSourcesEmptyHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(appStore.customAppSourcePaths, id: \.self) { path in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                appSourceRow(icon: "folder", path: path, isAvailable: pathExists(path)) {
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleExpandedSource(path)
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)

                                        Button {
                                            appStore.removeCustomAppSource(path: path)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(Color.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }

                            if expandedSource == standardizePath(path) {
                                let apps = appsForSource(path)
                                VStack(alignment: .leading, spacing: 8) {
                                    if apps.isEmpty {
                                        Text(appStore.localized(.scanSourcesEmptyHint))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                    } else {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 8) {
                                                ForEach(apps, id: \.path) { app in
                                                    HStack(spacing: 8) {
                                                        Image(nsImage: app.icon)
                                                            .resizable()
                                                            .interpolation(.high)
                                                            .antialiased(true)
                                                            .frame(width: 24, height: 24)
                                                            .cornerRadius(5)
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(app.name)
                                                                .font(.callout)
                                                                .lineLimit(1)
                                                            Text(app.path)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                        Spacer()
                                                        Button(role: .destructive) {
                                                            removeAppFromLayout(app.path)
                                                        } label: {
                                                            Image(systemName: "trash")
                                                                .foregroundStyle(Color.red)
                                                        }
                                                        .buttonStyle(.borderless)
                                                    }
                                                    .padding(.horizontal, 6)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .frame(maxHeight: 220)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(appStore.localized(.scanSourcesFuzzySearchTitle))
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(appStore.localized(.scanSourcesFuzzySearchDescription))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)

                    Toggle("", isOn: $appStore.fuzzySearchEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)

                Divider()
                    .padding(.horizontal, 18)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .confirmationDialog(appStore.localized(.scanSourcesResetButton), isPresented: $showAppSourcesResetDialog, titleVisibility: .visible) {
            Button(appStore.localized(.scanSourcesResetButton), role: .destructive) {
                appStore.resetCustomAppSources()
            }
            Button(appStore.localized(.cancel), role: .cancel) {}
        }
    }

    // MARK: - Helpers
    private struct SourceApp {
        let name: String
        let path: String
        let icon: NSImage
    }

    private func appsForSource(_ sourcePath: String) -> [SourceApp] {
        let normalizedSource = standardizePath(sourcePath)
        let prefix = normalizedSource.hasSuffix("/") ? normalizedSource : normalizedSource + "/"
        var apps: [SourceApp] = []
        var seen: Set<String> = []

        func consider(name: String, path: String, icon: NSImage) {
            let normalized = standardizePath(path)
            guard normalized == normalizedSource || normalized.hasPrefix(prefix) else { return }
            if seen.insert(normalized).inserted {
                apps.append(SourceApp(name: name, path: normalized, icon: icon))
            }
        }

        for item in appStore.items {
            switch item {
            case .app(let app):
                consider(name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
            case .missingApp(let placeholder):
                consider(name: placeholder.displayName, path: placeholder.bundlePath, icon: placeholder.icon)
            case .folder(let folder):
                for app in folder.apps {
                    consider(name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
                }
            case .empty:
                break
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func standardizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    @State private var expandedSource: String? = nil

    private func toggleExpandedSource(_ path: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let normalized = standardizePath(path)
            expandedSource = (expandedSource == normalized) ? nil : normalized
        }
    }

    private func removeAppFromLayout(_ rawPath: String) {
        let normalized = standardizePath(rawPath)
        // Replace matching top-level items with empty placeholders.
        var updatedItems = appStore.items
        for idx in updatedItems.indices {
            switch updatedItems[idx] {
            case .app(let app) where standardizePath(app.url.path) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .missingApp(let placeholder) where standardizePath(placeholder.bundlePath) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .folder(var folder):
                let originalCount = folder.apps.count
                folder.apps.removeAll { standardizePath($0.url.path) == normalized }
                if folder.apps.count != originalCount {
                    if folder.apps.isEmpty {
                        updatedItems[idx] = .empty(UUID().uuidString)
                    } else {
                        updatedItems[idx] = .folder(folder)
                    }
                }
            default:
                break
            }
        }
        appStore.items = updatedItems

        // Sync cleanup in the folders list.
        for idx in appStore.folders.indices {
            appStore.folders[idx].apps.removeAll { standardizePath($0.url.path) == normalized }
        }
        // Cleanup in the apps list.
        appStore.apps.removeAll { standardizePath($0.url.path) == normalized }

        appStore.compactItemsWithinPages()
        appStore.removeEmptyPages()
        DispatchQueue.main.async {
            appStore.folderUpdateTrigger = UUID()
            appStore.gridRefreshTrigger = UUID()
        }
        appStore.saveAllOrder()
    }

    private var appearanceSection: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            appearancePrimarySection
            Divider().padding(.vertical, 24)
            Text(appStore.localized(.settingsSectionSound)).font(.headline)
            soundSection.padding(.top, 12)
        }
    }

    private var appearancePrimarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(appStore.localized(.useLocalizedThirdPartyTitles))
                Spacer()
                Toggle("", isOn: $appStore.useLocalizedThirdPartyTitles)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.hideDockOption))
                Spacer()
                Toggle("", isOn: $appStore.hideDock)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack {
                Text(appStore.localized(.hideMenuBarOption))
                Button {
                    showHideMenuBarInfoPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHideMenuBarInfoPopover, arrowEdge: .top) {
                    Text(appStore.localized(.hideMenuBarInfoBody))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(width: 280, alignment: .leading)
                }
                Spacer()
                Toggle("", isOn: $appStore.hideMenuBar)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .disabled(!appStore.isFullscreenMode)
            .opacity(appStore.isFullscreenMode ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 6) {
                Text(appStore.localized(.folderPreviewHighResTitle))
                    .font(.headline)
                Text(appStore.localized(.folderPreviewHighResHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
