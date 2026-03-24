import SwiftUI

struct IgnoredAppsWindowView: View {
    @EnvironmentObject private var viewModel: SpotifyAutopauseViewModel
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.manageableSources.isEmpty {
                ContentUnavailableView(
                    "No sources collected yet",
                    systemImage: "music.note.list",
                    description: Text("Apps show up here after macOS reports them in the audio path. Once they appear, you can ignore them with a checkbox.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    candidateColumn
                    savedColumn
                }
            }
        }
        .padding(20)
        .frame(minWidth: 940, minHeight: 540)
        .confirmationDialog(
            "Reset ignored apps?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Ignored Apps", role: .destructive) {
                viewModel.resetIgnoredApps()
            }
        } message: {
            Text("This removes every saved ignored app but keeps the detected source history.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ignored Apps")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Manage which detected apps should be ignored.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Reset") {
                showingResetConfirmation = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var candidateColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: "Detected Sources",
                subtitle: "Most recently seen apps that can still be ignored."
            )

            if viewModel.candidateIgnoredSources.isEmpty {
                EmptyPaneLabel(text: "Everything detected is already saved as ignored.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.candidateIgnoredSources) { source in
                            CandidateSourceRow(source: source) {
                                viewModel.setIgnored(true, for: source.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var savedColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: "Saved Ignore List",
                subtitle: "Persisted across sessions."
            )

            if viewModel.savedIgnoredSources.isEmpty {
                EmptyPaneLabel(text: "No ignored apps saved yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.savedIgnoredSources) { source in
                            SavedIgnoredRow(source: source) {
                                viewModel.setIgnored(false, for: source.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 280, alignment: .topLeading)
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CandidateSourceRow: View {
    let source: ObservedAudioSource
    let onIgnore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(source.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }

                Text(source.detailLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    detailItem(title: "Last Seen", value: Self.relativeFormatter.localizedString(for: source.lastSeenAt, relativeTo: Date()))
                    detailItem(title: "Seen Count", value: "\(source.seenCount)")

                    if let lastTriggeredAt = source.lastTriggeredAt {
                        detailItem(title: "Last Trigger", value: Self.timeFormatter.string(from: lastTriggeredAt))
                    }
                }
            }

            Spacer(minLength: 0)

            Button("Ignore") {
                onIgnore()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func detailItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct SavedIgnoredRow: View {
    let source: ObservedAudioSource
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(source.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Button("Remove") {
                onRemove()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

private struct EmptyPaneLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
    }
}
