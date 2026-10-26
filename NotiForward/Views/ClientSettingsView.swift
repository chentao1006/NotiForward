import SwiftUI

struct ClientSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedDeviceID: UUID?

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
                VStack(spacing: 0) {
                    List(model.general.barkDevices, selection: $selectedDeviceID) { device in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(L("Device token or key"), text: Binding(
                                    get: { deviceValue(device.id)?.input ?? "" },
                                    set: { model.setBarkInput($0, deviceID: device.id) }
                                ), prompt: Text(L("Paste the device token, key or URL from the Bark app")))
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))

                                if let current = deviceValue(device.id), !current.deviceToken.isEmpty {
                                    if model.isRegistering(deviceID: device.id) {
                                        Text(L("Registering device token…"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else if current.isConfigured {
                                        Text(L("Registered as key \(current.deviceKey)"))
                                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .tag(device.id)
                    }
                    .listStyle(.plain)
                    .frame(height: min(180, max(72, CGFloat(model.general.barkDevices.count) * 52)))

                    Divider()

                    HStack(spacing: 0) {
                        Button {
                            model.addBarkDevice()
                            selectedDeviceID = model.general.barkDevices.last?.id
                        } label: {
                            Image(systemName: "plus").frame(width: 28, height: 26)
                        }
                        .help(L("Add Device"))

                        Divider().frame(height: 20)

                        Button {
                            guard let selectedDeviceID, hasValidDeviceSelection else { return }
                            model.removeBarkDevice(id: selectedDeviceID)
                            self.selectedDeviceID = model.general.barkDevices.first?.id
                        } label: {
                            Image(systemName: "minus").frame(width: 28, height: 26)
                        }
                        .disabled(!hasValidDeviceSelection)
                        .help(L("Remove"))

                        Spacer()
                    }
                    .buttonStyle(.plain)
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.quaternary)
                }
            } header: {
                Text(L("Device token or key"))
            } footer: {
                Text(L("Paste the device token from Bark, or the key from its server list. A full URL such as https://api.day.app/yourkey/ also works."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(L("Send Test Notification")) { model.sendTest() }
                        .disabled(!model.general.isBarkConfigured || model.testStatus == .sending)
                    testStatusView
                }
                if let error = model.deliveryError {
                    HStack { Text(L("Delivery error")); Spacer(); Text(error).foregroundStyle(.red) }
                }
            }

            Section(L("Advanced")) {
                HStack {
                    Text(L("Server"))
                    Spacer()
                    HStack {
                        TextField(L("Server"), text: Binding(
                            get: { model.sharedBarkConfiguration.serverURL },
                            set: { model.setBarkServer($0) }
                        ), prompt: Text(BarkConfiguration.defaultServer))
                        .labelsHidden()
                        if model.sharedBarkConfiguration.serverURL != BarkConfiguration.defaultServer {
                            Button(L("Reset")) { model.resetBarkServer() }
                        }
                    }
                }
                Picker(L("Interruption level"), selection: Binding(
                    get: { model.sharedBarkConfiguration.level },
                    set: { model.setBarkLevel($0) }
                )) {
                    Text(L("Active")).tag(BarkLevel.active)
                    Text(L("Time Sensitive")).tag(BarkLevel.timeSensitive)
                    Text(L("Passive")).tag(BarkLevel.passive)
                }
                Toggle(L("Group notifications by app"), isOn: Binding(
                    get: { model.sharedBarkConfiguration.groupByApp },
                    set: { model.setBarkGroupByApp($0) }
                ))
                Toggle(L("Show app icons"), isOn: Binding(
                    get: { model.sharedBarkConfiguration.showsAppIcon },
                    set: { model.setBarkShowsAppIcon($0) }
                ))
                Toggle(L("Open the matching iPhone app on tap"), isOn: Binding(
                    get: { model.sharedBarkConfiguration.opensAppOnTap },
                    set: { model.setBarkOpensAppOnTap($0) }
                ))
            }
            .disabled(model.general.barkDevices.isEmpty)
        }
        .onAppear {
            if selectedDeviceID == nil { selectedDeviceID = model.general.barkDevices.first?.id }
        }
        .onChange(of: model.general.barkDevices.map(\.id)) { deviceIDs in
            if selectedDeviceID.map(deviceIDs.contains) != true {
                selectedDeviceID = deviceIDs.first
            }
        }
    }

    private func deviceValue(_ id: UUID) -> BarkConfiguration? {
        model.general.barkDevices.first { $0.id == id }
    }

    private var hasValidDeviceSelection: Bool {
        guard let selectedDeviceID else { return false }
        return model.general.barkDevices.contains { $0.id == selectedDeviceID }
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
