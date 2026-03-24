import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var viewModel: SpotifyAutopauseViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            summaryCard

            if let errorMessage = viewModel.snapshot.lastErrorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            actionButtons
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MenuBarIconView()
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Spotify Autopause")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Pauses Spotify when other audio takes over.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                statusPill(
                    title: "Spotify \(viewModel.snapshot.spotifyState.displayName)",
                    systemImage: "music.note",
                    tint: spotifyTint
                )
                statusPill(
                    title: viewModel.snapshot.externalAudioActive ? "Pausing" : "Idle",
                    systemImage: viewModel.snapshot.externalAudioActive ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: viewModel.snapshot.externalAudioActive ? .orange : .secondary
                )
            }

            infoBlock(
                title: "Current Audio",
                value: viewModel.currentSourceSummary
            )

            if !viewModel.snapshot.userVisibleIgnoredSources.isEmpty {
                infoBlock(
                    title: "Ignored Right Now",
                    value: viewModel.snapshot.userVisibleIgnoredSources.map(\.displayName).joined(separator: ", "),
                    secondary: "Ignored sources stay visible here but do not pause Spotify."
                )
            }

            infoBlock(
                title: "Last Action",
                value: viewModel.snapshot.lastAction?.action.title ?? "Waiting for activity"
            )

            infoBlock(
                title: "Updated",
                value: formattedTimestamp(viewModel.snapshot.lastUpdatedAt)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Recent Activity") {
                    openWindow(id: SpotifyAutopauseWindowID.recentActivity)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)

                Button("Ignored Apps") {
                    openWindow(id: SpotifyAutopauseWindowID.ignoredApps)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
            }

            Button("Inspect") {
                openWindow(id: SpotifyAutopauseWindowID.inspect)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.bordered)

            Button("Quit Spotify Autopause") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func statusPill(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func infoBlock(title: String, value: String, secondary: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            if let secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var spotifyTint: Color {
        switch viewModel.snapshot.spotifyState {
        case .playing:
            return .green
        case .paused, .stopped:
            return .secondary
        case .notRunning:
            return .red
        case .unknown:
            return .orange
        }
    }

    private func formattedTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "Not yet"
        }

        return Self.timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
