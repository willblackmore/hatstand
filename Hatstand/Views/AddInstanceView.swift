import SwiftUI
import AppKit

struct AddInstanceView: View {
    @EnvironmentObject private var store: InstanceStore
    @Environment(\.dismiss) private var dismiss

    /// Called after the instance is added, with whether existing folders were used.
    var onAdd: (Instance, Bool) -> Void

    enum Mode: Hashable { case createNew, useExisting }

    @State private var name = ""
    @State private var mode: Mode = .createNew
    @State private var parentFolder = ""
    @State private var existingAppData = ""
    @State private var existingClaudeCode = ""
    @State private var addError: String?

    static let appDataFolderName = "app-data"
    static let claudeCodeFolderName = "claude-code"

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("For example, Personal"))
                    issueLabels(for: .name)
                }

                Section {
                    Picker("Folders", selection: $mode) {
                        Text("Create new folders").tag(Mode.createNew)
                        Text("Use existing folders").tag(Mode.useExisting)
                    }
                    .pickerStyle(.radioGroup)

                    if mode == .createNew {
                        createNewFields
                    } else {
                        useExistingFields
                    }
                }

                if let addError {
                    Section {
                        Label(addError, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(allIssues.hasErrors)
            }
            .padding()
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if parentFolder.isEmpty {
                parentFolder = store.locations.suggestedInstancesParent
            }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private var createNewFields: some View {
        LabeledContent("Location") {
            HStack {
                Text(parentFolder.abbreviatingWithTilde)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(parentFolder)
                Button("Choose…") {
                    if let path = chooseFolder(title: "Choose a Location", message: "New folders for the instance will be created inside this folder.", startingAt: parentFolder) {
                        parentFolder = path
                    }
                }
            }
        }
        if let base = newInstanceFolder {
            Text("Creates “\(Self.appDataFolderName)” and “\(Self.claudeCodeFolderName)” folders inside \(base.abbreviatingWithTilde).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        issueLabels(for: .location)
        issueLabels(for: .appData)
        issueLabels(for: .claudeCode)
    }

    @ViewBuilder
    private var useExistingFields: some View {
        LabeledContent("App data folder") {
            folderPicker(path: $existingAppData, placeholder: "None", optional: false,
                         title: "Choose the App Data Folder",
                         message: "Choose the folder Claude uses for this instance’s sign-in, chats and settings.")
        }
        issueLabels(for: .appData)

        LabeledContent("Claude Code folder") {
            folderPicker(path: $existingClaudeCode, placeholder: "Optional", optional: true,
                         title: "Choose the Claude Code Folder",
                         message: "Choose the folder Claude Code uses for this instance.")
        }
        if existingClaudeCode.isEmpty, let appData = resolvedPaths?.claudeCode, !existingAppData.isEmpty {
            Text("If left empty, a “\(Self.claudeCodeFolderName)” folder is used next to the app data folder: \(appData.abbreviatingWithTilde)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        issueLabels(for: .claudeCode)
    }

    private func folderPicker(path: Binding<String>, placeholder: String, optional: Bool,
                              title: String, message: String) -> some View {
        HStack {
            Text(path.wrappedValue.isEmpty ? placeholder : path.wrappedValue.abbreviatingWithTilde)
                .foregroundStyle(path.wrappedValue.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path.wrappedValue)
            if optional && !path.wrappedValue.isEmpty {
                Button {
                    path.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
            Button("Choose…") {
                if let chosen = chooseFolder(title: title, message: message, startingAt: path.wrappedValue) {
                    path.wrappedValue = chosen
                }
            }
        }
    }

    @ViewBuilder
    private func issueLabels(for field: ValidationIssue.Field) -> some View {
        ForEach(visibleIssues.issues(for: field), id: \.self) { issue in
            Label(issue.message, systemImage: issue.severity == .error
                  ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Paths

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var newInstanceFolder: String? {
        guard !trimmedName.isEmpty, !parentFolder.isEmpty else { return nil }
        return PathStandardiser.standardise(parentFolder) + "/" + trimmedName
    }

    private var resolvedPaths: (appData: String, claudeCode: String)? {
        switch mode {
        case .createNew:
            guard let base = newInstanceFolder else { return nil }
            return (PathStandardiser.standardise(base + "/" + Self.appDataFolderName),
                    PathStandardiser.standardise(base + "/" + Self.claudeCodeFolderName))
        case .useExisting:
            guard !existingAppData.isEmpty else { return nil }
            let appData = PathStandardiser.standardise(existingAppData)
            let claudeCode = existingClaudeCode.isEmpty
                ? PathStandardiser.standardise((appData as NSString).deletingLastPathComponent + "/" + Self.claudeCodeFolderName)
                : PathStandardiser.standardise(existingClaudeCode)
            return (appData, claudeCode)
        }
    }

    // MARK: Validation

    private var allIssues: [ValidationIssue] {
        let validator = store.validator
        var issues: [ValidationIssue] = []

        if let issue = validator.validateName(name, existing: store.allInstances) {
            issues.append(issue)
        }
        if mode == .createNew, let issue = validator.folderNameIssue(name) {
            issues.append(issue)
        }

        guard let paths = resolvedPaths else {
            issues.append(.error(mode == .createNew ? .location : .appData, "Choose a folder."))
            return issues
        }

        issues += validator.validatePaths(appData: paths.appData, claudeCode: paths.claudeCode,
                                          existing: store.config.instances)

        if mode == .createNew, let base = newInstanceFolder,
           let contents = try? FileManager.default.contentsOfDirectory(atPath: base),
           !contents.filter({ $0 != ".DS_Store" }).isEmpty {
            issues.append(.error(.location, "A folder called “\(trimmedName)” already exists here and isn’t empty. Choose another name or location, or use existing folders."))
        }
        return issues
    }

    /// Issues worth showing: skip “empty field” prompts until the user has typed or chosen something.
    private var visibleIssues: [ValidationIssue] {
        allIssues.filter { issue in
            switch issue.field {
            case .name: return !trimmedName.isEmpty
            case .appData where mode == .useExisting: return !existingAppData.isEmpty
            case .location: return !trimmedName.isEmpty
            default: return resolvedPaths != nil
            }
        }
    }

    // MARK: Actions

    private func add() {
        guard let paths = resolvedPaths, !allIssues.hasErrors else { return }
        do {
            let instance = try store.add(name: trimmedName, appDataPath: paths.appData, claudeCodePath: paths.claudeCode)
            dismiss()
            onAdd(instance, mode == .useExisting)
        } catch {
            addError = error.localizedDescription
        }
    }

    private func chooseFolder(title: String, message: String, startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if !path.isEmpty {
            var directory = PathStandardiser.standardise(path)
            while !FileManager.default.fileExists(atPath: directory), directory != "/" {
                directory = (directory as NSString).deletingLastPathComponent
            }
            panel.directoryURL = URL(fileURLWithPath: directory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return PathStandardiser.standardise(url.path)
    }
}
