import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel<AnyView>?

    private var statusItem: NSStatusItem?

    private var popover: NSPopover?

    private var outsideClickMonitor: Any?

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

        services.panel.onMinimizedChange = { [weak self] minimized in
            self?.setMinimized(minimized)
        }
        if services.panel.isMinimized {
            setMinimized(true)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }

        services.spotify.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppServices.shared.panel.isMinimized {
            AppServices.shared.panel.restoreFromMenuBar()
        } else {
            panel?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func setMinimized(_ minimized: Bool) {
        if minimized {
            panel?.orderOut(nil)
            showStatusItem()
        } else {
            hideStatusItem()
            panel?.makeKeyAndOrderFront(nil)
        }
    }

    private func showStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: "StatusBarIcon")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = false
            image?.accessibilityDescription = "Float"
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
    }

    private func hideStatusItem() {
        guard let item = statusItem else { return }
        closePopover(restoring: false)
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    @objc private func statusItemClicked() {
        if let popover, popover.isShown {
            closePopover(restoring: true)
        } else if let button = statusItem?.button {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        let services = AppServices.shared
        let view = MenuBarPreviewView()
            .environmentObject(services)
            .environmentObject(services.settings)
            .environmentObject(services.engine)
            .environmentObject(services.spotify)
            .environmentObject(services.panel)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover(restoring: false) }
        }
    }

    private func closePopover(restoring: Bool) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        popover?.performClose(nil)
        popover = nil
        if restoring {
            AppServices.shared.panel.restoreFromMenuBar()
        }
    }
}
