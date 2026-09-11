import Foundation
import CoreGraphics

@MainActor
final class PanelState: ObservableObject {
    static let expandedSize = CGSize(width: 320, height: 460)

    static let compactSize  = CGSize(width: 220, height: 118)

    static let drawerWidth: CGFloat = 300

    static let settingsDrawerWidth: CGFloat = 280

    var applyLayout: ((_ size: CGSize, _ leftInset: CGFloat) -> Void)?

    var onMinimizedChange: ((Bool) -> Void)?

    @Published var isMinimized: Bool {
        didSet {
            UserDefaults.standard.set(isMinimized, forKey: Self.minimizedKey)
            onMinimizedChange?(isMinimized)
        }
    }

    @Published var isCompact: Bool {
        didSet {
            UserDefaults.standard.set(isCompact, forKey: Self.compactKey)
            if isCompact {
                isDrawerOpen = false
                isSettingsDrawerOpen = false
            }
            relayout()
        }
    }

    @Published var isDrawerOpen: Bool {
        didSet {
            UserDefaults.standard.set(isDrawerOpen, forKey: Self.drawerKey)
            relayout()
        }
    }

    @Published var isSettingsDrawerOpen: Bool {
        didSet {
            UserDefaults.standard.set(isSettingsDrawerOpen, forKey: Self.settingsKey)
            relayout()
        }
    }

    private static let compactKey = "panel.compact"
    private static let drawerKey = "panel.drawer"
    private static let settingsKey = "panel.settingsDrawer"
    private static let minimizedKey = "panel.minimized"

    init() {
        isMinimized = UserDefaults.standard.bool(forKey: Self.minimizedKey)
        isCompact = UserDefaults.standard.bool(forKey: Self.compactKey)
        isDrawerOpen = UserDefaults.standard.bool(forKey: Self.drawerKey)
        isSettingsDrawerOpen = UserDefaults.standard.bool(forKey: Self.settingsKey)
    }

    var leftInset: CGFloat {
        (!isCompact && isSettingsDrawerOpen) ? Self.settingsDrawerWidth : 0
    }

    var size: CGSize {
        if isCompact { return Self.compactSize }
        var w = Self.expandedSize.width
        if isSettingsDrawerOpen { w += Self.settingsDrawerWidth }
        if isDrawerOpen { w += Self.drawerWidth }
        return CGSize(width: w, height: Self.expandedSize.height)
    }

    func toggleCompact() { isCompact.toggle() }
    func toggleDrawer() { isDrawerOpen.toggle() }
    func toggleSettingsDrawer() { isSettingsDrawerOpen.toggle() }

    func minimizeToMenuBar() { isMinimized = true }

    func restoreFromMenuBar() {
        isCompact = true
        isMinimized = false
    }

    private func relayout() { applyLayout?(size, leftInset) }
}
