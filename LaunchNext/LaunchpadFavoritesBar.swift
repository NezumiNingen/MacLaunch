import SwiftUI

/// Favorites are independent of the paged grid and survive relaunches.
struct LaunchpadFavoritesBar: View {
    @ObservedObject var appStore: AppStore
    let onLaunch: (AppInfo) -> Void
    @AppStorage("launchNextFavoriteAppPaths") private var storedPaths = "[]"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPicker = false
    @State private var query = ""
    @State private var hoveredPath: String?

    private var uiScale: CGFloat { LaunchpadUIMetrics.overallScale }

    private var paths: [String] {
        guard let data = storedPaths.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(NSOrderedSet(array: values).array.compactMap { $0 as? String }.prefix(8))
    }

    private var favorites: [AppInfo] {
        paths.compactMap { path in appStore.apps.first { $0.url.path == path } }
    }

    private var matchingApps: [AppInfo] {
        appStore.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: 14 * uiScale) {
            if favorites.isEmpty {
                Text("固定常用应用")
                    .font(.system(size: 13 * uiScale, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6 * uiScale)
            }
            ForEach(favorites) { app in
                Button { onLaunch(app) } label: {
                    Image(nsImage: IconStore.shared.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 42 * uiScale, height: 42 * uiScale)
                        .scaleEffect(hoveredPath == app.id ? 1.12 : 1)
                        .frame(width: 48 * uiScale, height: 48 * uiScale)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(app.name)
                .accessibilityLabel(app.name)
                .onHover { inside in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75)) {
                        hoveredPath = inside ? app.id : nil
                    }
                }
                .contextMenu {
                    Button("从常用栏移除", systemImage: "pin.slash") { toggle(app) }
                }
            }
            if !favorites.isEmpty {
                Divider().frame(height: 28 * uiScale)
            }
            Button {
                query = ""
                showingPicker = true
            } label: {
                Image(systemName: favorites.isEmpty ? "plus" : "slider.horizontal.3")
                    .font(.system(size: 16 * uiScale, weight: .medium))
                    .frame(width: 36 * uiScale, height: 42 * uiScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("管理常用应用")
            .accessibilityLabel("管理常用应用")
        }
        .padding(.horizontal, 14 * uiScale)
        .padding(.vertical, 8 * uiScale)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24 * uiScale).fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24 * uiScale))
            }
        }
        .sheet(isPresented: $showingPicker) { picker }
    }

    private var picker: some View {
        VStack(spacing: 16 * uiScale) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("常用应用").font(.title2.bold())
                    Text("最多固定 8 个应用，翻页后仍可快速启动。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { showingPicker = false }
                    .keyboardShortcut(.defaultAction)
            }
            TextField("搜索应用", text: $query)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("已固定 \(paths.count) / 8").foregroundStyle(.secondary)
                Spacer()
                if !paths.isEmpty {
                    Button("清空常用栏") { storedPaths = "[]" }
                }
            }.font(.callout)
            List(matchingApps) { app in
                Button { toggle(app) } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: IconStore.shared.icon(for: app))
                            .resizable().frame(width: 32 * uiScale, height: 32 * uiScale)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Image(systemName: paths.contains(app.id) ? "pin.fill" : "plus.circle")
                            .foregroundStyle(paths.contains(app.id) ? Color.accentColor : Color.secondary)
                    }
                    .padding(.vertical, 4 * uiScale)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(paths.count >= 8 && !paths.contains(app.id))
                .accessibilityLabel("\(app.name)，\(paths.contains(app.id) ? "已固定，点击移除" : "点击固定")")
            }
            if matchingApps.isEmpty {
                Text("没有找到应用").foregroundStyle(.secondary)
            }
        }
        .padding(24 * uiScale)
        .frame(width: 460 * uiScale, height: 520 * uiScale)
    }

    private func toggle(_ app: AppInfo) {
        var updated = paths
        if updated.contains(app.id) {
            updated.removeAll { $0 == app.id }
        } else if updated.count < 8 {
            updated.append(app.id)
        }
        guard let data = try? JSONEncoder().encode(updated),
              let value = String(data: data, encoding: .utf8) else { return }
        storedPaths = value
    }
}
