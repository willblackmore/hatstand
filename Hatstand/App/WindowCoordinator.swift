import AppKit
import SwiftUI

/// Creates and shows Hatstand's windows. SwiftUI views hosted in AppKit
/// windows, because the app is driven from an `NSStatusItem`.
@MainActor
final class WindowCoordinator {

    private let store: InstanceStore
    private let controller: ClaudeController
    private var manageWindow: NSWindow?
    private let updates: UpdateChecker
    private var settingsWindow: NSWindow?

    init(store: InstanceStore, controller: ClaudeController, updates: UpdateChecker) {
        self.store = store
        self.controller = controller
        self.updates = updates
    }

    func showManageWindow() {
        if manageWindow == nil {
            let view = ManageInstancesView(openSettings: { [weak self] in self?.showSettingsWindow() })
                .environmentObject(store)
                .environmentObject(controller)
            let window = makeWindow(
                title: "Manage Instances",
                rootView: view,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                autosaveName: "ManageInstancesWindow"
            )
            window.setContentSize(NSSize(width: 720, height: 460))
            window.contentMinSize = NSSize(width: 620, height: 380)
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .automatic
            manageWindow = window
            window.center()
            window.setFrameUsingName("ManageInstancesWindow")
        }
        present(manageWindow)
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(store)
                .environmentObject(controller)
                .environmentObject(updates)
            let window = makeWindow(
                title: "Hatstand Settings",
                rootView: view,
                styleMask: [.titled, .closable],
                autosaveName: "SettingsWindow"
            )
            settingsWindow = window
            window.center()
            window.setFrameUsingName("SettingsWindow")
        }
        present(settingsWindow)
    }

    private func makeWindow<Content: View>(
        title: String,
        rootView: Content,
        styleMask: NSWindow.StyleMask,
        autosaveName: String
    ) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = styleMask
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosaveName)
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
