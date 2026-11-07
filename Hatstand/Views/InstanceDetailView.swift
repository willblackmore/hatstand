import SwiftUI
import AppKit

struct InstanceDetailView: View {
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var controller: ClaudeController

    let instance: Instance

    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draftName)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                if let nameError {
                    Label(nameError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } footer: {
                if instance.isDefault {
                    Text("The default instance uses Claude’s normal data locations. It’s the one that opens when you open Claude from the Dock, Spotlight or at login.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Folders") {
                FolderRow(title: "App data", path: instance.appDataPath)
                FolderRow(title: "Claude Code", path: instance.claudeCodePath)
            }

            Section {
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(actionTitle) {
                        commitName()
                        controller.open(instance)
                    }
                    .disabled(controller.isBusy || controller.claudeAppURL == nil)
                }
            } footer: {
                if controller.claudeAppURL == nil {
                    Label("Claude can’t be found. Choose its location in Settings.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftName = instance.name }
        .onChange(of: nameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: instance.name) { _, newName in
            if !nameFocused { draftName = newName }
        }
        .onDisappear(perform: commitName)
    }

    // MARK: Name

    private var nameError: String? {
        guard draftName != instance.name else { return nil }
        return store.validator.validateName(draftName, existing: store.allInstances, excluding: instance.id)?.message
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != instance.name, nameError == nil else { return }
        try? store.rename(instance.id, to: trimmed)
        draftName = trimmed
    }

    // MARK: Status

    private var isRunning: Bool { controller.runningInstanceID == instance.id }

    private var statusText: String {
        if controller.switchingTo == instance.id { return "Opening…" }
        if isRunning { return "Running" }
        if case .running = controller.runState { return "Not running (another instance is open)" }
        return "Not running"
    }

    private var actionTitle: String {
        if isRunning { return "Show Claude" }
        if case .running = controller.runState { return "Switch to This Instance" }
        return "Open"
    }
}

private struct FolderRow: View {
    let title: String
    let path: String

    private var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var body: some View {
        LabeledContent {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .disabled(!exists)
            .help(exists ? "Show this folder in Finder" : "This folder will be created the first time the instance opens.")
        } label: {
            Text(title)
            Text(path.abbreviatingWithTilde)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(path)
        }
    }
}
