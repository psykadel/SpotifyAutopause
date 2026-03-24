import Foundation

@MainActor
final class SpotifyAutopauseViewModel: ObservableObject {
    @Published private(set) var snapshot: MonitoringSnapshot = .empty
    @Published private(set) var activityRecords: [ActivityRecord] = []
    @Published private(set) var observedSources: [ObservedAudioSource] = []
    @Published private(set) var pollInspectionSnapshot: PollInspectionSnapshot?
    @Published private(set) var pollInspectionErrorMessage: String?
    @Published private(set) var isRefreshingPollInspection = false
    @Published private(set) var configuration: MonitoringConfiguration

    private let audioSourceMonitor: AudioSourceMonitor
    private let spotifyController: any SpotifyControlling
    private let activityStore: ActivityStore
    private let ignoredAppsStore: IgnoredAppsStore
    private let configurationStore: MonitoringConfigurationStore

    private var monitoringEngine = MonitoringEngine()
    private var monitoringTask: Task<Void, Never>?
    private var lastActionableSources: [ObservedAudioSource] = []

    init(
        configuration: MonitoringConfiguration = .default,
        audioSourceMonitor: AudioSourceMonitor = AudioSourceMonitor(),
        spotifyController: any SpotifyControlling = SpotifyController(),
        appStateStore: AppStateStore = AppStateStore()
    ) {
        self._configuration = Published(initialValue: configuration)
        self.audioSourceMonitor = audioSourceMonitor
        self.spotifyController = spotifyController
        self.activityStore = ActivityStore(appStateStore: appStateStore, historyLimit: configuration.storedHistoryLimit)
        self.ignoredAppsStore = IgnoredAppsStore(appStateStore: appStateStore)
        self.configurationStore = MonitoringConfigurationStore(appStateStore: appStateStore)
    }

    deinit {
        monitoringTask?.cancel()
    }

    var visibleActivityRecords: [ActivityRecord] {
        Array(activityRecords.prefix(configuration.visibleHistoryLimit))
    }

    var manageableSources: [ObservedAudioSource] {
        observedSources.filter { !$0.isAlwaysIgnored }
    }

    var candidateIgnoredSources: [ObservedAudioSource] {
        manageableSources.filter { !$0.isIgnored }
    }

