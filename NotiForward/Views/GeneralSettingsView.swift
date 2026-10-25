import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                accessRow
                LabeledContent(L("Last forwarded")) {
                    Text(model.lastForwardedAt.map { $0.formatted(.dateTime.locale(model.language.locale)) } ?? "—")
                }
            } header: {
                Text(L("Status"))
            } footer: {
                if model.captureStatus == .permissionRequired {
                    Text(L("\(appName) reads only the Notification Center folder, which you grant once. Forwarding starts within a few seconds."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("App")) {
                Toggle(L("Launch at login"), isOn: $model.general.launchAtLogin)
                    .onChange(of: model.general.launchAtLogin) { _, _ in model.saveSettings() }
                Toggle(L("Show menu bar icon"), isOn: Binding(
                    get: { model.isMenuBarVisible },
                    set: { visible in visible ? model.restoreMenuBar() : model.hideMenuBar() }
                ))
                Text(L("If hidden, open \(appName) again to restore the menu bar icon."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Updates")) {
                LabeledContent(L("Version"), value: model.appVersion)
#if !APP_STORE
                @Bindable var updater = model.updater
                Toggle(L("Automatically check for updates"), isOn: $updater.automaticallyChecks)
                HStack {
                    Spacer()
                    Button(L("Check for Updates…")) { model.updater.checkForUpdates() }
                }
#endif
            }
            Section(L("Language")) {
                Picker(L("App language"), selection: $model.general.language) {
                    ForEach(AppLanguage.allCases) { language in Text(name(of: language)).tag(language) }
                }
                .onChange(of: model.general.language) { _, _ in model.saveSettings() }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var accessRow: some View {
        LabeledContent(L("Notification access")) {
            switch model.captureStatus {
            case .permissionRequired:
                Button(L("Grant Access…")) { model.requestNotificationAccess() }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            case .running where model.isPaused:
                Text(L("Paused"))
            case .running:
                Label(L("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .starting:
                ProgressView().controlSize(.small)
            }
        }
    }

    /// Languages are listed by their own names so they stay recognizable in any UI language.
    private func name(of language: AppLanguage) -> String {
        switch language {
        case .system: L("System Default")
        case .english: "English"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portugueseBrazil: "Português (Brasil)"
        }
    }
}
