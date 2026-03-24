import Foundation

enum MonitoringEvent: Equatable, Sendable {
    case actionableSourcesStarted
    case actionableSourcesChanged
    case actionableSourcesEnded
    case ignoredSourcesObserved
}

struct MonitoringOutcome: Equatable, Sendable {
    var command: SpotifyControlCommand?
    var actionableSources: [ObservedAudioSource]
    var ignoredSources: [ObservedAudioSource]
    var events: [MonitoringEvent]
}

struct MonitoringEngine: Sendable {
    private(set) var actionableAudioActive = false
    private(set) var shouldResumeSpotify = false

    private var lastActionableSourceIDs = Set<String>()
    private var lastIgnoredSourceIDs = Set<String>()

    mutating func evaluate(
        spotifyState: SpotifyPlayerState,
        activeSources: [ObservedAudioSource],
        ignoredSourceIDs: Set<String>
    ) -> MonitoringOutcome {
        let actionableSources = activeSources.filter { !ignoredSourceIDs.contains($0.id) && !$0.isAlwaysIgnored }
        let ignoredSources = activeSources.filter { ignoredSourceIDs.contains($0.id) || $0.isAlwaysIgnored }

        let actionableSourceIDs = Set(actionableSources.map(\.id))
        let ignoredIDs = Set(ignoredSources.map(\.id))

        var events: [MonitoringEvent] = []
        var command: SpotifyControlCommand?

        if !actionableSources.isEmpty {
            if !actionableAudioActive {
                actionableAudioActive = true
                events.append(.actionableSourcesStarted)

                if spotifyState.isPlaying {
                    shouldResumeSpotify = true
                    command = .pause
                } else {
                    shouldResumeSpotify = false
                }
            } else if actionableSourceIDs != lastActionableSourceIDs {
                events.append(.actionableSourcesChanged)
            }
        } else if actionableAudioActive {
            actionableAudioActive = false
            events.append(.actionableSourcesEnded)

            if shouldResumeSpotify {
                command = .resume
            }

            shouldResumeSpotify = false
        } else if !ignoredSources.isEmpty, ignoredIDs != lastIgnoredSourceIDs {
            events.append(.ignoredSourcesObserved)
        }

        lastActionableSourceIDs = actionableSourceIDs
        lastIgnoredSourceIDs = ignoredIDs

        return MonitoringOutcome(
            command: command,
            actionableSources: actionableSources,
            ignoredSources: ignoredSources,
            events: events
        )
    }

    mutating func commandFailed(_ command: SpotifyControlCommand) {
        switch command {
        case .pause:
            shouldResumeSpotify = false
        case .resume:
            shouldResumeSpotify = false
        }
    }
}
