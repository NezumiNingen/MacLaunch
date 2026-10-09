import Foundation

extension AppStore {
    @discardableResult
    func organizeAppsAutomatically() -> AutomaticAppOrganizationResult {
        guard !isLayoutLocked, openFolder == nil, !isSetting else {
            return AutomaticAppOrganizationResult(appsOrganized: 0, foldersCreated: 0, foldersRenamed: 0)
        }

        let originalItemOrder = items.map(\.id)
        let originalFolderContents = folders.reduce(into: [String: [String]]()) { result, folder in
            result[folder.id] = folder.apps.map { standardizedFilePath($0.url.path) }
        }
        let originalFolderByAppPath = folders.reduce(into: [String: String]()) { result, folder in
            for app in folder.apps {
                result[standardizedFilePath(app.url.path)] = folder.id
            }
        }

        var automaticFolderIDs = UserDefaults.standard.dictionary(forKey: Self.automaticOrganizerFolderIDsKey) as? [String: String] ?? [:]
        var destinationFolders: [AutomaticAppFolderGroup: FolderInfo] = [:]
        var newlyCreatedGroups = Set<AutomaticAppFolderGroup>()
        var groupedApps: [AutomaticAppFolderGroup: [AppInfo]] = [:]
        var groupedPinnedPaths: [AutomaticAppFolderGroup: [String]] = [:]
        var groupByPath: [String: AutomaticAppFolderGroup] = [:]
        var organizedPaths = Set<String>()
        var createdFolderCount = 0
        var renamedFolderCount = 0
        var reclassifiedApps: [AppInfo] = []
        var removedAutomaticFolderIDs = Set<String>()
        var didMigrateLegacyCommunicationCategory = false

        func isLegacyCommunicationFolderName(_ name: String) -> Bool {
            let baseName = name.components(separatedBy: " · ").first ?? name
            return ["Communication", "Communications", "通讯"].contains {
                $0.localizedCaseInsensitiveCompare(baseName) == .orderedSame
            }
        }

        // The former Communications and Social Media buckets now share one
        // broad Social Media group. Preserve organizer-owned folder IDs and
        // user edits while merging the two old buckets when both exist.
        for suffix in ["", ".apple"] {
            let oldKey = "communication\(suffix)"
            let newKey = "socialMedia\(suffix)"
            guard let oldID = automaticFolderIDs.removeValue(forKey: oldKey) else { continue }
            didMigrateLegacyCommunicationCategory = true
            guard let oldIndex = folders.firstIndex(where: { $0.id == oldID }) else {
                if automaticFolderIDs[newKey] == nil { automaticFolderIDs[newKey] = oldID }
                continue
            }

            if let newID = automaticFolderIDs[newKey], newID != oldID,
               let newIndex = folders.firstIndex(where: { $0.id == newID }) {
                let oldFolder = folders[oldIndex]
                var newFolder = folders[newIndex]
                var knownPaths = Set(newFolder.apps.map { standardizedFilePath($0.url.path) })
                newFolder.apps.append(contentsOf: oldFolder.apps.filter {
                    knownPaths.insert(standardizedFilePath($0.url.path)).inserted
                })
                var knownPins = Set(newFolder.pinnedAppPaths.map(standardizedFilePath))
                newFolder.pinnedAppPaths.append(contentsOf: oldFolder.pinnedAppPaths.filter {
                    knownPins.insert(standardizedFilePath($0)).inserted
                })
                if isLegacyCommunicationFolderName(newFolder.name) {
                    let baseName = localized(.autoFolderSocialMedia)
                    newFolder.name = suffix.isEmpty ? baseName : "\(baseName) · \(localized(.autoFolderApple))"
                }
                folders[newIndex] = folderWithValidQuickLaunchPins(newFolder)
                folders.remove(at: oldIndex)
                removedAutomaticFolderIDs.insert(oldID)
                continue
            }

            automaticFolderIDs[newKey] = oldID
            if isLegacyCommunicationFolderName(folders[oldIndex].name) {
                var folder = folders[oldIndex]
                let baseName = localized(.autoFolderSocialMedia)
                folder.name = suffix.isEmpty ? baseName : "\(baseName) · \(localized(.autoFolderApple))"
                folders[oldIndex] = folderWithValidQuickLaunchPins(folder)
                renamedFolderCount += 1
            }
        }

        func folderName(for group: AutomaticAppFolderGroup) -> String {
            let baseName = group.customTitle ?? group.category.map { localized($0.localizationKey) } ?? ""
            guard group.isAppleOwned else { return baseName }
            return "\(baseName) · \(localized(.autoFolderApple))"
        }

        func isDefaultFolderName(_ name: String, for category: AutomaticAppCategory) -> Bool {
            AppLanguage.allCases.contains {
                LocalizationManager.shared.localized(category.localizationKey, language: $0) == name
            }
        }

        let generatedAppleFolderNamesByCategory = Dictionary(uniqueKeysWithValues:
            AutomaticAppCategory.allCases.map { category in
                let names = AppLanguage.allCases.map { language in
                    let categoryName = LocalizationManager.shared.localized(category.localizationKey, language: language)
                    let appleName = LocalizationManager.shared.localized(.autoFolderApple, language: language)
                    return "\(categoryName) · \(appleName)"
                }
                return (category.rawValue, names)
            }
        )
        let managedAppleCategoryIdentifiers = Set(AutomaticAppCategory.allCases.compactMap { category in
            automaticFolderIDs["\(category.rawValue).apple"] == nil ? nil : category.rawValue
        })
        let currentlyManagedFolderIDs = Set(automaticFolderIDs.values)

        // A previous organizer version could leave a second generated Apple
        // folder after ownership IDs changed. Reconcile only exact localized
        // generated names that duplicate a managed Apple folder, and only when
        // every member is Apple-owned. User-named and mixed folders stay intact.
        for folderIndex in folders.indices.reversed() {
            let legacyFolder = folders[folderIndex]
            var containsNonAppleApp = false
            for app in legacyFolder.apps where !AutomaticAppCategory.isAppleOwned(app) {
                containsNonAppleApp = true
                break
            }
            guard !currentlyManagedFolderIDs.contains(legacyFolder.id),
                  !legacyFolder.apps.isEmpty,
                  !containsNonAppleApp,
                  AutomaticFolderNameInference.managedAppleCategoryIdentifier(
                    for: legacyFolder.name,
                    generatedNamesByCategory: generatedAppleFolderNamesByCategory,
                    managedAppleCategoryIdentifiers: managedAppleCategoryIdentifiers
                  ) != nil else { continue }

            let appsToReconcile = legacyFolder.apps.compactMap { app -> (AppInfo, AutomaticAppFolderGroup)? in
                let path = standardizedFilePath(app.url.path)
                guard !hiddenAppPaths.contains(path),
                      AutomaticAppCategory.isAppleOwned(app),
                      let category = AutomaticAppCategory.classify(app) else { return nil }
                return (app, AutomaticAppFolderGroup(category: category, isAppleOwned: true))
            }
            guard !appsToReconcile.isEmpty else { continue }

            let reconciledPaths = Set(appsToReconcile.map { standardizedFilePath($0.0.url.path) })
            let pinnedPaths = Set(legacyFolder.pinnedAppPaths.map(standardizedFilePath))
            for (app, group) in appsToReconcile {
                let path = standardizedFilePath(app.url.path)
                groupByPath[path] = group
                groupedApps[group, default: []].append(app)
                organizedPaths.insert(path)
                if pinnedPaths.contains(path) {
                    groupedPinnedPaths[group, default: []].append(path)
                }
            }

            var remainingFolder = legacyFolder
            remainingFolder.apps.removeAll { reconciledPaths.contains(standardizedFilePath($0.url.path)) }
            remainingFolder = folderWithValidQuickLaunchPins(remainingFolder)
            if remainingFolder.apps.isEmpty {
                folders.remove(at: folderIndex)
                removedAutomaticFolderIDs.insert(legacyFolder.id)
            } else {
                folders[folderIndex] = remainingFolder
            }
        }

        // Repair generic names left by older imports or manually-created
        // placeholder folders. Derive a name from the folder's actual contents;
        // user-chosen names are preserved.
        let localizedCategoryNames = Dictionary(uniqueKeysWithValues: AutomaticAppCategory.allCases.map {
            ($0.rawValue, localized($0.localizationKey))
        })
        for index in folders.indices where AutomaticFolderNameInference.isPlaceholder(folders[index].name) {
            let visibleApps = folders[index].apps.filter {
                !hiddenAppPaths.contains(standardizedFilePath($0.url.path))
            }
            var allVisibleAppsAppleOwned = true
            for app in visibleApps where !AutomaticAppCategory.isAppleOwned(app) {
                allVisibleAppsAppleOwned = false
                break
            }
            guard !visibleApps.isEmpty,
                  let suggestedName = AutomaticFolderNameInference.suggestedName(
                    appNames: visibleApps.map(\.name),
                    categoryIdentifiers: visibleApps.compactMap { AutomaticAppCategory.classify($0)?.rawValue },
                    localizedCategoryNames: localizedCategoryNames,
                    allAppsAppleOwned: allVisibleAppsAppleOwned,
                    appleLabel: localized(.autoFolderApple)
                  ),
                  suggestedName != folders[index].name else { continue }
            var folder = folders[index]
            folder.name = suggestedName
            folder = folderWithValidQuickLaunchPins(folder)
            folders[index] = folder
            renamedFolderCount += 1
        }

        // Older organizer versions stored one folder per category, so those
        // folders may already mix Apple and third-party apps. Split only folders
        // that this organizer previously recorded; leave user-made folders alone.
        let legacyMappings = AutomaticAppCategory.allCases.compactMap { category -> (AutomaticAppCategory, String)? in
            guard let folderID = automaticFolderIDs[category.rawValue] else { return nil }
            return (category, folderID)
        }
        for (category, legacyFolderID) in legacyMappings {
            guard let legacyIndex = folders.firstIndex(where: { $0.id == legacyFolderID }) else { continue }
            let originalFolder = folders[legacyIndex]
            let appleApps = originalFolder.apps.filter { app in
                AutomaticAppCategory.isAppleOwned(app)
                    && !hiddenAppPaths.contains(standardizedFilePath(app.url.path))
            }
            guard !appleApps.isEmpty else { continue }

            let applePaths = Set(appleApps.map { standardizedFilePath($0.url.path) })
            let remainingApps = originalFolder.apps.filter {
                !applePaths.contains(standardizedFilePath($0.url.path))
            }
            let appleGroup = AutomaticAppFolderGroup(category: category, isAppleOwned: true)
            let appleFolderName = folderName(for: appleGroup)
            for app in appleApps {
                let path = standardizedFilePath(app.url.path)
                groupByPath[path] = appleGroup
                groupedApps[appleGroup, default: []].append(app)
                organizedPaths.insert(path)
            }

            if remainingApps.isEmpty {
                var folder = originalFolder
                folder.apps = appleApps
                if isDefaultFolderName(folder.name, for: category) {
                    folder.name = appleFolderName
                }
                folder = folderWithValidQuickLaunchPins(folder)
                folders[legacyIndex] = folder
                automaticFolderIDs.removeValue(forKey: category.rawValue)
                automaticFolderIDs[appleGroup.storageKey] = folder.id
                destinationFolders[appleGroup] = folder
                continue
            }

            var legacyFolder = originalFolder
            legacyFolder.apps = remainingApps
            legacyFolder = folderWithValidQuickLaunchPins(legacyFolder)
            folders[legacyIndex] = legacyFolder
            automaticFolderIDs[category.rawValue] = legacyFolder.id

            let savedAppleFolderID = automaticFolderIDs[appleGroup.storageKey]
            let existingAppleFolderIndex = folders.firstIndex(where: {
                $0.id == savedAppleFolderID && $0.id != legacyFolderID
            }) ?? folders.firstIndex(where: {
                $0.name == appleFolderName && $0.id != legacyFolderID
            })

            let requestedApplePins = originalFolder.pinnedAppPaths
                .map(standardizedFilePath)
                .filter(applePaths.contains)
            if let existingAppleFolderIndex {
                var appleFolder = folders[existingAppleFolderIndex]
                var knownPaths = Set(appleFolder.apps.map { standardizedFilePath($0.url.path) })
                let additions = appleApps.filter {
                    knownPaths.insert(standardizedFilePath($0.url.path)).inserted
                }
                appleFolder.apps.append(contentsOf: additions)
                var knownPins = Set(appleFolder.pinnedAppPaths)
                appleFolder.pinnedAppPaths.append(contentsOf: requestedApplePins.filter {
                    knownPins.insert($0).inserted
                })
                if isDefaultFolderName(appleFolder.name, for: category) {
                    appleFolder.name = appleFolderName
                }
                appleFolder = folderWithValidQuickLaunchPins(appleFolder)
                folders[existingAppleFolderIndex] = appleFolder
                destinationFolders[appleGroup] = appleFolder
                automaticFolderIDs[appleGroup.storageKey] = appleFolder.id
            } else {
                let appleFolder = FolderInfo(name: appleFolderName,
                                             apps: appleApps,
                                             pinnedAppPaths: Array(requestedApplePins))
                folders.append(appleFolder)
                destinationFolders[appleGroup] = appleFolder
                newlyCreatedGroups.insert(appleGroup)
                automaticFolderIDs[appleGroup.storageKey] = appleFolder.id
                createdFolderCount += 1
            }
        }

        // Re-check only folders previously created by this organizer. If a
        // newer rule now assigns one of their apps elsewhere (for example, a
        // social platform formerly grouped with communication apps), move it
        // through the normal grouping path. Hand-made folders are untouched.
        let previousCategoryGroups: [(storageKey: String, category: AutomaticAppCategory, isAppleOwned: Bool)] =
            AutomaticAppCategory.allCases.flatMap { category in
                [(category.rawValue, category, false),
                 ("\(category.rawValue).apple", category, true)]
            }
        for previousGroup in previousCategoryGroups {
            guard let folderID = automaticFolderIDs[previousGroup.storageKey],
                  let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { continue }
            let folder = folders[folderIndex]
            let movedApps = folder.apps.filter { app in
                guard !hiddenAppPaths.contains(standardizedFilePath(app.url.path)),
                      let newCategory = AutomaticAppCategory.classify(app) else { return false }
                let newPublisher = AutomaticAppCategory.isAppleOwned(app)
                return newCategory != previousGroup.category || newPublisher != previousGroup.isAppleOwned
            }
            guard !movedApps.isEmpty else { continue }

            let movedPaths = Set(movedApps.map { standardizedFilePath($0.url.path) })
            var updatedFolder = folder
            updatedFolder.apps.removeAll { movedPaths.contains(standardizedFilePath($0.url.path)) }
            updatedFolder = folderWithValidQuickLaunchPins(updatedFolder)
            reclassifiedApps.append(contentsOf: movedApps)

            if updatedFolder.apps.isEmpty {
                folders.remove(at: folderIndex)
                automaticFolderIDs.removeValue(forKey: previousGroup.storageKey)
                removedAutomaticFolderIDs.insert(folderID)
            } else {
                folders[folderIndex] = updatedFolder
            }
        }

        let appsAlreadyInFolders = Set(folders.flatMap { $0.apps.map { standardizedFilePath($0.url.path) } })
        var candidates: [AppInfo] = []
        var seenPaths = Set<String>()

        func appendCandidate(_ app: AppInfo) {
            let path = standardizedFilePath(app.url.path)
            guard !path.isEmpty,
                  !hiddenAppPaths.contains(path),
                  !appsAlreadyInFolders.contains(path),
                  seenPaths.insert(path).inserted else { return }
            candidates.append(app)
        }

        for item in items {
            if case .app(let app) = item { appendCandidate(app) }
        }
        for app in reclassifiedApps { appendCandidate(app) }
        for app in apps { appendCandidate(app) }

        // Duplicate display names are useful grouping evidence even when the
        // bundle metadata does not reveal a shared category. Keep Apple and
        // third-party apps in separate folders, consistent with category groups.
        let sameNameBuckets = Dictionary(grouping: candidates) {
            AutomaticFolderNameInference.normalizedKey($0.name)
        }
        for nameKey in sameNameBuckets.keys.sorted() {
            guard !nameKey.isEmpty, nameKey != "unknownapp" else { continue }
            let sameNameApps = sameNameBuckets[nameKey] ?? []
            guard sameNameApps.count >= 2 else { continue }
            for isAppleOwned in [false, true] {
                let matchingApps = sameNameApps.filter {
                    AutomaticAppCategory.isAppleOwned($0) == isAppleOwned
                }
                guard matchingApps.count >= 2,
                      let customTitle = matchingApps.first?.name.trimmingCharacters(in: .whitespacesAndNewlines),
                      !customTitle.isEmpty else { continue }
                let group = AutomaticAppFolderGroup(repeatedNameKey: nameKey,
                                                    customTitle: customTitle,
                                                    isAppleOwned: isAppleOwned)
                for app in matchingApps {
                    let path = standardizedFilePath(app.url.path)
                    groupByPath[path] = group
                    groupedApps[group, default: []].append(app)
                }
            }
        }

        for app in candidates {
            let path = standardizedFilePath(app.url.path)
            if groupByPath[path] != nil { continue }
            guard let category = AutomaticAppCategory.classify(app) else { continue }
            let group = AutomaticAppFolderGroup(category: category,
                                                isAppleOwned: AutomaticAppCategory.isAppleOwned(app))
            groupByPath[path] = group
            groupedApps[group, default: []].append(app)
        }

        let categoryGroups = AutomaticAppCategory.allCases.flatMap { category in
            [AutomaticAppFolderGroup(category: category, isAppleOwned: false),
             AutomaticAppFolderGroup(category: category, isAppleOwned: true)]
        }
        let repeatedNameGroups = groupedApps.keys
            .filter { $0.repeatedNameKey != nil }
            .sorted { $0.storageKey.localizedStandardCompare($1.storageKey) == .orderedAscending }
        let folderGroups = categoryGroups + repeatedNameGroups
        for group in folderGroups {
            let categoryApps = (groupedApps[group] ?? []).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard !categoryApps.isEmpty else { continue }

            let savedID = automaticFolderIDs[group.storageKey]
            let name = folderName(for: group)
            let otherGroupFolderIDs = Set(automaticFolderIDs.compactMap { key, value in
                key == group.storageKey ? nil : value
            })
            let existingFolderIndex = folders.firstIndex(where: { $0.id == savedID })
                ?? folders.firstIndex(where: { $0.name == name && !otherGroupFolderIDs.contains($0.id) })

            if let existingFolderIndex {
                var folder = folders[existingFolderIndex]
                var knownPaths = Set(folder.apps.map { standardizedFilePath($0.url.path) })
                let additions = categoryApps.filter {
                    knownPaths.insert(standardizedFilePath($0.url.path)).inserted
                }
                folder.apps.append(contentsOf: additions)
                var knownPins = Set(folder.pinnedAppPaths.map(standardizedFilePath))
                folder.pinnedAppPaths.append(contentsOf: (groupedPinnedPaths[group] ?? []).filter {
                    knownPins.insert(standardizedFilePath($0)).inserted
                })
                if group.isAppleOwned,
                   let category = group.category,
                   isDefaultFolderName(folder.name, for: category) {
                    folder.name = name
                }
                folder = folderWithValidQuickLaunchPins(folder)
                folders[existingFolderIndex] = folder
                destinationFolders[group] = folder
                automaticFolderIDs[group.storageKey] = folder.id
                organizedPaths.formUnion(additions.map { standardizedFilePath($0.url.path) })
                continue
            }

            // Keep Apple apps separate even when they are the only member of
            // their category; ordinary third-party groups still need a pair.
            let minimumCount = group.isAppleOwned ? 1 : (group.category?.minimumAppsForFolder ?? 2)
            guard categoryApps.count >= minimumCount else { continue }
            let folder = FolderInfo(name: name,
                                    apps: categoryApps,
                                    pinnedAppPaths: groupedPinnedPaths[group] ?? [])
            folders.append(folder)
            destinationFolders[group] = folder
            newlyCreatedGroups.insert(group)
            automaticFolderIDs[group.storageKey] = folder.id
            organizedPaths.formUnion(categoryApps.map { standardizedFilePath($0.url.path) })
            createdFolderCount += 1
        }

        let appleManagedFolderIDs = Set(automaticFolderIDs.compactMap { key, value in
            key.hasSuffix(".apple") ? value : nil
        })
        let currentAppleFolderIndices = items.enumerated().compactMap { index, item -> Int? in
            guard case .folder(let folder) = item,
                  appleManagedFolderIDs.contains(folder.id) else { return nil }
            return index
        }
        let appleFoldersAlreadyAtFront = currentAppleFolderIndices == Array(0..<currentAppleFolderIndices.count)
        let needsAppleFolderPrioritization = !currentAppleFolderIndices.isEmpty && !appleFoldersAlreadyAtFront

        guard !organizedPaths.isEmpty || renamedFolderCount > 0 || needsAppleFolderPrioritization
                || didMigrateLegacyCommunicationCategory else {
            return AutomaticAppOrganizationResult(appsOrganized: 0, foldersCreated: 0, foldersRenamed: 0)
        }

        var rebuiltItems: [LaunchpadItem] = []
        rebuiltItems.reserveCapacity(items.count)
        var insertedNewGroups = Set<AutomaticAppFolderGroup>()
        var visibleFolderIDs = Set<String>()
        var seenCandidatePaths = Set<String>()

        for item in items {
            switch item {
            case .app(let app):
                let path = standardizedFilePath(app.url.path)
                if let group = groupByPath[path],
                   organizedPaths.contains(path),
                   let folder = destinationFolders[group] {
                    seenCandidatePaths.insert(path)
                    if newlyCreatedGroups.contains(group), insertedNewGroups.insert(group).inserted {
                        rebuiltItems.append(.folder(folder))
                        visibleFolderIDs.insert(folder.id)
                    }
                } else {
                    rebuiltItems.append(item)
                }
            case .folder(let folder):
                if removedAutomaticFolderIDs.contains(folder.id) { continue }
                let current = folders.first(where: { $0.id == folder.id }) ?? folder
                rebuiltItems.append(.folder(current))
                visibleFolderIDs.insert(current.id)
            case .missingApp(let placeholder):
                rebuiltItems.append(.missingApp(placeholder))
            case .empty:
                break
            }
        }

        for app in candidates where !seenCandidatePaths.contains(standardizedFilePath(app.url.path)) {
            let path = standardizedFilePath(app.url.path)
            if let group = groupByPath[path],
               organizedPaths.contains(path),
               let folder = destinationFolders[group] {
                seenCandidatePaths.insert(path)
                if newlyCreatedGroups.contains(group), insertedNewGroups.insert(group).inserted {
                    rebuiltItems.append(.folder(folder))
                    visibleFolderIDs.insert(folder.id)
                }
            } else {
                rebuiltItems.append(.app(app))
            }
        }

        for group in folderGroups {
            guard let folder = destinationFolders[group], !visibleFolderIDs.contains(folder.id) else { continue }
            if newlyCreatedGroups.contains(group) {
                if insertedNewGroups.insert(group).inserted {
                    rebuiltItems.append(.folder(folder))
                    visibleFolderIDs.insert(folder.id)
                }
            } else {
                rebuiltItems.append(.folder(folder))
                visibleFolderIDs.insert(folder.id)
            }
        }

        // Put only folders owned by this organizer and explicitly marked as
        // Apple groups first; preserve the relative order of all remaining items.
        let appleFolders = rebuiltItems.filter { item in
            guard case .folder(let folder) = item else { return false }
            return appleManagedFolderIDs.contains(folder.id)
        }
        let otherItems = rebuiltItems.filter { item in
            guard case .folder(let folder) = item else { return true }
            return !appleManagedFolderIDs.contains(folder.id)
        }

        apps.removeAll { organizedPaths.contains(standardizedFilePath($0.url.path)) }
        items = filteredItemsRemovingHidden(from: appleFolders + otherItems)
        compactItemsWithinPages()
        removeEmptyPages()
        currentPage = 0
        searchText = ""
        UserDefaults.standard.set(automaticFolderIDs, forKey: Self.automaticOrganizerFolderIDsKey)

        triggerFolderUpdate()
        triggerGridRefresh()
        refreshCacheAfterFolderOperation()
        saveAllOrder()
        sortFolderAppsByUsage()

        let finalFolderByAppPath = folders.reduce(into: [String: String]()) { result, folder in
            for app in folder.apps {
                result[standardizedFilePath(app.url.path)] = folder.id
            }
        }
        let movedAppCount = Set(originalFolderByAppPath.keys).union(finalFolderByAppPath.keys).reduce(into: 0) { count, path in
            if originalFolderByAppPath[path] != finalFolderByAppPath[path] {
                count += 1
            }
        }
        let folderContentsChanged = folders.contains { folder in
            originalFolderContents[folder.id] != folder.apps.map { standardizedFilePath($0.url.path) }
        }
        let gridOrderChanged = originalItemOrder != items.map(\.id)
        if movedAppCount > 0 || folderContentsChanged || gridOrderChanged || renamedFolderCount > 0 {
            automaticOrganizationAnimationTrigger = UUID()
        }

        return AutomaticAppOrganizationResult(appsOrganized: movedAppCount,
                                              foldersCreated: createdFolderCount,
                                              foldersRenamed: renamedFolderCount)
    }
}
