import SwiftUI

enum SpotifyAutopauseWindowID {
    static let recentActivity = "recent-activity"
    static let ignoredApps = "ignored-apps"
    static let inspect = "inspect"
    static let configure = "configure"
}

@main
struct SpotifyAutopauseApp: App {
    @StateObject private var viewModel: SpotifyAutopauseViewModel

    init() {
        let viewModel = SpotifyAutopauseViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        viewModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(viewModel)
        } label: {
            MenuBarIconView()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .accessibilityLabel("Spotify Autopause")
        }
        .menuBarExtraStyle(.window)

        Window("Recent Activity", id: SpotifyAutopauseWindowID.recentActivity) {
            ActivityHistoryWindowView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 780, height: 500)
        .windowResizability(.contentSize)

        Window("Ignored Apps", id: SpotifyAutopauseWindowID.ignoredApps) {
            IgnoredAppsWindowView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 980, height: 560)
        .windowResizability(.contentSize)

        Window("Inspect", id: SpotifyAutopauseWindowID.inspect) {
            PollInspectionWindowView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentSize)

        Window("Configure", id: SpotifyAutopauseWindowID.configure) {
            ConfigurationWindowView()
                .environmentObject(viewModel)
        }
        .defaultSize(width: 560, height: 420)
        .windowResizability(.contentSize)
    }
}
