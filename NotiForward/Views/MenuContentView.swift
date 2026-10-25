import AppKit
import SwiftUI

struct MenuContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Label(statusText, systemImage: statusIcon)
            if let error = model.deliveryError {
                Text(error).foregroundStyle(.secondary)
            } else if let date = model.lastForwardedAt {
                let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(model.language.locale))
                Text(L("Last forwarded: \(time)"))
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(model.isPaused ? L("Resume Forwarding") : L("Pause Forwarding")) {
                model.togglePaused()
            }
            .disabled(!model.general.bark.isConfigured)
            Button(L("Send Test Notification")) { model.sendTest() }
                .disabled(!model.general.bark.isConfigured)
            Button(L("Settings…")) {
                model.restoreMenuBar()
                openSettingsWindow(openWindow)
            }
            .keyboardShortcut(",")
            Divider()
            Button(L("Quit \(appName)")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .id(model.language.language)
    }

    private var statusText: String {
        switch model.captureStatus {
        case .starting: return L("Starting…")
        case .permissionRequired: return L("Notification folder access is required")
        case .failed(let message): return message
        case .running:
            if !model.general.bark.isConfigured { return L("Bark device key is not set") }
            if model.isPaused { return L("Forwarding is paused") }
            return L("Forwarding to Bark")
        }
    }

    private var statusIcon: String {
        switch model.captureStatus {
        case .starting: return "clock"
        case .permissionRequired, .failed: return "exclamationmark.triangle.fill"
        case .running:
            if !model.general.bark.isConfigured { return "exclamationmark.triangle.fill" }
            return model.isPaused ? "pause.circle.fill" : "checkmark.circle.fill"
        }
    }
}

@MainActor
func openSettingsWindow(_ openWindow: OpenWindowAction) {
    openWindow(id: "settings")
    NSApp.activate()
}
