import AppKit
import CoreAudio
import Foundation
import os

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

enum ProbeInspectionState: String, Codable, CaseIterable, Sendable {
    case audible
    case silent
    case permissionRequired
    case failed
    case unavailable

    var displayName: String {
        switch self {
        case .audible:
            return "Audible"
        case .silent:
            return "Silent"
        case .permissionRequired:
            return "Permission Required"
        case .failed:
            return "Probe Failed"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct ProbeInspectionResult: Identifiable, Equatable, Sendable {
    var pid: Int32
    var displayName: String
    var sourceID: String
    var state: ProbeInspectionState
    var peakLevel: Double?
    var detail: String

    var id: String {
        "pid:\(pid)"
    }

    var userFacingDisplayName: String {
        userFacingAudioSourceName(displayName)
    }
}

struct PollInspectionSnapshot: Sendable {
    var refreshedAt: Date
    var entries: [CommandInspectionResult]
    var probeDiagnostics: [ProbeInspectionResult]
    var warningMessage: String?
}

struct CandidateAudioProcess: Hashable, Sendable {
    var pid: Int32
    var source: ObservedAudioSource
}

struct AudioSourceObservation: Sendable {
    var activeSources: [ObservedAudioSource]
    var hasCandidateProcesses: Bool
    var warningMessage: String?
    var probeDiagnostics: [ProbeInspectionResult]
}

struct AudibilityProbeObservation: Sendable {
    var audiblePIDs: Set<Int32>
    var warningMessage: String?
    var diagnostics: [ProbeInspectionResult]
}

protocol ShellCommandRunning: Sendable {
    func run(_ executableURL: URL, arguments: [String]) async throws -> ShellCommandResult
}

protocol AudibilityProbing: Sendable {
    func observe(_ candidates: [CandidateAudioProcess], at now: Date) async -> AudibilityProbeObservation
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
    private let audibilityProbe: any AudibilityProbing

    init(
        runner: any ShellCommandRunning = ProcessShellCommandRunner(),
        parser: PmsetAudioAssertionParser = PmsetAudioAssertionParser(),
        audibilityProbe: any AudibilityProbing = CoreAudioProcessTapProbe()
    ) {
        self.runner = runner
        self.parser = parser
        self.resolver = ProcessResolver(runner: runner)
        self.audibilityProbe = audibilityProbe
    }

    func fetchActiveSources(at now: Date = Date()) async throws -> AudioSourceObservation {
        let result = try await runner.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["-g", "assertions"])
        guard result.status == 0 else {
            throw ShellCommandError.commandFailed(
                executable: "/usr/bin/pmset",
                status: result.status,
                stderr: result.stderr
            )
        }

        let candidates = try await resolveCandidateProcesses(from: result.stdout, at: now)
        let probeObservation = await audibilityProbe.observe(candidates, at: now)

        return AudioSourceObservation(
            activeSources: mergeAudibleSources(from: candidates, audiblePIDs: probeObservation.audiblePIDs),
            hasCandidateProcesses: !candidates.isEmpty,
            warningMessage: probeObservation.warningMessage,
            probeDiagnostics: probeObservation.diagnostics
        )
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
            return PollInspectionSnapshot(
                refreshedAt: now,
                entries: entries,
                probeDiagnostics: [],
                warningMessage: nil
            )
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

        let candidates = try await resolveCandidateProcesses(from: pmsetResult.stdout, at: now)
        let probeObservation = await audibilityProbe.observe(candidates, at: now)

        return PollInspectionSnapshot(
            refreshedAt: now,
            entries: entries,
            probeDiagnostics: probeObservation.diagnostics,
            warningMessage: probeObservation.warningMessage
        )
    }

    private func resolveCandidateProcesses(from pmsetOutput: String, at now: Date) async throws -> [CandidateAudioProcess] {
        var candidates: [CandidateAudioProcess] = []

        for pid in parser.extractAudioOutputPIDs(from: pmsetOutput) {
            if let candidate = try await resolver.resolve(pid: pid, seenAt: now) {
                candidates.append(candidate)
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.source.displayName != rhs.source.displayName {
                return lhs.source.displayName.localizedCaseInsensitiveCompare(rhs.source.displayName) == .orderedAscending
            }

            return lhs.pid < rhs.pid
        }
    }

    private func mergeAudibleSources(from candidates: [CandidateAudioProcess], audiblePIDs: Set<Int32>) -> [ObservedAudioSource] {
        var mergedSources: [String: ObservedAudioSource] = [:]

        for candidate in candidates where audiblePIDs.contains(candidate.pid) {
            mergedSources[candidate.source.id] = candidate.source
        }

        return mergedSources.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
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

    func resolve(pid: Int32, seenAt: Date) async throws -> CandidateAudioProcess? {
        if let runningApp = NSRunningApplication(processIdentifier: pid_t(pid)) {
            let bundleIdentifier = runningApp.bundleIdentifier?.lowercased()
            let executablePath = runningApp.executableURL?.path
            let displayName = Self.normalizedDisplayName(
                runningApp.localizedName
                    ?? runningApp.bundleURL?.deletingPathExtension().lastPathComponent
                    ?? executablePath
                    ?? "PID \(pid)"
            )

            return CandidateAudioProcess(
                pid: pid,
                source: ObservedAudioSource(
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

        return CandidateAudioProcess(
            pid: pid,
            source: ObservedAudioSource(
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
        )
    }

    private static func normalizedDisplayName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown Source"
        }

        return trimmed
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

@available(macOS 14.2, *)
actor CoreAudioProcessTapProbe: AudibilityProbing {
    private static let permissionWarning = "System audio capture permission is required to confirm whether external audio is audible."
    private static let degradedWarning = "Some audio sources could not be audited for audible output. Open Inspect for details."
    private static let permissionRetryInterval: TimeInterval = 10

    private var sessions: [Int32: ProcessTapSession] = [:]
    private var permissionRetryAfter: Date?

    func observe(_ candidates: [CandidateAudioProcess], at now: Date) async -> AudibilityProbeObservation {
        let candidatePIDs = Set(candidates.map(\.pid))
        let stalePIDs = Set(sessions.keys).subtracting(candidatePIDs)
        for pid in stalePIDs {
            sessions.removeValue(forKey: pid)?.invalidate()
        }

        guard !candidates.isEmpty else {
            permissionRetryAfter = nil
            return AudibilityProbeObservation(audiblePIDs: [], warningMessage: nil, diagnostics: [])
        }

        if let permissionRetryAfter, now < permissionRetryAfter {
            return Self.permissionDeniedObservation(for: candidates)
        }

        var diagnostics: [Int32: ProbeInspectionResult] = [:]
        var shouldShowDegradedWarning = false

        for candidate in candidates where sessions[candidate.pid] == nil {
            switch ProcessTapSession.make(candidate: candidate) {
            case .success(let session):
                sessions[candidate.pid] = session
                self.permissionRetryAfter = nil
            case .failure(let failure):
                diagnostics[candidate.pid] = failure.diagnostic(for: candidate)

                switch failure {
                case .permissionDenied:
                    teardownAllSessions()
                    permissionRetryAfter = now.addingTimeInterval(Self.permissionRetryInterval)
                    return Self.permissionDeniedObservation(for: candidates)
                case .unsupportedFormat, .coreAudioFailure:
                    shouldShowDegradedWarning = true
                case .staleProcess:
                    break
                }
            }
        }

        var audiblePIDs: Set<Int32> = []
        for candidate in candidates {
            if let session = sessions[candidate.pid] {
                let snapshot = session.snapshot(at: now)
                diagnostics[candidate.pid] = snapshot.diagnostic
                if snapshot.isAudible {
                    audiblePIDs.insert(candidate.pid)
                }
            } else if diagnostics[candidate.pid] == nil {
                diagnostics[candidate.pid] = ProbeInspectionResult(
                    pid: candidate.pid,
                    displayName: candidate.source.displayName,
                    sourceID: candidate.source.id,
                    state: .unavailable,
                    peakLevel: nil,
                    detail: "The candidate process disappeared before it could be probed."
                )
            }
        }

        let orderedDiagnostics = candidates.compactMap { diagnostics[$0.pid] }
        return AudibilityProbeObservation(
            audiblePIDs: audiblePIDs,
            warningMessage: shouldShowDegradedWarning ? Self.degradedWarning : nil,
            diagnostics: orderedDiagnostics
        )
    }

    private func teardownAllSessions() {
        for session in sessions.values {
            session.invalidate()
        }
        sessions.removeAll()
    }

    private static func permissionDeniedObservation(for candidates: [CandidateAudioProcess]) -> AudibilityProbeObservation {
        AudibilityProbeObservation(
            audiblePIDs: [],
            warningMessage: permissionWarning,
            diagnostics: candidates.map { candidate in
                ProbeInspectionResult(
                    pid: candidate.pid,
                    displayName: candidate.source.displayName,
                    sourceID: candidate.source.id,
                    state: .permissionRequired,
                    peakLevel: nil,
                    detail: "Grant system audio capture permission to let Spotify Autopause confirm that this source is actually audible."
                )
            }
        )
    }
}

@available(macOS 14.2, *)
private final class ProcessTapSession {
    private let candidate: CandidateAudioProcess
    private let peakAccumulator = ProcessTapRealtimePeakAccumulator()

    private var tapID: AudioObjectID
    private var aggregateDeviceID: AudioObjectID
    private var ioProcID: AudioDeviceIOProcID?
    private var audibilityState = PeakWindowAudibilityState()
    private let format: ProcessTapLinearPCMFormat

    private init(
        candidate: CandidateAudioProcess,
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID?,
        format: ProcessTapLinearPCMFormat
    ) {
        self.candidate = candidate
        self.tapID = tapID
        self.aggregateDeviceID = aggregateDeviceID
        self.ioProcID = ioProcID
        self.format = format
    }

    deinit {
        invalidate()
    }

    static func make(candidate: CandidateAudioProcess) -> Result<ProcessTapSession, ProcessTapFailure> {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let ioProcID: AudioDeviceIOProcID? = nil

        do {
            let processObjectID = try translateProcessObjectID(pid: candidate.pid)
            let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
            tapDescription.name = "Spotify Autopause PID \(candidate.pid)"
            tapDescription.isPrivate = true
            tapDescription.isExclusive = false
            tapDescription.isMixdown = true
            tapDescription.isMono = false
            tapDescription.muteBehavior = CATapMuteBehavior.unmuted

            try checkStatus(
                AudioHardwareCreateProcessTap(tapDescription, &tapID),
                permissionDetails: "Could not create a process tap for PID \(candidate.pid)."
            )

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Spotify Autopause Probe \(candidate.pid)",
                kAudioAggregateDeviceUIDKey: "io.github.psykadel.spotifyautopause.probe.\(candidate.pid).\(UUID().uuidString)",
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]],
                // Keep start nonblocking so silent candidate processes do not stall the polling loop.
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false
            ]

            try checkStatus(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
                permissionDetails: "Could not create a private aggregate device for PID \(candidate.pid)."
            )

            let format = try ProcessTapLinearPCMFormat.read(from: tapID)
            try verifyCapturePermission(on: tapID)

            let session = ProcessTapSession(
                candidate: candidate,
                tapID: tapID,
                aggregateDeviceID: aggregateDeviceID,
                ioProcID: nil,
                format: format
            )

            var createdIOProcID: AudioDeviceIOProcID?
            let createIOStatus = AudioDeviceCreateIOProcIDWithBlock(&createdIOProcID, aggregateDeviceID, nil) {
                [peakAccumulator = session.peakAccumulator, format] _, inputData, _, _, _ in
                let peak = format.peak(from: inputData)
                peakAccumulator.record(peak: peak)
            }
            try checkStatus(
                createIOStatus,
                permissionDetails: "Could not register the audio probe callback for PID \(candidate.pid)."
            )

            session.ioProcID = createdIOProcID

            try checkStatus(
                AudioDeviceStart(aggregateDeviceID, createdIOProcID),
                permissionDetails: "Could not start the audio probe for PID \(candidate.pid)."
            )

            return .success(session)
        } catch let failure as ProcessTapFailure {
            if let ioProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            if aggregateDeviceID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }
            if tapID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            return .failure(failure)
        } catch {
            if let ioProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            if aggregateDeviceID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }
            if tapID != kAudioObjectUnknown {
                _ = AudioHardwareDestroyProcessTap(tapID)
            }
            return .failure(.coreAudioFailure(detail: error.localizedDescription))
        }
    }

    func snapshot(at now: Date) -> ProcessTapSnapshot {
        let peak = peakAccumulator.drainPeak()
        let isAudible = audibilityState.record(peak: peak, at: now)
        return ProcessTapSnapshot(candidate: candidate, peak: peak, isAudible: isAudible)
    }

    func invalidate() {
        if let ioProcID {
            _ = AudioDeviceStop(aggregateDeviceID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private static func translateProcessObjectID(pid: Int32) throws -> AudioObjectID {
        var propertyAddress = propertyAddress(selector: kAudioHardwarePropertyTranslatePIDToProcessObject)
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var processID = pid_t(pid)

        let status = withUnsafePointer(to: &processID) { processIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<pid_t>.size),
                processIDPointer,
                &propertySize,
                &processObjectID
            )
        }

        try checkStatus(status, permissionDetails: "Could not resolve PID \(pid) in Core Audio.")
        guard processObjectID != kAudioObjectUnknown else {
            throw ProcessTapFailure.staleProcess(detail: "PID \(pid) is no longer attached to Core Audio.")
        }

        return processObjectID
    }

    private static func verifyCapturePermission(on tapID: AudioObjectID) throws {
        var propertyAddress = propertyAddress(selector: kAudioTapPropertyDescription)
        var propertySize = UInt32(MemoryLayout<Unmanaged<AnyObject>?>.size)
        var unmanagedDescription: Unmanaged<AnyObject>?

        let readStatus = AudioObjectGetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &unmanagedDescription
        )
        try checkStatus(readStatus, permissionDetails: "System audio capture permission has not been granted yet.")

        guard let descriptionObject = unmanagedDescription?.takeRetainedValue() as? CATapDescription else {
            throw ProcessTapFailure.permissionDenied(detail: "System audio capture permission has not been granted yet.")
        }

        var descriptionReference = Unmanaged.passUnretained(descriptionObject as AnyObject)
        let writeStatus = AudioObjectSetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            propertySize,
            &descriptionReference
        )
        try checkStatus(writeStatus, permissionDetails: "System audio capture permission has not been granted yet.")
    }

    private static func checkStatus(_ status: OSStatus, permissionDetails: String) throws {
        guard status == kAudioHardwareNoError else {
            if status == kAudioDevicePermissionsError || status == kAudioHardwareIllegalOperationError {
                throw ProcessTapFailure.permissionDenied(detail: permissionDetails)
            }

            throw ProcessTapFailure.coreAudioFailure(detail: "\(permissionDetails) \(status.description)")
        }
    }
}

private struct ProcessTapSnapshot: Sendable {
    var candidate: CandidateAudioProcess
    var peak: Double
    var isAudible: Bool

    var diagnostic: ProbeInspectionResult {
        let dbfs = peak > 0 ? 20 * log10(peak) : nil
        let peakSummary: String
        if let dbfs {
            peakSummary = String(format: "peak %.4f (%.1f dBFS)", peak, dbfs)
        } else {
            peakSummary = "peak 0.0000"
        }

        return ProbeInspectionResult(
            pid: candidate.pid,
            displayName: candidate.source.displayName,
            sourceID: candidate.source.id,
            state: isAudible ? .audible : .silent,
            peakLevel: peak,
            detail: isAudible
                ? "The probe is seeing audible samples for this PID with \(peakSummary)."
                : "The probe is attached, but recent samples are below the audibility threshold (\(peakSummary))."
        )
    }
}

private enum ProcessTapFailure: Error {
    case staleProcess(detail: String)
    case permissionDenied(detail: String)
    case unsupportedFormat(detail: String)
    case coreAudioFailure(detail: String)

    func diagnostic(for candidate: CandidateAudioProcess) -> ProbeInspectionResult {
        let state: ProbeInspectionState
        switch self {
        case .staleProcess:
            state = .unavailable
        case .permissionDenied:
            state = .permissionRequired
        case .unsupportedFormat, .coreAudioFailure:
            state = .failed
        }

        return ProbeInspectionResult(
            pid: candidate.pid,
            displayName: candidate.source.displayName,
            sourceID: candidate.source.id,
            state: state,
            peakLevel: nil,
            detail: detail
        )
    }

    var detail: String {
        switch self {
        case .staleProcess(let detail),
             .permissionDenied(let detail),
             .unsupportedFormat(let detail),
             .coreAudioFailure(let detail):
            return detail
        }
    }
}

private struct ProcessTapLinearPCMFormat: Sendable {
    private enum SampleEncoding: Sendable {
        case float32
        case float64
        case int16
        case int24
        case int32
    }

    private let encoding: SampleEncoding

    static func read(from tapID: AudioObjectID) throws -> ProcessTapLinearPCMFormat {
        var propertyAddress = propertyAddress(selector: kAudioTapPropertyFormat)
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var streamDescription = AudioStreamBasicDescription()

        let status = AudioObjectGetPropertyData(
            tapID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &streamDescription
        )

        guard status == kAudioHardwareNoError else {
            throw ProcessTapFailure.coreAudioFailure(detail: "Could not read the process tap stream format. \(status.description)")
        }

        guard streamDescription.mFormatID == kAudioFormatLinearPCM else {
            throw ProcessTapFailure.unsupportedFormat(detail: "The process tap is using an unsupported non-LPCM format.")
        }

        let formatFlags = streamDescription.mFormatFlags
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (formatFlags & kAudioFormatFlagIsSignedInteger) != 0

        let encoding: SampleEncoding
        switch (isFloat, isSignedInteger, bitsPerChannel) {
        case (true, _, 32):
            encoding = .float32
        case (true, _, 64):
            encoding = .float64
        case (_, true, 16):
            encoding = .int16
        case (_, true, 24):
            encoding = .int24
        case (_, true, 32):
            encoding = .int32
        default:
            throw ProcessTapFailure.unsupportedFormat(
                detail: "The tap format \(bitsPerChannel)-bit LPCM is not one of the supported float or signed-integer layouts."
            )
        }

        return ProcessTapLinearPCMFormat(encoding: encoding)
    }

    func peak(from audioBufferList: UnsafePointer<AudioBufferList>) -> Double {
        let bufferCount = Int(audioBufferList.pointee.mNumberBuffers)
        guard bufferCount > 0 else {
            return 0
        }

        var maxPeak = 0.0
        withUnsafePointer(to: audioBufferList.pointee.mBuffers) { firstBufferPointer in
            firstBufferPointer.withMemoryRebound(to: AudioBuffer.self, capacity: bufferCount) { buffers in
                for index in 0..<bufferCount {
                    maxPeak = max(maxPeak, peak(in: buffers[index]))
                }
            }
        }
        return min(maxPeak, 1.0)
    }

    private func peak(in buffer: AudioBuffer) -> Double {
        guard let data = buffer.mData, buffer.mDataByteSize > 0 else {
            return 0
        }

        switch encoding {
        case .float32:
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.bindMemory(to: Float.self, capacity: sampleCount)
            var peak = 0.0
            for index in 0..<sampleCount {
                peak = max(peak, abs(Double(samples[index])))
            }
            return peak
        case .float64:
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Double>.size
            let samples = data.bindMemory(to: Double.self, capacity: sampleCount)
            var peak = 0.0
            for index in 0..<sampleCount {
                peak = max(peak, abs(samples[index]))
            }
            return peak
        case .int16:
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
            let samples = data.bindMemory(to: Int16.self, capacity: sampleCount)
            var peak = 0.0
            for index in 0..<sampleCount {
                peak = max(peak, abs(Double(samples[index])) / 32768.0)
            }
            return peak
        case .int24:
            return peakForPacked24BitSamples(data: data, byteCount: Int(buffer.mDataByteSize))
        case .int32:
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int32>.size
            let samples = data.bindMemory(to: Int32.self, capacity: sampleCount)
            var peak = 0.0
            for index in 0..<sampleCount {
                peak = max(peak, abs(Double(samples[index])) / 2147483648.0)
            }
            return peak
        }
    }

    private func peakForPacked24BitSamples(data: UnsafeMutableRawPointer, byteCount: Int) -> Double {
        let bytes = data.bindMemory(to: UInt8.self, capacity: byteCount)
        guard byteCount >= 3 else {
            return 0
        }

        var peak = 0.0
        var offset = 0
        while offset + 2 < byteCount {
            var value = Int32(bytes[offset])
                | (Int32(bytes[offset + 1]) << 8)
                | (Int32(bytes[offset + 2]) << 16)

            if (value & 0x0080_0000) != 0 {
                value |= ~0x00FF_FFFF
            }

            peak = max(peak, abs(Double(value)) / 8_388_608.0)
            offset += 3
        }

        return peak
    }
}

struct PeakWindowAudibilityState: Sendable {
    static let defaultThreshold = 0.001
    static let defaultHoldDuration: TimeInterval = 0.3
    static let defaultQuietWindowsBeforeSilent = 2

    var threshold: Double = Self.defaultThreshold
    var holdDuration: TimeInterval = Self.defaultHoldDuration
    var quietWindowsBeforeSilent: Int = Self.defaultQuietWindowsBeforeSilent

    private(set) var isAudible = false
    private var lastAboveThresholdAt: Date?
    private var consecutiveQuietWindows = 0

    mutating func record(peak: Double, at now: Date) -> Bool {
        if peak >= threshold {
            lastAboveThresholdAt = now
            consecutiveQuietWindows = 0
            isAudible = true
            return true
        }

        if let lastAboveThresholdAt, now.timeIntervalSince(lastAboveThresholdAt) <= holdDuration {
            consecutiveQuietWindows = 0
            isAudible = true
            return true
        }

        if isAudible {
            consecutiveQuietWindows += 1
            if consecutiveQuietWindows < max(quietWindowsBeforeSilent, 1) {
                return true
            }
        }

        isAudible = false
        return false
    }
}

private final class ProcessTapRealtimePeakAccumulator: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var maxPeak = 0.0

    func record(peak: Double) {
        os_unfair_lock_lock(&lock)
        if peak > maxPeak {
            maxPeak = peak
        }
        os_unfair_lock_unlock(&lock)
    }

    func drainPeak() -> Double {
        os_unfair_lock_lock(&lock)
        let peak = maxPeak
        maxPeak = 0
        os_unfair_lock_unlock(&lock)
        return peak
    }
}

private func propertyAddress(selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

private extension OSStatus {
    var description: String {
        if self == 0 {
            return "0"
        }

        let bigEndianValue = CFSwapInt32HostToBig(UInt32(bitPattern: self))
        let scalarValues = [
            UnicodeScalar((bigEndianValue >> 24) & 0xFF),
            UnicodeScalar((bigEndianValue >> 16) & 0xFF),
            UnicodeScalar((bigEndianValue >> 8) & 0xFF),
            UnicodeScalar(bigEndianValue & 0xFF)
        ]

        if scalarValues.allSatisfy({ scalar in
            guard let scalar else {
                return false
            }

            return (32...126).contains(scalar.value)
        }) {
            return "'" + String(String.UnicodeScalarView(scalarValues.compactMap { $0 })) + "'"
        }

        return "\(self)"
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
