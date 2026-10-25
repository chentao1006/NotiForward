import SwiftUI

struct ClientSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.title)
                        .foregroundStyle(.tint)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("\(appName) uses Bark, a free open-source iPhone app, to receive notifications. Install Bark on your iPhone first. Forwarded notifications pass through the Bark server set below."))
                            .fixedSize(horizontal: false, vertical: true)
                        Link(L("Visit the Bark website"), destination: URL(string: "https://bark.day.app")!)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                TextField(L("Device token or key"), text: Binding(
                    get: { model.general.bark.input },
                    set: { model.setBarkInput($0) }
                ), prompt: Text(L("Paste the device token, key or URL from the Bark app")))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                if !model.general.bark.deviceToken.isEmpty {
                    if model.isRegistering {
                        Text(L("Registering device token…")).font(.caption).foregroundStyle(.secondary)
                    } else if model.general.bark.isConfigured {
                        Text(L("Registered as key \(model.general.bark.deviceKey)"))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                HStack {
                    Button(L("Send Test Notification")) { model.sendTest() }
                        .disabled(!model.general.bark.isConfigured || model.testStatus == .sending)
                    testStatusView
                }
                if let error = model.deliveryError {
                    LabeledContent(L("Delivery error")) { Text(error).foregroundStyle(.red) }
                }
            } header: {
                Text(L("Device token or key"))
            } footer: {
                Text(L("Paste the device token from Bark, or the key from its server list. A full URL such as https://api.day.app/yourkey/ also works."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Advanced")) {
                LabeledContent(L("Server")) {
                    HStack {
                        TextField(L("Server"), text: $model.general.bark.serverURL, prompt: Text(BarkConfiguration.defaultServer))
                            .labelsHidden()
                            .onChange(of: model.general.bark.serverURL) { _, _ in model.barkServerChanged() }
                        if model.general.bark.serverURL != BarkConfiguration.defaultServer {
                            Button(L("Reset")) { model.resetBarkServer() }
                        }
                    }
                }
                Picker(L("Interruption level"), selection: $model.general.bark.level) {
                    Text(L("Active")).tag(BarkLevel.active)
                    Text(L("Time Sensitive")).tag(BarkLevel.timeSensitive)
                    Text(L("Passive")).tag(BarkLevel.passive)
                }
                .onChange(of: model.general.bark.level) { _, _ in model.saveSettings() }
                Toggle(L("Group notifications by app"), isOn: $model.general.bark.groupByApp)
                    .onChange(of: model.general.bark.groupByApp) { _, _ in model.saveSettings() }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Show app icons"), isOn: $model.general.bark.showsAppIcon)
                        .onChange(of: model.general.bark.showsAppIcon) { _, _ in model.saveSettings() }
                    Text(L("Looks up icons on the App Store by bundle ID. Apps not on the App Store show Bark’s icon."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L("Open the matching iPhone app on tap"), isOn: $model.general.bark.opensAppOnTap)
                        .onChange(of: model.general.bark.opensAppOnTap) { _, _ in model.saveSettings() }
                    Text(L("Uses the Mac app’s URL scheme, such as tg:// for Telegram. Apps without the same scheme on iPhone just open Bark."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var testStatusView: some View {
        switch model.testStatus {
        case .idle: EmptyView()
        case .sending: ProgressView().controlSize(.small)
        case .succeeded: Label(L("Sent"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
