import SwiftUI

struct PollInspectionWindowView: View {
    @EnvironmentObject private var viewModel: SpotifyAutopauseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let errorMessage = viewModel.pollInspectionErrorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let warningMessage = viewModel.pollInspectionSnapshot?.warningMessage, !warningMessage.isEmpty {
                Text(warningMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let snapshot = viewModel.pollInspectionSnapshot {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let pmsetEntry = snapshot.entries.first {
                            inspectionSection(
                                title: "Find processes using CoreAudioD",
                                description: "Spotify Autopause runs `pmset -g assertions` to find processes currently using the system audio path."
                            ) {
                                commandCard(pmsetEntry, outputHeight: 180)
                            }
                        }

                        if snapshot.entries.count > 1 {
                            inspectionSection(
                                title: "Retrieve process names",
                                description: "For each PID from `pmset`, Spotify Autopause runs `ps` so you can see the matching process command and path."
                            ) {
                                ForEach(Array(snapshot.entries.dropFirst())) { entry in
                                    commandCard(entry, outputHeight: 96)
                                }
                            }
                        }

                        if !snapshot.probeDiagnostics.isEmpty {
                            inspectionSection(
                                title: "Check whether the audio is actually audible",
                                description: "Each candidate process gets a short probe. Silent tabs or idle sessions do not count as active audio."
                            ) {
                                ForEach(snapshot.probeDiagnostics) { diagnostic in
                                    probeCard(diagnostic)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if viewModel.isRefreshingPollInspection {
                ProgressView("Running polling commands...")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ContentUnavailableView(
                    "No inspection data yet",
                    systemImage: "terminal",
                    description: Text("Run Refresh to inspect the exact command output used for polling audio state.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 560)
        .task {
            if viewModel.pollInspectionSnapshot == nil && !viewModel.isRefreshingPollInspection {
                viewModel.refreshPollInspection()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Inspect")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Spotify Autopause finds candidate audio processes with `pmset`, looks up their names with `ps`, and then samples them to confirm the audio is actually audible.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let refreshedAt = viewModel.pollInspectionSnapshot?.refreshedAt {
                    Text("Last refreshed: \(Self.timestampFormatter.string(from: refreshedAt))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button(viewModel.isRefreshingPollInspection ? "Refreshing..." : "Refresh") {
                viewModel.refreshPollInspection()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRefreshingPollInspection)
        }
    }

    private func inspectionSection<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(description)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
    }

    private func commandCard(_ entry: CommandInspectionResult, outputHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(entry.commandLine)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Text("exit \(entry.result.status)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill((entry.result.status == 0 ? Color.green : Color.red).opacity(0.12))
                    )
                    .foregroundStyle(entry.result.status == 0 ? .green : .red)
            }

            outputSection(title: "stdout", content: entry.result.stdout, maxHeight: outputHeight)

            if !entry.result.stderr.isEmpty {
                outputSection(title: "stderr", content: entry.result.stderr, maxHeight: 72)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func probeCard(_ diagnostic: ProbeInspectionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(diagnostic.userFacingDisplayName) (PID \(diagnostic.pid))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(diagnostic.sourceID)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Text(diagnostic.state.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(probeTint(for: diagnostic.state).opacity(0.12))
                    )
                    .foregroundStyle(probeTint(for: diagnostic.state))
            }

            Text(diagnostic.detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if let peakLevel = diagnostic.peakLevel {
                Text(String(format: "Peak %.4f", peakLevel))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func outputSection(title: String, content: String, maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(content.isEmpty ? "(empty)" : content)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: maxHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private func probeTint(for state: ProbeInspectionState) -> Color {
        switch state {
        case .audible:
            return .orange
        case .silent:
            return .secondary
        case .permissionRequired:
            return .red
        case .failed:
            return .yellow
        case .unavailable:
            return .secondary
        }
    }
}
