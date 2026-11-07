import SwiftUI
import AppKit

struct ManageInstancesView: View {
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var controller: ClaudeController

    var openSettings: () -> Void

    @State private var selection: UUID? = Instance.defaultID
    @State private var showingAddSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if let id = selection, let instance = store.instance(withID: id) {
                InstanceDetailView(instance: instance)
                    .id(id)
            } else {
                ContentUnavailableView("No Instance Selected", systemImage: "square.stack.3d.up",
                                       description: Text("Select an instance to see its details."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Hatstand Settings")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddInstanceView { instance, usedExistingFolders in
                selection = instance.id
                // Let the sheet finish closing before showing the alert.
                DispatchQueue.main.async {
                    offerToOpen(instance, usedExistingFolders: usedExistingFolders)
                }
            }
            .environmentObject(store)
        }
        .onChange(of: store.config.instances) { _, _ in
            if let id = selection, store.instance(withID: id) == nil {
                selection = Instance.defaultID
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.allInstances) { instance in
                InstanceRow(
                    instance: instance,
                    isRunning: controller.runningInstanceID == instance.id,
                    isSwitchingTo: controller.switchingTo == instance.id
                )
                .tag(instance.id)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addRemoveBar
        }
    }

    private var addRemoveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .help("Add an instance")
                .accessibilityLabel("Add Instance")

                Button {
                    removeSelected()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .help(removeHelp)
                .accessibilityLabel("Remove Instance")
                .disabled(!canRemoveSelection)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var selectedInstance: Instance? {
        selection.flatMap { store.instance(withID: $0) }
    }

    private var canRemoveSelection: Bool {
        guard let instance = selectedInstance else { return false }
        return !instance.isDefault
            && controller.runningInstanceID != instance.id
            && controller.switchingTo != instance.id
    }

    private var removeHelp: String {
        guard let instance = selectedInstance else { return "Remove the selected instance" }
        if instance.isDefault { return "The default instance can’t be removed" }
        if controller.runningInstanceID == instance.id { return "Quit Claude before removing the running instance" }
        return "Remove “\(instance.name)”"
    }

    // MARK: Actions

    private func removeSelected() {
        guard canRemoveSelection, let instance = selectedInstance else { return }

        let alert = NSAlert()
        alert.messageText = "Remove “\(instance.name)”?"
        alert.informativeText = "Hatstand will forget this instance. Its folders stay where they are unless you also move them to the Bin."
        let remove = alert.addButton(withTitle: "Remove")
        remove.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Also move its folders to the Bin"
        alert.suppressionButton?.state = .off

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let moveToBin = alert.suppressionButton?.state == .on

        store.remove(instance.id)
        selection = Instance.defaultID

        if moveToBin {
            do {
                try FolderTrash.moveFoldersToBin(for: instance)
            } catch {
                let failure = NSAlert()
                failure.alertStyle = .warning
                failure.messageText = "Some folders couldn’t be moved to the Bin"
                failure.informativeText = error.localizedDescription
                failure.runModal()
            }
        }
    }

    private func offerToOpen(_ instance: Instance, usedExistingFolders: Bool) {
        let alert = NSAlert()
        alert.messageText = "Open “\(instance.name)” now?"
        var text = usedExistingFolders
            ? "Claude will open using the folders you chose."
            : "The first time an instance opens, Claude shows its sign-in screen. Sign in with the account you want to use for “\(instance.name)”."
        if case .running = controller.runState {
            text += " Claude will quit and reopen."
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Open Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            controller.open(instance, skipConfirmation: true)
        }
    }
}

private struct InstanceRow: View {
    let instance: Instance
    let isRunning: Bool
    let isSwitchingTo: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(instance.name)
                    .lineLimit(1)
                if instance.isDefault {
                    Text("Default instance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if isSwitchingTo {
                ProgressView()
                    .controlSize(.small)
            } else if isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .help("Running")
                    .accessibilityLabel("Running")
            }
        }
        .padding(.vertical, 2)
    }
}

/// Moves an instance's folders to the Bin. Never deletes anything outright.
enum FolderTrash {

    static func moveFoldersToBin(for instance: Instance) throws {
        let fileManager = FileManager.default
        let appData = URL(fileURLWithPath: instance.appDataPath)
        let claudeCode = URL(fileURLWithPath: instance.claudeCodePath)

        // For folders Hatstand created (<Name>/app-data and <Name>/claude-code),
        // move the enclosing <Name> folder if it holds nothing else.
        let parent = appData.deletingLastPathComponent()
        if appData.lastPathComponent == "app-data",
           claudeCode.lastPathComponent == "claude-code",
           claudeCode.deletingLastPathComponent().path == parent.path,
           let contents = try? fileManager.contentsOfDirectory(atPath: parent.path),
           Set(contents).isSubset(of: ["app-data", "claude-code", ".DS_Store"]) {
            try fileManager.trashItem(at: parent, resultingItemURL: nil)
            return
        }

        var firstError: Error?
        for url in [appData, claudeCode] where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}
