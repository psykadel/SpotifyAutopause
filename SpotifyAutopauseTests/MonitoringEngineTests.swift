import XCTest
@testable import SpotifyAutopause

final class MonitoringEngineTests: XCTestCase {
    func testFirstActionableAudioStartPausesSpotifyWhenSpotifyIsPlaying() {
        var engine = MonitoringEngine()

        let outcome = engine.evaluate(
            spotifyState: .playing,
            activeSources: [source(id: "bundle:com.apple.Safari", name: "Safari")],
            ignoredSourceIDs: []
        )

        XCTAssertEqual(outcome.events, [.actionableSourcesStarted])
        XCTAssertEqual(outcome.command, .pause)
        XCTAssertEqual(outcome.actionableSources.map(\.displayName), ["Safari"])
    }

    func testIgnoredOnlyAudioDoesNotPauseSpotify() {
        var engine = MonitoringEngine()
        let ignored = source(id: "bundle:com.apple.shortcuts", name: "Shortcuts Events")

        let outcome = engine.evaluate(
            spotifyState: .playing,
            activeSources: [ignored],
            ignoredSourceIDs: [ignored.id]
        )

        XCTAssertEqual(outcome.events, [.ignoredSourcesObserved])
        XCTAssertNil(outcome.command)
        XCTAssertEqual(outcome.ignoredSources.map(\.displayName), ["Shortcuts Events"])
    }

    func testStoppingActionableAudioResumesSpotifyOnlyAfterOwnPause() {
        var engine = MonitoringEngine()
        _ = engine.evaluate(
            spotifyState: .playing,
            activeSources: [source(id: "bundle:com.apple.Safari", name: "Safari")],
            ignoredSourceIDs: []
        )

        let stoppedOutcome = engine.evaluate(
            spotifyState: .paused,
            activeSources: [],
            ignoredSourceIDs: []
        )

        XCTAssertEqual(stoppedOutcome.events, [.actionableSourcesEnded])
        XCTAssertEqual(stoppedOutcome.command, .resume)
    }

    func testStoppingActionableAudioDoesNotResumeWhenSpotifyWasAlreadyPaused() {
        var engine = MonitoringEngine()
        _ = engine.evaluate(
            spotifyState: .paused,
            activeSources: [source(id: "bundle:com.apple.Safari", name: "Safari")],
            ignoredSourceIDs: []
        )

        let stoppedOutcome = engine.evaluate(
            spotifyState: .paused,
            activeSources: [],
            ignoredSourceIDs: []
        )

        XCTAssertEqual(stoppedOutcome.events, [.actionableSourcesEnded])
        XCTAssertNil(stoppedOutcome.command)
    }

