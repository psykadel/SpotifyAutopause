import Foundation

enum SpotifyPlayerState: String, Codable, CaseIterable, Sendable {
    case notRunning
    case playing
    case paused
    case stopped
    case unknown

    var isPlaying: Bool {
        self == .playing
    }

    var displayName: String {
        switch self {
        case .notRunning:
            return "Not Running"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        case .unknown:
            return "Unknown"
        }
    }
}

enum SpotifyControlCommand: String, Codable, Sendable {
    case pause
    case resume
}

enum ActivityAction: String, Codable, CaseIterable, Sendable {
    case externalAudioDetected
    case externalAudioChanged
    case externalAudioEnded
    case ignoredAudioDetected
    case spotifyPaused
    case spotifyResumed
    case ignoreRuleUpdated
    case monitorError

    var title: String {
        switch self {
        case .externalAudioDetected:
            return "External Audio Started"
        case .externalAudioChanged:
            return "External Audio Changed"
        case .externalAudioEnded:
            return "External Audio Ended"
        case .ignoredAudioDetected:
            return "Ignored Audio Seen"
        case .spotifyPaused:
            return "Spotify Paused"
        case .spotifyResumed:
            return "Spotify Resumed"
        case .ignoreRuleUpdated:
            return "Ignore Rule Updated"
        case .monitorError:
            return "Monitoring Error"
        }
    }
}

enum ActivityAccentStyle: Sendable {
    case neutral
    case attention
    case success
    case subdued
}

struct ObservedAudioSource: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var displayName: String
    var bundleIdentifier: String?
    var executablePath: String?
    var lastSeenAt: Date
    var lastTriggeredAt: Date?
    var lastTriggeredAction: ActivityAction?
    var seenCount: Int
    var isIgnored: Bool

    var isAlwaysIgnored: Bool {
        bundleIdentifier?.lowercased() == SpotifyController.spotifyBundleIdentifier
            || id == "bundle:\(SpotifyController.spotifyBundleIdentifier)"
    }

    var isEffectivelyIgnored: Bool {
        isIgnored || isAlwaysIgnored
    }

    var detailLine: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        if let executablePath, !executablePath.isEmpty {
            return executablePath
        }

        return id
    }
}

struct IgnoredAppEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var displayName: String
    var bundleIdentifier: String?
    var executablePath: String?
    var updatedAt: Date
}

struct ActivityRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var timestamp: Date
    var action: ActivityAction
    var sourceIDs: [String]
    var sourceDisplayNames: [String]
    var visibleSourceIDs: [String]?
    var visibleSourceDisplayNames: [String]?
    var spotifyStateBefore: SpotifyPlayerState
    var spotifyStateAfter: SpotifyPlayerState
    var ignored: Bool
    var note: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: ActivityAction,
        sourceIDs: [String],
        sourceDisplayNames: [String],
        visibleSourceIDs: [String]? = nil,
        visibleSourceDisplayNames: [String]? = nil,
        spotifyStateBefore: SpotifyPlayerState,
        spotifyStateAfter: SpotifyPlayerState,
        ignored: Bool,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.sourceIDs = sourceIDs
        self.sourceDisplayNames = sourceDisplayNames
        self.visibleSourceIDs = visibleSourceIDs
        self.visibleSourceDisplayNames = visibleSourceDisplayNames
        self.spotifyStateBefore = spotifyStateBefore
        self.spotifyStateAfter = spotifyStateAfter
        self.ignored = ignored
        self.note = note
    }

    var sourceSummary: String {
        guard !sourceDisplayNames.isEmpty else {
            return "No source details"
        }

        return sourceDisplayNames.joined(separator: ", ")
    }

    var visibleSourceSummary: String {
        if hasExplicitVisibleSources {
            return visibleSourceDisplayNames?.joined(separator: ", ") ?? sourceSummary
        }

        switch action {
        case .externalAudioEnded, .spotifyResumed:
            return ""
        default:
            return sourceSummary
        }
    }

    var spotifyTransitionSummary: String {
        guard normalizedSpotifyStateAfter != spotifyStateBefore else {
            return ""
        }

        return "\(spotifyStateBefore.displayName) -> \(normalizedSpotifyStateAfter.displayName)"
    }

    var accentStyle: ActivityAccentStyle {
        switch action {
        case .externalAudioDetected, .externalAudioChanged, .spotifyPaused:
            return .attention
        case .spotifyResumed:
            return .success
        case .ignoredAudioDetected, .ignoreRuleUpdated:
            return .subdued
        case .externalAudioEnded, .monitorError:
            return .neutral
        }
    }

    private var normalizedSpotifyStateAfter: SpotifyPlayerState {
        guard spotifyStateAfter == spotifyStateBefore else {
            return spotifyStateAfter
        }

        switch action {
        case .spotifyPaused:
            return .paused
        case .spotifyResumed:
            return .playing
        default:
            return spotifyStateAfter
        }
    }

    private var hasExplicitVisibleSources: Bool {
        visibleSourceIDs != nil || visibleSourceDisplayNames != nil
    }
}

struct MonitoringSnapshot: Equatable, Sendable {
    var spotifyState: SpotifyPlayerState
    var externalAudioActive: Bool
    var candidateAudioActive: Bool
    var activeSources: [ObservedAudioSource]
    var actionableSources: [ObservedAudioSource]
    var ignoredSources: [ObservedAudioSource]
    var lastAction: ActivityRecord?
    var lastUpdatedAt: Date?
    var lastErrorMessage: String?

    var userVisibleActiveSources: [ObservedAudioSource] {
        activeSources.filter { !$0.isAlwaysIgnored }
    }

    var userVisibleIgnoredSources: [ObservedAudioSource] {
        ignoredSources.filter { !$0.isAlwaysIgnored }
    }

    var currentAudioSummary: String {
        if !actionableSources.isEmpty {
            return actionableSources.map(\.displayName).joined(separator: ", ")
        }

        if !userVisibleIgnoredSources.isEmpty {
            return "Only ignored audio is active"
        }

        return "No external audio detected"
    }

    var currentAudioDetailSummary: String {
        let activeCount = userVisibleActiveSources.count
        if activeCount == 0 {
            return "Spotify Autopause checks the system audio path every few seconds."
        }

        return activeCount == 1
            ? "1 source is visible in the audio path."
            : "\(activeCount) sources are visible in the audio path."
    }

    static let empty = MonitoringSnapshot(
        spotifyState: .notRunning,
        externalAudioActive: false,
        candidateAudioActive: false,
        activeSources: [],
        actionableSources: [],
        ignoredSources: [],
        lastAction: nil,
        lastUpdatedAt: nil,
        lastErrorMessage: nil
    )
}

struct PersistedAppState: Codable, Sendable {
    var activityRecords: [ActivityRecord]
    var observedSources: [ObservedAudioSource]
    var ignoredEntries: [IgnoredAppEntry]
    var monitoringConfiguration: MonitoringConfiguration?

    static let empty = PersistedAppState(
        activityRecords: [],
        observedSources: [],
        ignoredEntries: [],
        monitoringConfiguration: nil
    )
}
