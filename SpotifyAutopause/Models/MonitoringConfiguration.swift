import Foundation

struct MonitoringConfiguration: Codable, Equatable, Sendable {
    static let defaultStartupDelaySeconds = 2
    static let defaultActivePollIntervalSeconds = 2
    static let defaultIdlePollIntervalSeconds = 3
    static let defaultResumeWatchPollIntervalMilliseconds = 750
    static let defaultVisibleHistoryLimit = 25
    static let defaultStoredHistoryLimit = 250

    var startupDelaySeconds: Int
    var activePollIntervalSeconds: Int
    var idlePollIntervalSeconds: Int
    var resumeWatchPollIntervalMilliseconds: Int
    var visibleHistoryLimit: Int
    var storedHistoryLimit: Int

    init(
        startupDelaySeconds: Int = Self.defaultStartupDelaySeconds,
        activePollIntervalSeconds: Int = Self.defaultActivePollIntervalSeconds,
        idlePollIntervalSeconds: Int = Self.defaultIdlePollIntervalSeconds,
        resumeWatchPollIntervalMilliseconds: Int = Self.defaultResumeWatchPollIntervalMilliseconds,
        visibleHistoryLimit: Int = Self.defaultVisibleHistoryLimit,
        storedHistoryLimit: Int = Self.defaultStoredHistoryLimit
    ) {
        self.startupDelaySeconds = max(startupDelaySeconds, 0)
        self.activePollIntervalSeconds = max(activePollIntervalSeconds, 1)
        self.idlePollIntervalSeconds = max(idlePollIntervalSeconds, 1)
        self.resumeWatchPollIntervalMilliseconds = max(resumeWatchPollIntervalMilliseconds, 250)
        self.visibleHistoryLimit = max(visibleHistoryLimit, 1)
        self.storedHistoryLimit = max(storedHistoryLimit, visibleHistoryLimit)
    }

    static let `default` = MonitoringConfiguration()
}
