import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var controller: ClaudeController

    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Hatstand at login", isOn: launchAtLoginBinding)
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow Hatstand in Login Items to finish turning this on.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
                if let loginItemError {
                    Label(loginItemError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Toggle(isOn: confirmBinding) {
                    Text("Confirm before switching")
                    Text("Ask before quitting Claude to open another instance.")
                }
            }

            Section("Claude") {
                LabeledContent("Location") {
                    HStack {
                        Text(store.settings.claudeAppPath.abbreviatingWithTilde)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(store.settings.claudeAppPath)
                        Button("Choose…") { controller.chooseClaudeApp() }
                    }
                }
                if controller.claudeAppURL == nil {
                    Label("Claude can’t be found at this location.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let identifier = controller.bundleIdentifier {
                    LabeledContent("Bundle identifier") {
                        Text(identifier)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = SMAppService.mainApp.status
            controller.refreshClaudeApp()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
            set: { enabled in
                loginItemError = nil
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    loginItemError = error.localizedDescription
                }
                loginItemStatus = SMAppService.mainApp.status
            }
        )
    }

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { store.settings.confirmBeforeSwitching },
            set: { value in store.updateSettings { $0.confirmBeforeSwitching = value } }
        )
    }
}
