import AppKit
import SwiftUI

private enum MenuBarIconImageProvider {
    static let menuBarImage: NSImage = {
        if let resourceURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: resourceURL) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let fallback = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Spotify Autopause")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }()
}

struct MenuBarIconView: View {
    var body: some View {
        Image(nsImage: MenuBarIconImageProvider.menuBarImage)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}
