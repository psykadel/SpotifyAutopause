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

            if let snapshot = viewModel.pollInspectionSnapshot {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(snapshot.entries) { entry in
                            commandCard(entry)
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
                Text("Exact output from the polling commands Spotify Autopause uses to inspect system audio.")
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

    private func commandCard(_ entry: CommandInspectionResult) -> some View {
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

            outputSection(title: "stdout", content: entry.result.stdout)

            if !entry.result.stderr.isEmpty {
                outputSection(title: "stderr", content: entry.result.stderr)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func outputSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(content.isEmpty ? "(empty)" : content)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
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
}
