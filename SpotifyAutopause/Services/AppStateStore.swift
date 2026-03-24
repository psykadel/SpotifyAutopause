import Foundation

actor AppStateStore {
    private let fileManager: FileManager
    private let stateFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var state: PersistedAppState

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        let supportDirectory = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Spotify Autopause", isDirectory: true)
        self.stateFileURL = supportDirectory.appendingPathComponent("state.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        self.state = Self.loadInitialState(from: stateFileURL, using: decoder)
    }

    func activityRecords() -> [ActivityRecord] {
        state.activityRecords.sorted { $0.timestamp > $1.timestamp }
    }

    func observedSources() -> [ObservedAudioSource] {
        Self.sortedSources(state.observedSources)
    }

    func monitoringConfiguration() -> MonitoringConfiguration {
        state.monitoringConfiguration ?? .default
    }

    func appendActivityRecords(_ records: [ActivityRecord], limit: Int) throws -> [ActivityRecord] {
        guard !records.isEmpty else {
            return activityRecords()
        }

        state.activityRecords.append(contentsOf: records)
        state.activityRecords.sort { $0.timestamp > $1.timestamp }

        if state.activityRecords.count > limit {
            state.activityRecords = Array(state.activityRecords.prefix(limit))
        }

        try persist()
        return activityRecords()
    }

    func clearActivityRecords() throws -> [ActivityRecord] {
        state.activityRecords = []
        try persist()
        return []
    }

    func mergeObservedSources(
        _ activeSources: [ObservedAudioSource],
        actionBySourceID: [String: ActivityAction]
    ) throws -> [ObservedAudioSource] {
        let ignoredIDs = Set(state.ignoredEntries.map(\.id))

        for source in activeSources {
            if let index = state.observedSources.firstIndex(where: { $0.id == source.id }) {
                var existing = state.observedSources[index]
                existing.displayName = source.displayName
                existing.bundleIdentifier = source.bundleIdentifier
                existing.executablePath = source.executablePath
                existing.lastSeenAt = source.lastSeenAt
                existing.seenCount += 1
                existing.isIgnored = existing.isIgnored || ignoredIDs.contains(existing.id)

                if let action = actionBySourceID[source.id] {
                    existing.lastTriggeredAction = action
                    existing.lastTriggeredAt = source.lastSeenAt
                }

                state.observedSources[index] = existing
            } else {
                var fresh = source
                fresh.seenCount = max(fresh.seenCount, 1)
                fresh.isIgnored = fresh.isIgnored || ignoredIDs.contains(fresh.id)

                if let action = actionBySourceID[source.id] {
                    fresh.lastTriggeredAction = action
                    fresh.lastTriggeredAt = source.lastSeenAt
                }

                state.observedSources.append(fresh)
            }
        }

        syncIgnoredEntries()
        try persist()
        return observedSources()
    }

    func setIgnored(_ ignored: Bool, sourceID: String) throws -> [ObservedAudioSource] {
        guard let index = state.observedSources.firstIndex(where: { $0.id == sourceID }) else {
            return observedSources()
        }

        state.observedSources[index].isIgnored = ignored
        syncIgnoredEntries()
        try persist()
        return observedSources()
    }

    func resetIgnoredApps() throws -> [ObservedAudioSource] {
        for index in state.observedSources.indices {
            state.observedSources[index].isIgnored = false
        }

        state.ignoredEntries = []
        try persist()
        return observedSources()
    }

    func setMonitoringConfiguration(_ configuration: MonitoringConfiguration) throws -> MonitoringConfiguration {
        state.monitoringConfiguration = configuration
        try persist()
        return monitoringConfiguration()
    }

    private func syncIgnoredEntries() {
        state.ignoredEntries = state.observedSources
            .filter(\.isIgnored)
            .map {
                IgnoredAppEntry(
                    id: $0.id,
                    displayName: $0.displayName,
                    bundleIdentifier: $0.bundleIdentifier,
                    executablePath: $0.executablePath,
                    updatedAt: $0.lastSeenAt
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func persist() throws {
        let directoryURL = stateFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }

    private static func loadInitialState(from fileURL: URL, using decoder: JSONDecoder) -> PersistedAppState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(PersistedAppState.self, from: data) else {
            return .empty
        }

        return state
    }

    private static func sortedSources(_ sources: [ObservedAudioSource]) -> [ObservedAudioSource] {
        sources.sorted { lhs, rhs in
            if lhs.lastSeenAt != rhs.lastSeenAt {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

actor ActivityStore {
    private let appStateStore: AppStateStore
    private let historyLimit: Int

    init(appStateStore: AppStateStore, historyLimit: Int) {
        self.appStateStore = appStateStore
        self.historyLimit = historyLimit
    }

    func load() async -> [ActivityRecord] {
        await appStateStore.activityRecords()
    }

    func append(_ records: [ActivityRecord]) async -> [ActivityRecord] {
        do {
            return try await appStateStore.appendActivityRecords(records, limit: historyLimit)
        } catch {
            return await appStateStore.activityRecords()
        }
    }

    func clear() async -> [ActivityRecord] {
        do {
            return try await appStateStore.clearActivityRecords()
        } catch {
            return await appStateStore.activityRecords()
        }
    }
}

actor MonitoringConfigurationStore {
    private let appStateStore: AppStateStore

    init(appStateStore: AppStateStore) {
        self.appStateStore = appStateStore
    }

    func load() async -> MonitoringConfiguration {
        await appStateStore.monitoringConfiguration()
    }

    func save(_ configuration: MonitoringConfiguration) async -> MonitoringConfiguration {
        do {
            return try await appStateStore.setMonitoringConfiguration(configuration)
        } catch {
            return await appStateStore.monitoringConfiguration()
        }
    }
}

actor IgnoredAppsStore {
    private let appStateStore: AppStateStore

    init(appStateStore: AppStateStore) {
        self.appStateStore = appStateStore
    }

    func load() async -> [ObservedAudioSource] {
        await appStateStore.observedSources()
    }

    func registerObservedSources(
        _ activeSources: [ObservedAudioSource],
        actionBySourceID: [String: ActivityAction]
    ) async -> [ObservedAudioSource] {
        do {
            return try await appStateStore.mergeObservedSources(activeSources, actionBySourceID: actionBySourceID)
        } catch {
            return await appStateStore.observedSources()
        }
    }

    func setIgnored(_ ignored: Bool, sourceID: String) async -> [ObservedAudioSource] {
        do {
            return try await appStateStore.setIgnored(ignored, sourceID: sourceID)
        } catch {
            return await appStateStore.observedSources()
        }
    }

    func reset() async -> [ObservedAudioSource] {
        do {
            return try await appStateStore.resetIgnoredApps()
        } catch {
            return await appStateStore.observedSources()
        }
    }

    func ignoredSourceIDs() async -> Set<String> {
        Set((await appStateStore.observedSources()).filter(\.isIgnored).map(\.id))
    }
}