    func testSnapshotSummariesHideSpotifyFromUserVisibleStatuses() {
        let spotify = source(id: "bundle:com.spotify.client", name: "Spotify")
        let safari = source(id: "bundle:com.apple.Safari", name: "Safari", ignored: true)

        let spotifyOnly = MonitoringSnapshot(
            spotifyState: .playing,
            externalAudioActive: false,
            activeSources: [spotify],
            actionableSources: [],
            ignoredSources: [spotify],
            lastAction: nil,
            lastUpdatedAt: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(spotifyOnly.userVisibleActiveSources, [])
        XCTAssertEqual(spotifyOnly.userVisibleIgnoredSources, [])
        XCTAssertEqual(spotifyOnly.currentAudioSummary, "No external audio detected")
        XCTAssertEqual(spotifyOnly.currentAudioDetailSummary, "Spotify Autopause checks the system audio path every few seconds.")

        let ignoredSafari = MonitoringSnapshot(
            spotifyState: .paused,
            externalAudioActive: false,
            activeSources: [spotify, safari],
            actionableSources: [],
            ignoredSources: [spotify, safari],
            lastAction: nil,
            lastUpdatedAt: nil,
            lastErrorMessage: nil
        )

        XCTAssertEqual(ignoredSafari.userVisibleActiveSources.map(\.displayName), ["Safari"])
        XCTAssertEqual(ignoredSafari.userVisibleIgnoredSources.map(\.displayName), ["Safari"])
        XCTAssertEqual(ignoredSafari.currentAudioSummary, "Only ignored audio is active")
        XCTAssertEqual(ignoredSafari.currentAudioDetailSummary, "1 source is visible in the audio path.")
    }

    func testSettledSpotifyStateRetriesResumeUntilSpotifyReportsPlaying() async {
        let reader = StateSequenceReader(states: [.paused, .playing])

        let resolved = await settledSpotifyState(after: .resume, maxAttempts: 3, retryDelay: .zero) { _ in
            await reader.next()
        }

        XCTAssertEqual(resolved, .playing)
    }

    func testSettledSpotifyStateTreatsRepeatedPausedResumeReadbackAsStale() async {
        let reader = StateSequenceReader(states: [.paused, .paused, .paused])

        let resolved = await settledSpotifyState(after: .resume, maxAttempts: 3, retryDelay: .zero) { _ in
            await reader.next()
        }

        XCTAssertEqual(resolved, .playing)
    }

    func testSettledSpotifyStatePreservesNotRunningAfterResumeAttempt() async {
        let reader = StateSequenceReader(states: [.notRunning])

        let resolved = await settledSpotifyState(after: .resume, maxAttempts: 1, retryDelay: .zero) { _ in
            await reader.next()
        }

        XCTAssertEqual(resolved, .notRunning)
    }

    func testSpotifyTransitionSummaryNormalizesLegacyResumedRows() {
        let record = ActivityRecord(
            action: .spotifyResumed,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            spotifyStateBefore: .paused,
            spotifyStateAfter: .paused,
            ignored: false,
            note: "Spotify resumed after the other audio stopped."
        )

        XCTAssertEqual(record.spotifyTransitionSummary, "Paused -> Playing")
    }

    func testSpotifyTransitionSummaryIsBlankWhenStateDidNotChange() {
        let record = ActivityRecord(
            action: .externalAudioChanged,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            spotifyStateBefore: .paused,
            spotifyStateAfter: .paused,
            ignored: false,
            note: "Firefox changed audio output."
        )

        XCTAssertEqual(record.spotifyTransitionSummary, "")
    }

    func testVisibleSourceSummaryUsesExplicitVisibleSourcesForFreshActiveRows() {
        let record = ActivityRecord(
            action: .externalAudioChanged,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            visibleSourceIDs: ["bundle:org.mozilla.firefox"],
            visibleSourceDisplayNames: ["Firefox"],
            spotifyStateBefore: .paused,
            spotifyStateAfter: .paused,
            ignored: false,
            note: "Firefox changed audio output."
        )

        XCTAssertEqual(record.sourceSummary, "Firefox")
        XCTAssertEqual(record.visibleSourceSummary, "Firefox")
    }

    func testVisibleSourceSummaryHidesFreshEndedAndResumedRowsWhileKeepingCausalSourceContext() {
        let ended = ActivityRecord(
            action: .externalAudioEnded,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            visibleSourceIDs: [],
            visibleSourceDisplayNames: [],
            spotifyStateBefore: .paused,
            spotifyStateAfter: .paused,
            ignored: false,
            note: "All actionable audio sources stopped."
        )

        let resumed = ActivityRecord(
            action: .spotifyResumed,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            visibleSourceIDs: [],
            visibleSourceDisplayNames: [],
            spotifyStateBefore: .paused,
            spotifyStateAfter: .playing,
            ignored: false,
            note: "Spotify resumed after the other audio stopped."
        )

        XCTAssertEqual(ended.sourceSummary, "Firefox")
        XCTAssertEqual(ended.visibleSourceSummary, "")
        XCTAssertEqual(resumed.sourceSummary, "Firefox")
        XCTAssertEqual(resumed.visibleSourceSummary, "")
    }

    func testLegacyEndedAndResumedRowsDecodeWithBlankVisibleSourceSummary() throws {
        let ended = try legacyRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            action: .externalAudioEnded
        )
        let resumed = try legacyRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            action: .spotifyResumed
        )

