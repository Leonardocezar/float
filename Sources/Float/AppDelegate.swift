import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel<AnyView>?

    private var lastLeftInset: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let services = AppServices.shared

        let root = AnyView(
            PanelView()
                .environmentObject(services)
                .environmentObject(services.settings)
                .environmentObject(services.engine)
                .environmentObject(services.spotify)
                .environmentObject(services.panel)
                .modelContainer(services.container)
        )

        let size = services.panel.size
        let panel = FloatingPanel<AnyView>(
            contentRect: NSRect(origin: .zero, size: size),
            content: { root }
        )
        self.panel = panel

        services.panel.applyLayout = { [weak self, weak panel] newSize, leftInset in
            guard let self, let panel else { return }
            var frame = panel.frame
            let mainLeft = frame.minX + self.lastLeftInset
            let top = frame.maxY
            frame.size = newSize
            frame.origin = NSPoint(x: mainLeft - leftInset, y: top - newSize.height)
            panel.setFrame(frame, display: true, animate: true)
            self.lastLeftInset = leftInset
        }
        lastLeftInset = services.panel.leftInset

        var frame = NSRect(origin: .zero, size: size)
        if let tl = panel.savedTopLeft {
            frame.origin = NSPoint(x: tl.x, y: tl.y - size.height)
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            frame.origin = NSPoint(x: v.maxX - size.width - 16, y: v.maxY - size.height - 16)
        }
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)

        services.spotify.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.makeKeyAndOrderFront(nil)
        return true
    }
}
