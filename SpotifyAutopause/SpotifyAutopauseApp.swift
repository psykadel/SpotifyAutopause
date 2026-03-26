import AppKit
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
                .centerWindowOnAttach(id: SpotifyAutopauseWindowID.recentActivity)
        }
        .defaultSize(width: 775, height: 532)
        .windowResizability(.contentSize)

        Window("Ignored Apps", id: SpotifyAutopauseWindowID.ignoredApps) {
            IgnoredAppsWindowView()
                .environmentObject(viewModel)
                .centerWindowOnAttach(id: SpotifyAutopauseWindowID.ignoredApps)
        }
        .defaultSize(width: 760, height: 572)
        .windowResizability(.contentSize)

        Window("Inspect", id: SpotifyAutopauseWindowID.inspect) {
            PollInspectionWindowView()
                .environmentObject(viewModel)
                .centerWindowOnAttach(id: SpotifyAutopauseWindowID.inspect)
        }
        .defaultSize(width: 820, height: 592)
        .windowResizability(.contentSize)

        Window("Configure", id: SpotifyAutopauseWindowID.configure) {
            ConfigurationWindowView()
                .environmentObject(viewModel)
                .centerWindowOnAttach(id: SpotifyAutopauseWindowID.configure)
        }
        .defaultSize(width: 560, height: 529)
        .windowResizability(.contentSize)
    }
}

private struct WindowAttachmentView: NSViewRepresentable {
    let windowID: String

    func makeNSView(context: Context) -> AttachmentNSView {
        let view = AttachmentNSView()
        view.onAttachToWindow = { window in
            guard let window else {
                return
            }

            window.identifier = NSUserInterfaceItemIdentifier(windowID)
            DispatchQueue.main.async {
                window.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: AttachmentNSView, context: Context) {
        nsView.onAttachToWindow = { window in
            guard let window else {
                return
            }

            window.identifier = NSUserInterfaceItemIdentifier(windowID)
            DispatchQueue.main.async {
                window.center()
            }
        }
    }
}

private final class AttachmentNSView: NSView {
    var onAttachToWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onAttachToWindow?(window)
    }
}

private extension View {
    func centerWindowOnAttach(id: String) -> some View {
        background(WindowAttachmentView(windowID: id))
    }
}
