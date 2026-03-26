import Foundation

struct MonitoringConfiguration: Codable, Equatable, Sendable {
    static let defaultActivePollIntervalSeconds = 2
    static let defaultIdlePollIntervalSeconds = 3
    static let defaultResumeWatchPollIntervalMilliseconds = 1_000
    static let defaultVisibleHistoryLimit = 25
    static let defaultStoredHistoryLimit = 250

    var activePollIntervalSeconds: Int
    var idlePollIntervalSeconds: Int
    var resumeWatchPollIntervalMilliseconds: Int
    var visibleHistoryLimit: Int
    var storedHistoryLimit: Int

    init(
        activePollIntervalSeconds: Int = Self.defaultActivePollIntervalSeconds,
        idlePollIntervalSeconds: Int = Self.defaultIdlePollIntervalSeconds,
        resumeWatchPollIntervalMilliseconds: Int = Self.defaultResumeWatchPollIntervalMilliseconds,
        visibleHistoryLimit: Int = Self.defaultVisibleHistoryLimit,
        storedHistoryLimit: Int = Self.defaultStoredHistoryLimit
    ) {
        self.activePollIntervalSeconds = max(activePollIntervalSeconds, 1)
        self.idlePollIntervalSeconds = max(idlePollIntervalSeconds, 1)
        self.resumeWatchPollIntervalMilliseconds = max(resumeWatchPollIntervalMilliseconds, 250)
        self.visibleHistoryLimit = max(visibleHistoryLimit, 1)
        self.storedHistoryLimit = max(storedHistoryLimit, visibleHistoryLimit)
    }

    static let `default` = MonitoringConfiguration()
}
