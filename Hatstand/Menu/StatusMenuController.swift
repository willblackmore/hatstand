import AppKit
import Combine

/// The menu bar item and its menu.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let store: InstanceStore
    private let controller: ClaudeController
    private let windows: WindowCoordinator
    private let updates: UpdateChecker
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(store: InstanceStore, controller: ClaudeController, windows: WindowCoordinator, updates: UpdateChecker) {
        self.store = store
        self.controller = controller
        self.windows = windows
        self.updates = updates
        super.init()

        statusItem.autosaveName = "HatstandStatusItem"
        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.accessibilityDescription = "Hatstand"
            button.image = image
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        Publishers.CombineLatest3(controller.$runState, controller.$switchingTo, store.$config)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateTitle() }
            .store(in: &cancellables)
        Publishers.CombineLatest(controller.$claudeAppURL, controller.$bundleIdentifier)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    // MARK: Title

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let title: String
        if controller.isBusy {
            title = "Switching…"
        } else {
            switch controller.runState {
            case .notRunning:
                title = store.defaultInstance.name
            case .running(.known(let id)):
                title = store.instance(withID: id)?.name ?? "Unknown instance"
            case .running(.unknown):
                title = "Unknown instance"
            }
        }
        button.title = " " + title
        button.toolTip = controller.claudeAppURL == nil
            ? "Hatstand – Claude can’t be found"
            : "Hatstand – \(title)"
        button.appearsDisabled = controller.isBusy
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.refreshRunState()
        menu.removeAllItems()

        menu.addItem(.sectionHeader(title: "Your Instances"))

        let busy = controller.isBusy
        let canLaunch = controller.claudeAppURL != nil
        for instance in store.allInstances {
            let item = NSMenuItem(title: instance.name, action: #selector(openInstance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = instance.id
            item.isEnabled = !busy && canLaunch
            if controller.switchingTo == instance.id {
                item.state = .mixed
            } else if controller.runningInstanceID == instance.id {
                item.state = .on
            }
            if instance.isDefault {
                if #available(macOS 14.4, *) {
                    item.subtitle = "Default instance"
                }
            }
            menu.addItem(item)
        }

        if case .running(.unknown(let path)) = controller.runState {
            let item = NSMenuItem(title: "Unknown instance", action: nil, keyEquivalent: "")
            item.state = .on
            item.isEnabled = false
            if #available(macOS 14.4, *), !path.isEmpty {
                item.subtitle = path.abbreviatingWithTilde
            }
            menu.addItem(item)
        }

        if !canLaunch {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: "Claude can’t be found", action: nil, keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            warning.isEnabled = false
            menu.addItem(warning)
            let locate = NSMenuItem(title: "Locate Claude…", action: #selector(locateClaude), keyEquivalent: "")
            locate.target = self
            menu.addItem(locate)
        }

        menu.addItem(.separator())

        if let update = updates.availableUpdate {
            let version = update.version?.description ?? update.tagName
            let item = NSMenuItem(title: "Update Available: Hatstand \(version)…",
                                  action: #selector(showUpdate), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let manage = NSMenuItem(title: "Manage Instances…", action: #selector(manageInstances), keyEquivalent: "")
        manage.target = self
        manage.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)
        menu.addItem(manage)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        check.isEnabled = !updates.isChecking
        menu.addItem(check)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Hatstand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func openInstance(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let instance = store.instance(withID: id) else { return }
        controller.open(instance)
    }

    @objc private func manageInstances() {
        windows.showManageWindow()
    }

    @objc private func openSettings() {
        windows.showSettingsWindow()
    }

    @objc private func showUpdate() {
        guard let update = updates.availableUpdate else { return }
        updates.presentUpdate(update)
    }

    @objc private func checkForUpdates() {
        updates.checkAndReport()
    }

    @objc private func locateClaude() {
        controller.chooseClaudeApp()
    }
}
