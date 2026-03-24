import SwiftUI

struct ActivityHistoryWindowView: View {
    @EnvironmentObject private var viewModel: SpotifyAutopauseViewModel
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.visibleActivityRecords.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Spotify Autopause will add rows here as it sees audio sources, pauses Spotify, resumes Spotify, or records ignored activity.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.visibleActivityRecords) {
                    TableColumn("Time") { record in
                        Text(Self.timestampFormatter.string(from: record.timestamp))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .width(min: 126, ideal: 132)

                    TableColumn("Action") { record in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: record.accentStyle))
                                .frame(width: 8, height: 8)
                            Text(record.action.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                    .width(min: 170, ideal: 182)

                    TableColumn("Sources") { record in
                        Text(record.visibleSourceSummary)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .width(min: 180, ideal: 210)

                    TableColumn("Spotify") { record in
                        Text(record.spotifyTransitionSummary)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .width(min: 118, ideal: 132)

                    TableColumn("State") { record in
                        Text(record.ignored ? "Ignored" : "")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(record.ignored ? .secondary : .primary)
                    }
                    .width(min: 82, ideal: 92)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 480)
        .confirmationDialog(
            "Clear recent activity?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Activity", role: .destructive) {
                viewModel.clearRecentActivity()
            }
        } message: {
            Text("This removes the saved recent activity history and starts the log fresh.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Activity")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Live history of audio-source changes, Spotify pause and resume decisions, and ignored-source observations. Showing the newest \(viewModel.visibleActivityRecords.count) rows.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Clear") {
                showingClearConfirmation = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func color(for accentStyle: ActivityAccentStyle) -> Color {
        switch accentStyle {
        case .attention:
            return .orange
        case .success:
            return .green
        case .subdued:
            return .gray
        case .neutral:
            return .blue
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