    var savedIgnoredSources: [ObservedAudioSource] {
        manageableSources
            .filter(\.isIgnored)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    var currentSourceSummary: String {
        snapshot.currentAudioSummary
    }

    func start() {
        guard monitoringTask == nil else {
            return
        }

        monitoringTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.loadPersistedState()

            if self.configuration.startupDelaySeconds > 0 {
                try? await Task.sleep(for: .seconds(self.configuration.startupDelaySeconds))
            }

            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: self.pollDelay)
            }
        }
    }

    func setIgnored(_ isIgnored: Bool, for sourceID: String) {
        Task { [weak self] in
            guard let self else {
                return
            }

            let sourceName = self.observedSources.first(where: { $0.id == sourceID })?.displayName ?? "Unknown Source"
            self.observedSources = await self.ignoredAppsStore.setIgnored(isIgnored, sourceID: sourceID)
            self.snapshot = self.rebuiltSnapshot(
                from: self.snapshot,
                using: self.observedSources,
                spotifyState: self.snapshot.spotifyState
            )

            let record = ActivityRecord(
                action: .ignoreRuleUpdated,
                sourceIDs: [sourceID],
                sourceDisplayNames: [sourceName],
                visibleSourceIDs: [sourceID],
                visibleSourceDisplayNames: [sourceName],
                spotifyStateBefore: self.snapshot.spotifyState,
                spotifyStateAfter: self.snapshot.spotifyState,
                ignored: isIgnored,
                note: isIgnored ? "This source will no longer pause Spotify." : "This source can pause Spotify again."
            )

            self.activityRecords = await self.activityStore.append([record])
            self.snapshot.lastAction = self.activityRecords.first
        }
    }

    func clearRecentActivity() {
        Task { [weak self] in
            guard let self else {
                return
            }

            self.activityRecords = await self.activityStore.clear()
            self.snapshot.lastAction = nil
        }
    }

    func resetIgnoredApps() {
        Task { [weak self] in
            guard let self else {
                return
            }

            self.observedSources = await self.ignoredAppsStore.reset()
            self.snapshot = self.rebuiltSnapshot(
                from: self.snapshot,
                using: self.observedSources,
                spotifyState: self.snapshot.spotifyState
            )
        }
    }

    func refreshPollInspection() {
        Task { [weak self] in
            guard let self else {
                return
            }

            self.isRefreshingPollInspection = true
            defer { self.isRefreshingPollInspection = false }

            do {
                self.pollInspectionSnapshot = try await self.audioSourceMonitor.inspectPollingCommands()
                self.pollInspectionErrorMessage = nil
            } catch {
                self.pollInspectionErrorMessage = error.localizedDescription
            }
        }
    }

    private func loadPersistedState() async {
        configuration = await configurationStore.load()
        activityRecords = await activityStore.load()
        observedSources = await ignoredAppsStore.load()
        snapshot.lastAction = activityRecords.first
    }

    private func pollOnce() async {
        let now = Date()
        let spotifyStateBefore = await readSpotifyState()

        let observation: AudioSourceObservation
        do {
            observation = try await audioSourceMonitor.fetchActiveSources(at: now)
        } catch {
            let errorMessage = error.localizedDescription
            if snapshot.lastErrorMessage != errorMessage {
                let errorRecord = makeMonitorErrorRecord(
                    message: errorMessage,
                    sources: [],
                    visibleSources: [],
                    spotifyBefore: spotifyStateBefore,
                    spotifyAfter: spotifyStateBefore
                )
                activityRecords = await activityStore.append([errorRecord])
                snapshot.lastAction = activityRecords.first
            }

            snapshot.lastUpdatedAt = now
            snapshot.spotifyState = spotifyStateBefore
            snapshot.externalAudioActive = false
            snapshot.candidateAudioActive = false
            snapshot.activeSources = []
            snapshot.actionableSources = []
            snapshot.ignoredSources = []
            snapshot.lastErrorMessage = errorMessage
            return
        }

        let activeSources = observation.activeSources
        let ignoredSourceIDs = Set(observedSources.filter(\.isIgnored).map(\.id))
        let outcome = monitoringEngine.evaluate(
            spotifyState: spotifyStateBefore,
            activeSources: activeSources,
            ignoredSourceIDs: ignoredSourceIDs
        )

        var spotifyStateAfter = spotifyStateBefore
        var activity: [ActivityRecord] = []
        var sourceActions: [String: ActivityAction] = [:]
        let previousStatusMessage = snapshot.lastErrorMessage
        var statusMessage = observation.warningMessage
        var recordedMonitorMessages = Set<String>()

        let decoratedCurrentSources = applyingPersistedIgnoreFlags(to: activeSources, using: observedSources)
        let currentActionableSources = decoratedCurrentSources.filter { !$0.isEffectivelyIgnored }
        let currentIgnoredSources = decoratedCurrentSources.filter(\.isEffectivelyIgnored)

        if let warningMessage = observation.warningMessage, warningMessage != previousStatusMessage {
            activity.append(
                makeMonitorErrorRecord(
                    message: warningMessage,
                    sources: monitorErrorSources(from: observation.probeDiagnostics),
                    visibleSources: [],
                    spotifyBefore: spotifyStateBefore,
                    spotifyAfter: spotifyStateBefore
                )
            )
            recordedMonitorMessages.insert(warningMessage)
        }

        for event in outcome.events {
            switch event {
            case .actionableSourcesStarted:
                activity.append(
                    makeActivityRecord(
                        action: .externalAudioDetected,
                        sources: currentActionableSources,
                        visibleSources: currentActionableSources,
                        spotifyBefore: spotifyStateBefore,
                        spotifyAfter: spotifyStateBefore,
                        ignored: false,
                        note: "Actionable audio sources became active."
                    )
                )
                sourceActions.merge(currentActionableSources.reduce(into: [:]) { $0[$1.id] = .externalAudioDetected }) { _, new in new }
            case .actionableSourcesChanged:
                activity.append(
                    makeActivityRecord(
                        action: .externalAudioChanged,
                        sources: currentActionableSources,
                        visibleSources: currentActionableSources,
                        spotifyBefore: spotifyStateBefore,
                        spotifyAfter: spotifyStateBefore,
                        ignored: false,
                        note: "The active audio source list changed."
                    )
                )
                sourceActions.merge(currentActionableSources.reduce(into: [:]) { $0[$1.id] = .externalAudioChanged }) { _, new in new }
            case .actionableSourcesEnded:
                activity.append(
                    makeActivityRecord(
                        action: .externalAudioEnded,
                        sources: lastActionableSources,
                        visibleSources: [],
                        spotifyBefore: spotifyStateBefore,
                        spotifyAfter: spotifyStateBefore,
                        ignored: false,
                        note: "All actionable audio sources stopped."
                    )
                )
                sourceActions.merge(lastActionableSources.reduce(into: [:]) { $0[$1.id] = .externalAudioEnded }) { _, new in new }
            case .ignoredSourcesObserved:
                let userIgnoredSources = currentIgnoredSources.filter { !$0.isAlwaysIgnored }
                if !userIgnoredSources.isEmpty {
                    activity.append(
                        makeActivityRecord(
                            action: .ignoredAudioDetected,
                            sources: userIgnoredSources,
                            visibleSources: userIgnoredSources,
                            spotifyBefore: spotifyStateBefore,
                            spotifyAfter: spotifyStateBefore,
                            ignored: true,
                            note: "Ignored audio is active, so Spotify is left alone."
                        )
                    )
                    sourceActions.merge(userIgnoredSources.reduce(into: [:]) { $0[$1.id] = .ignoredAudioDetected }) { _, new in new }
                }
            }
        }

        if let command = outcome.command {
            let commandSources = command == .pause ? currentActionableSources : lastActionableSources
            let commandVisibleSources = command == .pause ? currentActionableSources : [ObservedAudioSource]()

            do {
                try await spotifyController.perform(command)
                spotifyStateAfter = await settledSpotifyState(after: command) { fallback in
                    await readSpotifyState(fallback: fallback)
                }

                let commandAction: ActivityAction = command == .pause ? .spotifyPaused : .spotifyResumed
                activity.append(
                    makeActivityRecord(
                        action: commandAction,
                        sources: commandSources,
                        visibleSources: commandVisibleSources,
                        spotifyBefore: spotifyStateBefore,
                        spotifyAfter: spotifyStateAfter,
                        ignored: false,
                        note: command == .pause
                            ? "Spotify was paused because other audio started."
                            : "Spotify resumed after the other audio stopped."
                    )
                )
                sourceActions.merge(commandSources.reduce(into: [:]) { $0[$1.id] = commandAction }) { _, new in new }
            } catch {
                monitoringEngine.commandFailed(command)
                statusMessage = error.localizedDescription
                if statusMessage != previousStatusMessage, let statusMessage, !recordedMonitorMessages.contains(statusMessage) {
                    activity.append(
                        makeMonitorErrorRecord(
                            message: statusMessage,
                            sources: commandSources,
                            visibleSources: commandVisibleSources,
                            spotifyBefore: spotifyStateBefore,
                            spotifyAfter: spotifyStateBefore
                        )
                    )
                    recordedMonitorMessages.insert(statusMessage)
                }
            }
        }

        observedSources = await ignoredAppsStore.registerObservedSources(activeSources, actionBySourceID: sourceActions)
        if !activity.isEmpty {
            activityRecords = await activityStore.append(activity)
        }

        let refreshedSources = applyingPersistedIgnoreFlags(to: activeSources, using: observedSources)
        let refreshedActionableSources = refreshedSources.filter { !$0.isEffectivelyIgnored }
        let refreshedIgnoredSources = refreshedSources.filter(\.isEffectivelyIgnored)

        snapshot = MonitoringSnapshot(
            spotifyState: spotifyStateAfter,
            externalAudioActive: !refreshedActionableSources.isEmpty,
            candidateAudioActive: observation.hasCandidateProcesses,
            activeSources: refreshedSources,
            actionableSources: refreshedActionableSources,
            ignoredSources: refreshedIgnoredSources,
            lastAction: activityRecords.first ?? snapshot.lastAction,
            lastUpdatedAt: now,
            lastErrorMessage: statusMessage
        )

        lastActionableSources = refreshedActionableSources
    }

    private func makeActivityRecord(
        action: ActivityAction,
        sources: [ObservedAudioSource],
        visibleSources: [ObservedAudioSource],
        spotifyBefore: SpotifyPlayerState,
        spotifyAfter: SpotifyPlayerState,
        ignored: Bool,
        note: String
    ) -> ActivityRecord {
        ActivityRecord(
            action: action,
            sourceIDs: sources.map(\.id),
            sourceDisplayNames: sources.map(\.displayName),
            visibleSourceIDs: visibleSources.map(\.id),
            visibleSourceDisplayNames: visibleSources.map(\.displayName),
            spotifyStateBefore: spotifyBefore,
            spotifyStateAfter: spotifyAfter,
            ignored: ignored,
            note: note
        )
    }

    private func rebuiltSnapshot(
        from snapshot: MonitoringSnapshot,
        using persistedSources: [ObservedAudioSource],
        spotifyState: SpotifyPlayerState
    ) -> MonitoringSnapshot {
        let activeSources = applyingPersistedIgnoreFlags(to: snapshot.activeSources, using: persistedSources)
        let actionableSources = activeSources.filter { !$0.isEffectivelyIgnored }
        let ignoredSources = activeSources.filter(\.isEffectivelyIgnored)

        return MonitoringSnapshot(
            spotifyState: spotifyState,
            externalAudioActive: !actionableSources.isEmpty,
            candidateAudioActive: snapshot.candidateAudioActive,
            activeSources: activeSources,
            actionableSources: actionableSources,
            ignoredSources: ignoredSources,
            lastAction: snapshot.lastAction,
            lastUpdatedAt: snapshot.lastUpdatedAt,
            lastErrorMessage: snapshot.lastErrorMessage
        )
    }

    private func applyingPersistedIgnoreFlags(
        to liveSources: [ObservedAudioSource],
        using persistedSources: [ObservedAudioSource]
    ) -> [ObservedAudioSource] {
        let persistedLookup = Dictionary(uniqueKeysWithValues: persistedSources.map { ($0.id, $0) })

        return liveSources.map { source in
            guard let persisted = persistedLookup[source.id] else {
                return source
            }

            var merged = source
            merged.isIgnored = persisted.isIgnored
            merged.seenCount = persisted.seenCount
            merged.lastTriggeredAt = persisted.lastTriggeredAt
            merged.lastTriggeredAction = persisted.lastTriggeredAction
            return merged
        }
    }

    private func readSpotifyState(fallback: SpotifyPlayerState = .unknown) async -> SpotifyPlayerState {
        do {
            return try await spotifyController.currentState()
        } catch {
            snapshot.lastErrorMessage = error.localizedDescription
            return fallback
        }
    }

    func updateConfiguration(_ updatedConfiguration: MonitoringConfiguration) {
        Task { [weak self] in
            guard let self else {
                return
            }

            self.configuration = await self.configurationStore.save(updatedConfiguration)
        }
    }

    func resetConfigurationToDefaults() {
        updateConfiguration(.default)
    }

    private var pollDelay: Duration {
        monitoringPollDelay(
            configuration: configuration,
            externalAudioActive: snapshot.externalAudioActive,
            candidateAudioActive: snapshot.candidateAudioActive,
            waitingToResumeSpotify: monitoringEngine.shouldResumeSpotify
        )
    }

    private func makeMonitorErrorRecord(
        message: String,
        sources: [ObservedAudioSource],
        visibleSources: [ObservedAudioSource],
        spotifyBefore: SpotifyPlayerState,
        spotifyAfter: SpotifyPlayerState
    ) -> ActivityRecord {
        ActivityRecord(
            action: .monitorError,
            sourceIDs: sources.map(\.id),
            sourceDisplayNames: sources.map(\.displayName),
            visibleSourceIDs: visibleSources.map(\.id),
            visibleSourceDisplayNames: visibleSources.map(\.displayName),
            spotifyStateBefore: spotifyBefore,
            spotifyStateAfter: spotifyAfter,
            ignored: false,
            note: message
        )
    }

    private func monitorErrorSources(from diagnostics: [ProbeInspectionResult]) -> [ObservedAudioSource] {
        var orderedSources: [ObservedAudioSource] = []
        var seenSourceIDs: Set<String> = []

        for diagnostic in diagnostics {
            guard seenSourceIDs.insert(diagnostic.sourceID).inserted else {
                continue
            }

            orderedSources.append(
                ObservedAudioSource(
                    id: diagnostic.sourceID,
                    displayName: diagnostic.displayName,
                    bundleIdentifier: nil,
                    executablePath: nil,
                    lastSeenAt: Date(),
                    lastTriggeredAt: nil,
                    lastTriggeredAction: nil,
                    seenCount: 0,
                    isIgnored: false
                )
            )
        }

        return orderedSources
    }
}

