import AppKit
import Foundation

struct ShellCommandResult: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

struct CommandInspectionResult: Identifiable, Sendable {
    let id: UUID
    var commandLine: String
    var result: ShellCommandResult

    init(
        id: UUID = UUID(),
        commandLine: String,
        result: ShellCommandResult
    ) {
        self.id = id
        self.commandLine = commandLine
        self.result = result
    }
}

struct PollInspectionSnapshot: Sendable {
    var refreshedAt: Date
    var entries: [CommandInspectionResult]
}

protocol ShellCommandRunning: Sendable {
    func run(_ executableURL: URL, arguments: [String]) async throws -> ShellCommandResult
}

enum ShellCommandError: LocalizedError {
    case launchFailed(String)
    case commandFailed(executable: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .commandFailed(let executable, let status, let stderr):
            let suffix = stderr.isEmpty ? "" : " (\(stderr))"
            return "\(executable) exited with status \(status)\(suffix)"
        }
    }
}

struct ProcessShellCommandRunner: ShellCommandRunning {
    func run(_ executableURL: URL, arguments: [String]) async throws -> ShellCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(
                    returning: ShellCommandResult(
                        status: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellCommandError.launchFailed(error.localizedDescription))
            }
        }
    }
}

struct AudioSourceMonitor: Sendable {
    private let runner: any ShellCommandRunning
    private let parser: PmsetAudioAssertionParser
    private let resolver: ProcessResolver

    init(
        runner: any ShellCommandRunning = ProcessShellCommandRunner(),
        parser: PmsetAudioAssertionParser = PmsetAudioAssertionParser()
    ) {
        self.runner = runner
        self.parser = parser
        self.resolver = ProcessResolver(runner: runner)
    }

    func fetchActiveSources(at now: Date = Date()) async throws -> [ObservedAudioSource] {
        let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["-g", "assertions"])
        guard result.status == 0 else {
            throw ShellCommandError.commandFailed(
                executable: "/usr/bin/pmset",
                status: result.status,
                stderr: result.stderr
            )
        }

        let pids = parser.extractAudioOutputPIDs(from: result.stdout)
        var mergedSources: [String: ObservedAudioSource] = [:]

        for pid in pids {
            if let source = try await resolver.resolve(pid: pid, seenAt: now) {
                mergedSources[source.id] = source
            }
        }

        return mergedSources.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func inspectPollingCommands(at now: Date = Date()) async throws -> PollInspectionSnapshot {
        let pmsetExecutable = URL(fileURLWithPath: "/usr/bin/pmset")
        let pmsetArguments = ["-g", "assertions"]
        let pmsetResult = try await runner.run(pmsetExecutable, arguments: pmsetArguments)

        var entries = [
            CommandInspectionResult(
                commandLine: Self.commandLine(executableURL: pmsetExecutable, arguments: pmsetArguments),
                result: pmsetResult
            )
        ]

        guard pmsetResult.status == 0 else {
            return PollInspectionSnapshot(refreshedAt: now, entries: entries)
        }

        let pids = parser.extractAudioOutputPIDs(from: pmsetResult.stdout)
        for pid in pids {
            let psExecutable = URL(fileURLWithPath: "/bin/ps")
            let psArguments = ["-p", "\(pid)", "-o", "command="]
            let psResult = try await runner.run(psExecutable, arguments: psArguments)
            entries.append(
                CommandInspectionResult(
                    commandLine: Self.commandLine(executableURL: psExecutable, arguments: psArguments),
                    result: psResult
                )
            )
        }

        return PollInspectionSnapshot(refreshedAt: now, entries: entries)
    }

    private static func commandLine(executableURL: URL, arguments: [String]) -> String {
        ([executableURL.path] + arguments).joined(separator: " ")
    }
}

struct ProcessResolver: Sendable {
    private let runner: any ShellCommandRunning

    init(runner: any ShellCommandRunning) {
        self.runner = runner
    }

    func resolve(pid: Int32, seenAt: Date) async throws -> ObservedAudioSource? {
        if let runningApp = NSRunningApplication(processIdentifier: pid_t(pid)) {
            let bundleIdentifier = runningApp.bundleIdentifier?.lowercased()
            let executablePath = runningApp.executableURL?.path
            let displayName = Self.normalizedDisplayName(
                runningApp.localizedName
                    ?? runningApp.bundleURL?.deletingPathExtension().lastPathComponent
                    ?? executablePath
                    ?? "PID \(pid)"
            )

            return ObservedAudioSource(
                id: Self.stableID(bundleIdentifier: bundleIdentifier, executablePath: executablePath, fallbackName: displayName),
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                executablePath: executablePath,
                lastSeenAt: seenAt,
                lastTriggeredAt: nil,
                lastTriggeredAction: nil,
                seenCount: 0,
                isIgnored: false
            )
        }

        let command = try await runner.run(URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", "\(pid)", "-o", "command="])
        guard command.status == 0 else {
            throw ShellCommandError.commandFailed(executable: "/bin/ps", status: command.status, stderr: command.stderr)
        }

        let rawCommand = command.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawCommand.isEmpty else {
            return nil
        }

        let executablePath = rawCommand.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? rawCommand
        let displayName = Self.normalizedDisplayName(URL(fileURLWithPath: executablePath).deletingPathExtension().lastPathComponent)

        return ObservedAudioSource(
            id: Self.stableID(bundleIdentifier: nil, executablePath: executablePath, fallbackName: displayName),
            displayName: displayName,
            bundleIdentifier: nil,
            executablePath: executablePath,
            lastSeenAt: seenAt,
            lastTriggeredAt: nil,
            lastTriggeredAction: nil,
            seenCount: 0,
            isIgnored: false
        )
    }

    private static func normalizedDisplayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Source" : trimmed
    }

    private static func stableID(bundleIdentifier: String?, executablePath: String?, fallbackName: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier.lowercased())"
        }

        if let executablePath, !executablePath.isEmpty {
            return "exec:\(executablePath.lowercased())"
        }

        return "name:\(fallbackName.lowercased())"
    }
}

protocol SpotifyControlling: Sendable {
    func currentState() async throws -> SpotifyPlayerState
    func perform(_ command: SpotifyControlCommand) async throws
}

struct SpotifyController: SpotifyControlling, Sendable {
    static let spotifyBundleIdentifier = "com.spotify.client"

    private let runner: any ShellCommandRunning

    init(runner: any ShellCommandRunning = ProcessShellCommandRunner()) {
        self.runner = runner
    }

    func currentState() async throws -> SpotifyPlayerState {
        guard isRunning else {
            return .notRunning
        }

        let result = try await runner.run(
            URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", #"tell application "Spotify" to player state as string"#]
        )

        guard result.status == 0 else {
            throw ShellCommandError.commandFailed(
                executable: "/usr/bin/osascript",
                status: result.status,
                stderr: result.stderr
            )
        }

        switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unknown
        }
    }

    func perform(_ command: SpotifyControlCommand) async throws {
        guard isRunning else {
            return
        }

        let appleScript: String
        switch command {
        case .pause:
            appleScript = #"tell application "Spotify" to pause"#
        case .resume:
            appleScript = #"tell application "Spotify" to play"#
        }

        let result = try await runner.run(
            URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", appleScript]
        )

        guard result.status == 0 else {
            throw ShellCommandError.commandFailed(
                executable: "/usr/bin/osascript",
                status: result.status,
                stderr: result.stderr
            )
        }
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleIdentifier).isEmpty
    }
}