        XCTAssertNil(ended.visibleSourceDisplayNames)
        XCTAssertNil(resumed.visibleSourceDisplayNames)
        XCTAssertEqual(ended.visibleSourceSummary, "")
        XCTAssertEqual(resumed.visibleSourceSummary, "")
    }

    func testLegacyRowsWithoutVisibleSourcesStillShowSourceNamesForActiveEvents() {
        let record = ActivityRecord(
            action: .spotifyPaused,
            sourceIDs: ["bundle:org.mozilla.firefox"],
            sourceDisplayNames: ["Firefox"],
            spotifyStateBefore: .playing,
            spotifyStateAfter: .paused,
            ignored: false,
            note: "Spotify was paused because other audio started."
        )

        XCTAssertEqual(record.visibleSourceSummary, "Firefox")
    }

    func testMonitoringPollDelayUsesResumeWatchWhileAwaitingResume() {
        let configuration = MonitoringConfiguration(
            activePollIntervalSeconds: 2,
            idlePollIntervalSeconds: 3,
            resumeWatchPollIntervalMilliseconds: 750
        )

        let delay = monitoringPollDelay(
            configuration: configuration,
            externalAudioActive: true,
            waitingToResumeSpotify: true
        )

        XCTAssertEqual(delay, .milliseconds(750))
    }

    func testMonitoringPollDelayUsesActiveIntervalWhenNotAwaitingResume() {
        let configuration = MonitoringConfiguration(
            activePollIntervalSeconds: 2,
            idlePollIntervalSeconds: 3,
            resumeWatchPollIntervalMilliseconds: 750
        )

        let delay = monitoringPollDelay(
            configuration: configuration,
            externalAudioActive: true,
            waitingToResumeSpotify: false
        )

        XCTAssertEqual(delay, .seconds(2))
    }

    func testMonitoringPollDelayUsesIdleIntervalWhenNoExternalAudioIsActive() {
        let configuration = MonitoringConfiguration(
            activePollIntervalSeconds: 2,
            idlePollIntervalSeconds: 3,
            resumeWatchPollIntervalMilliseconds: 750
        )

        let delay = monitoringPollDelay(
            configuration: configuration,
            externalAudioActive: false,
            waitingToResumeSpotify: false
        )

        XCTAssertEqual(delay, .seconds(3))
    }

    func testPersistedIgnoreFlagsAndHistoryRoundTrip() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppStateStore(baseDirectoryURL: baseDirectory)
        let source = source(id: "bundle:com.apple.Safari", name: "Safari")

        _ = try await store.mergeObservedSources([source], actionBySourceID: [source.id: .externalAudioDetected])
        _ = try await store.setIgnored(true, sourceID: source.id)
        _ = try await store.appendActivityRecords([
            ActivityRecord(
                action: .spotifyPaused,
                sourceIDs: [source.id],
                sourceDisplayNames: [source.displayName],
                visibleSourceIDs: [source.id],
                visibleSourceDisplayNames: [source.displayName],
                spotifyStateBefore: .playing,
                spotifyStateAfter: .paused,
                ignored: false,
                note: "Paused for Safari."
            )
        ], limit: MonitoringConfiguration.default.storedHistoryLimit)

        let reloadedStore = AppStateStore(baseDirectoryURL: baseDirectory)
        let observed = await reloadedStore.observedSources()
        let history = await reloadedStore.activityRecords()

        XCTAssertEqual(observed.count, 1)
        XCTAssertTrue(observed[0].isIgnored)
        XCTAssertEqual(observed[0].lastTriggeredAction, .externalAudioDetected)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].action, .spotifyPaused)
        XCTAssertEqual(history[0].visibleSourceSummary, "Safari")
    }

    func testInspectPollingCommandsIncludesPmsetAndPerPIDPsOutput() async throws {
        let runner = MockShellCommandRunner(resultsByInvocation: [
            .init(executable: "/usr/bin/pmset", arguments: ["-g", "assertions"]): .init(
                status: 0,
                stdout: """
                2026-03-23 18:00:00 -0500
                Assertion status system-wide:
                   PreventUserIdleSystemSleep    0
                   PreventSystemSleep            0
                   ExternalMedia                  1
                Listed by owning process:
                   pid 321(Firefox): [0x0000000000000001] 00:00:10 AudioPlayback named: "Audio-Playing"
                """,
                stderr: ""
            ),
            .init(executable: "/bin/ps", arguments: ["-p", "321", "-o", "command="]): .init(
                status: 0,
                stdout: "/Applications/Firefox.app/Contents/MacOS/firefox\n",
                stderr: ""
            )
        ])
        let monitor = AudioSourceMonitor(runner: runner)

        let snapshot = try await monitor.inspectPollingCommands(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.entries.map(\.commandLine), [
            "/usr/bin/pmset -g assertions",
            "/bin/ps -p 321 -o command="
        ])
        XCTAssertEqual(snapshot.entries[0].result.status, 0)
        XCTAssertTrue(snapshot.entries[0].result.stdout.contains("Audio-Playing"))
        XCTAssertEqual(snapshot.entries[1].result.stdout, "/Applications/Firefox.app/Contents/MacOS/firefox\n")
    }

    func testInspectPollingCommandsReturnsPmsetFailureWithoutPsEntries() async throws {
        let runner = MockShellCommandRunner(resultsByInvocation: [
            .init(executable: "/usr/bin/pmset", arguments: ["-g", "assertions"]): .init(
                status: 1,
                stdout: "",
                stderr: "pmset failed"
            )
        ])
        let monitor = AudioSourceMonitor(runner: runner)

        let snapshot = try await monitor.inspectPollingCommands(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries[0].commandLine, "/usr/bin/pmset -g assertions")
        XCTAssertEqual(snapshot.entries[0].result.status, 1)
        XCTAssertEqual(snapshot.entries[0].result.stderr, "pmset failed")
    }

    func testClearingActivityAndResettingIgnoredAppsPersistsFreshState() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppStateStore(baseDirectoryURL: baseDirectory)
        let source = source(id: "bundle:org.mozilla.firefox", name: "Firefox")

        _ = try await store.mergeObservedSources([source], actionBySourceID: [source.id: .externalAudioDetected])
        _ = try await store.setIgnored(true, sourceID: source.id)
        _ = try await store.appendActivityRecords([
            ActivityRecord(
                action: .externalAudioDetected,
                sourceIDs: [source.id],
                sourceDisplayNames: [source.displayName],
                spotifyStateBefore: .playing,
                spotifyStateAfter: .playing,
                ignored: false,
                note: "Firefox started audio."
            )
        ], limit: MonitoringConfiguration.default.storedHistoryLimit)

        _ = try await store.clearActivityRecords()
        _ = try await store.resetIgnoredApps()

        let reloadedStore = AppStateStore(baseDirectoryURL: baseDirectory)
        let observed = await reloadedStore.observedSources()
        let history = await reloadedStore.activityRecords()

        XCTAssertEqual(history, [])
        XCTAssertEqual(observed.count, 1)
        XCTAssertFalse(observed[0].isIgnored)
    }

    private func source(id: String, name: String, ignored: Bool = false) -> ObservedAudioSource {
        ObservedAudioSource(
            id: id,
            displayName: name,
            bundleIdentifier: id.replacingOccurrences(of: "bundle:", with: ""),
            executablePath: "/Applications/\(name).app",
            lastSeenAt: Date(timeIntervalSince1970: 100),
            lastTriggeredAt: nil,
            lastTriggeredAction: nil,
            seenCount: 0,
            isIgnored: ignored
        )
    }

    private func legacyRecord(id: UUID, action: ActivityAction) throws -> ActivityRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let json = """
        {
          "id": "\(id.uuidString)",
          "timestamp": "2026-03-23T22:00:00Z",
          "action": "\(action.rawValue)",
          "sourceIDs": ["bundle:org.mozilla.firefox"],
          "sourceDisplayNames": ["Firefox"],
          "spotifyStateBefore": "paused",
          "spotifyStateAfter": "paused",
          "ignored": false,
          "note": "Legacy row."
        }
        """

        return try decoder.decode(ActivityRecord.self, from: Data(json.utf8))
    }
}

private actor StateSequenceReader {
    private let states: [SpotifyPlayerState]
    private var index = 0

    init(states: [SpotifyPlayerState]) {
        self.states = states
    }

    func next() -> SpotifyPlayerState {
        guard !states.isEmpty else {
            return .unknown
        }

        let state = states[min(index, states.count - 1)]
        index += 1
        return state
    }
}

private struct MockShellInvocation: Hashable {
    var executable: String
    var arguments: [String]
}

private actor MockShellCommandRunner: ShellCommandRunning {
    private let resultsByInvocation: [MockShellInvocation: ShellCommandResult]

    init(resultsByInvocation: [MockShellInvocation: ShellCommandResult]) {
        self.resultsByInvocation = resultsByInvocation
    }

    func run(_ executableURL: URL, arguments: [String]) async throws -> ShellCommandResult {
        let invocation = MockShellInvocation(executable: executableURL.path, arguments: arguments)
        guard let result = resultsByInvocation[invocation] else {
            throw ShellCommandError.launchFailed("Missing mock result for \(invocation.executable) \(arguments.joined(separator: " "))")
        }

        return result
    }
}