func monitoringPollDelay(
    configuration: MonitoringConfiguration,
    externalAudioActive: Bool,
    candidateAudioActive: Bool,
    waitingToResumeSpotify: Bool
) -> Duration {
    if waitingToResumeSpotify || candidateAudioActive {
        return .milliseconds(configuration.resumeWatchPollIntervalMilliseconds)
    }

    if externalAudioActive {
        return .seconds(configuration.activePollIntervalSeconds)
    }

    return .seconds(configuration.idlePollIntervalSeconds)
}

func settledSpotifyState(
    after command: SpotifyControlCommand,
    maxAttempts: Int = 4,
    retryDelay: Duration = .milliseconds(150),
    readState: (_ fallback: SpotifyPlayerState) async -> SpotifyPlayerState
) async -> SpotifyPlayerState {
    let expectedState = command.expectedSpotifyState
    let staleState = command.staleSpotifyState
    let attempts = max(1, maxAttempts)

    var lastObservedState = expectedState

    for attempt in 0..<attempts {
        let observedState = await readState(expectedState)
        lastObservedState = observedState

        if observedState == expectedState || observedState == .notRunning {
            return observedState
        }

        if attempt < attempts - 1 {
            try? await Task.sleep(for: retryDelay)
        }
    }

    return lastObservedState == staleState ? expectedState : lastObservedState
}

private extension SpotifyControlCommand {
    var expectedSpotifyState: SpotifyPlayerState {
        switch self {
        case .pause:
            return .paused
        case .resume:
            return .playing
        }
    }

    var staleSpotifyState: SpotifyPlayerState {
        switch self {
        case .pause:
            return .playing
        case .resume:
            return .paused
        }
    }
}
