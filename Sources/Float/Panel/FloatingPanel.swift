import AppKit
import SwiftUI

final class FloatingPanel<Content: View>: NSPanel {
    private static var originKey: String { "panel.origin" }

    init(contentRect: NSRect, content: () -> Content) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let hosting = NSHostingView(rootView: content())
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var savedTopLeft: NSPoint? {
        guard let arr = UserDefaults.standard.array(forKey: Self.originKey) as? [Double],
              arr.count == 2 else { return nil }
        return NSPoint(x: arr[0], y: arr[1])
    }

    func persistTopLeft() {
        let tl = [Double(frame.minX), Double(frame.maxY)]
        UserDefaults.standard.set(tl, forKey: Self.originKey)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        persistTopLeft()
    }
}
