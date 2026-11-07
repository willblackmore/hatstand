import AppKit
import Combine
import os

/// Finds Claude.app, works out which instance is running, and launches,
/// quits and switches between instances.
@MainActor
final class ClaudeController: ObservableObject {

    enum RunState: Equatable {
        case notRunning
        case running(DetectedInstance)
    }

    /// Used only to spot Claude while its Info.plist can't be read.
    static let expectedBundleIdentifier = "com.anthropic.claudefordesktop"
    static let quitTimeout: TimeInterval = 20
    static let forceQuitTimeout: TimeInterval = 5

    @Published private(set) var claudeAppURL: URL?
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var runState: RunState = .notRunning
    /// The instance being switched to, while a switch or launch is in progress.
    @Published private(set) var switchingTo: UUID?

    var isBusy: Bool { switchingTo != nil }

    let store: InstanceStore
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Set once `NSWorkspace` has been seen not to pass `CLAUDE_CONFIG_DIR` through.
    private var useOpenCommand = false
    private let logger = Logger(subsystem: "Hatstand", category: "ClaudeController")

    init(store: InstanceStore) {
        self.store = store
        refreshClaudeApp()
        refreshRunState()
        observeWorkspace()

        // Re-match the running instance when instances are added, renamed or removed,
        // and re-find Claude when its location changes.
        store.$config
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                guard let self else { return }
                if config.settings.claudeAppPath != self.claudeAppURL?.path {
                    self.refreshClaudeApp()
                }
                self.refreshRunState()
            }
            .store(in: &cancellables)
    }

    // MARK: Finding Claude

    func refreshClaudeApp() {
        let path = PathStandardiser.standardise(store.settings.claudeAppPath)
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier
        else {
            claudeAppURL = nil
            bundleIdentifier = nil
            return
        }
        claudeAppURL = url
        bundleIdentifier = identifier
    }

    /// Lets the user pick Claude.app with an open panel.
    func chooseClaudeApp() {
        let panel = NSOpenPanel()
        panel.title = "Locate Claude"
        panel.message = "Choose the Claude app."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.updateSettings { $0.claudeAppPath = url.path }
        refreshClaudeApp()
        refreshRunState()
    }

    // MARK: Detecting the running instance

    /// Claude's main process, if it's running.
    var runningApplication: NSRunningApplication? {
        let identifier = bundleIdentifier ?? Self.expectedBundleIdentifier
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { !$0.isTerminated }
        if let appURL = claudeAppURL,
           let match = candidates.first(where: {
               $0.bundleURL.map { PathComparison.isSame($0.standardizedFileURL.path, appURL.path) } ?? false
           }) {
            return match
        }
        return candidates.first
    }

    var runningInstanceID: UUID? {
        if case .running(.known(let id)) = runState { return id }
        return nil
    }

    func refreshRunState() {
        guard let app = runningApplication else {
            runState = .notRunning
            return
        }
        switch ProcessInspector.userDataDir(pid: app.processIdentifier) {
        case .success(let userDataDir):
            runState = .running(InstanceMatcher.match(
                userDataDir: userDataDir,
                instances: store.allInstances,
                locations: store.locations
            ))
        case .failure:
            runState = .running(.unknown(path: ""))
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let identifier = app?.bundleIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if identifier == (self.bundleIdentifier ?? Self.expectedBundleIdentifier) {
                        self.refreshRunState()
                    }
                }
            }
            workspaceObservers.append(observer)
        }
    }

    // MARK: Opening an instance

    /// What happens when the user picks an instance in the menu or the Manage window.
    func open(_ instance: Instance, skipConfirmation: Bool = false) {
        guard !isBusy else { return }
        guard claudeAppURL != nil else {
            showClaudeNotFound()
            return
        }
        refreshRunState()

        switch runState {
        case .running(.known(let id)) where id == instance.id:
            bringToFront()
        case .notRunning:
            Task { await perform(instance, quitFirst: false) }
        case .running:
            if store.settings.confirmBeforeSwitching && !skipConfirmation {
                guard confirmSwitch(to: instance) else { return }
            }
            Task { await perform(instance, quitFirst: true) }
        }
    }

    private func perform(_ instance: Instance, quitFirst: Bool) async {
        switchingTo = instance.id
        defer {
            switchingTo = nil
            refreshRunState()
        }

        if quitFirst {
            guard await quitClaudeAndWait() else { return }
        }
        do {
            try await launch(instance)
        } catch {
            logger.error("Launch failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Couldn’t open “\(instance.name)”", error: error)
        }
    }

    func bringToFront() {
        guard let app = runningApplication else { return }
        // Opening the running app sends it a reopen event, so Claude shows a
        // window even if all of them were closed. Arguments are ignored because
        // it's already running.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let url = app.bundleURL ?? claudeAppURL {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if error != nil {
                    Task { @MainActor in app.activate() }
                }
            }
        } else {
            app.activate()
        }
    }

    // MARK: Launching

    private func launch(_ instance: Instance) async throws {
        guard let appURL = claudeAppURL else { throw LaunchError.claudeNotFound }

        if instance.isDefault {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // Not setting `environment` means CLAUDE_CONFIG_DIR isn't passed on:
            // apps opened through Launch Services don't inherit Hatstand's environment.
            let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            if let environment = ProcessInspector.launchInfo(pid: app.processIdentifier)?.environment,
               environment["CLAUDE_CONFIG_DIR"] != nil {
                logger.warning("CLAUDE_CONFIG_DIR is set in the login session’s environment, so the default instance inherited it.")
            }
            return
        }

        try createFolders(for: instance)

        if useOpenCommand {
            try await launchWithOpenCommand(instance, appURL: appURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = ["\(ProcessArgumentParser.userDataDirFlag)=\(instance.appDataPath)"]
        configuration.environment = ["CLAUDE_CONFIG_DIR": instance.claudeCodePath]
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)

        // Check the environment variable actually arrived. If it can't be read
        // at all, trust it; if it's readable but wrong, relaunch with `open`.
        guard let environment = ProcessInspector.launchInfo(pid: app.processIdentifier)?.environment,
              environment["CLAUDE_CONFIG_DIR"] != instance.claudeCodePath
        else { return }

        logger.warning("CLAUDE_CONFIG_DIR didn’t reach Claude; relaunching with /usr/bin/open.")
        useOpenCommand = true
        app.terminate()
        guard await waitForExit(mainPID: app.processIdentifier, timeout: Self.quitTimeout) else {
            throw LaunchError.environmentNotPassed
        }
        try await launchWithOpenCommand(instance, appURL: appURL)
    }

    private func launchWithOpenCommand(_ instance: Instance, appURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-a", appURL.path,
            "--env", "CLAUDE_CONFIG_DIR=\(instance.claudeCodePath)",
            "--args", "\(ProcessArgumentParser.userDataDirFlag)=\(instance.appDataPath)",
        ]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw LaunchError.openCommandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func createFolders(for instance: Instance) throws {
        for path in [instance.appDataPath, instance.claudeCodePath] {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    // MARK: Quitting

    /// Asks Claude to quit and waits for it and all of its helpers to exit.
    /// Offers Force Quit on timeout. Returns `false` if the user cancelled or
    /// Claude couldn't be stopped.
    private func quitClaudeAndWait() async -> Bool {
        let mainPID = runningApplication?.processIdentifier
        runningApplication?.terminate()

        if await waitForExit(mainPID: mainPID, timeout: Self.quitTimeout) {
            return true
        }

        guard confirmForceQuit() else { return false }

        runningApplication?.forceTerminate()
        if let bundlePath = claudeBundlePath {
            for pid in await pidsInsideClaude(bundlePath) {
                kill(pid, SIGKILL)
            }
        }
        if await waitForExit(mainPID: mainPID, timeout: Self.forceQuitTimeout) {
            return true
        }
        showMessage(
            title: "Claude is still running",
            text: "Hatstand couldn’t stop all of Claude’s processes. Try quitting Claude yourself, then switch again."
        )
        return false
    }

    /// Waits until the main process and every process inside Claude.app have gone.
    private func waitForExit(mainPID: pid_t?, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let bundlePath = claudeBundlePath
        while Date() < deadline {
            let mainGone = mainPID.map { !ProcessInspector.isAlive($0) } ?? true
            if mainGone {
                let remaining = bundlePath == nil ? [] : await pidsInsideClaude(bundlePath!)
                if remaining.isEmpty { return true }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private var claudeBundlePath: String? {
        claudeAppURL.map { PathStandardiser.standardise($0.path) }
    }

    private func pidsInsideClaude(_ bundlePath: String) async -> [pid_t] {
        await Task.detached(priority: .userInitiated) {
            ProcessInspector.pids(insideBundle: bundlePath)
        }.value
    }

    // MARK: Alerts

    private func confirmSwitch(to instance: Instance) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Switch to \(instance.name)?"
        alert.informativeText = "Claude will quit and reopen."
        alert.addButton(withTitle: "Switch")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        NSApp.activate()
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed, alert.suppressionButton?.state == .on {
            store.updateSettings { $0.confirmBeforeSwitching = false }
        }
        return confirmed
    }

    private func confirmForceQuit() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Claude hasn’t quit"
        alert.informativeText = "Claude is taking a long time to quit. Force quitting may lose unsaved work in Claude."
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showClaudeNotFound() {
        let alert = NSAlert()
        alert.messageText = "Claude can’t be found"
        alert.informativeText = "Hatstand looked for Claude at \(store.settings.claudeAppPath.abbreviatingWithTilde)."
        alert.addButton(withTitle: "Locate Claude…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            chooseClaudeApp()
        }
    }

    private func showError(title: String, error: Error) {
        showMessage(title: title, text: error.localizedDescription)
    }

    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }

    enum LaunchError: LocalizedError {
        case claudeNotFound
        case environmentNotPassed
        case openCommandFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:
                return "Claude can’t be found. Choose its location in Settings."
            case .environmentNotPassed:
                return "Claude didn’t receive its Claude Code folder setting and didn’t quit so it could be reopened."
            case .openCommandFailed(let message):
                return message.isEmpty ? "macOS couldn’t open Claude." : message
            }
        }
    }
}
