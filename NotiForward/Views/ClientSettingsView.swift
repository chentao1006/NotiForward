import SwiftUI

struct ClientSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedDeviceID: UUID?
    @State private var editingDeviceID: UUID?
    @State private var pendingDeviceRemovalID: UUID?
    @FocusState private var focusedDeviceID: UUID?

    var body: some View {
        SettingsForm {
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
                    List(model.general.barkDevices) { device in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                if editingDeviceID == device.id {
                                    TextField(L("Device token or key"), text: Binding(
                                        get: { deviceValue(device.id)?.input ?? "" },
                                        set: { model.setBarkInput($0, deviceID: device.id) }
                                    ), prompt: Text(L("Paste the device token, key or URL from the Bark app")))
                                    .labelsHidden()
                                    .textFieldStyle(.plain)
                                    .font(.system(.body, design: .monospaced))
                                    .focused($focusedDeviceID, equals: device.id)
                                    .onSubmit { finishEditing() }
                                    .onExitCommand { finishEditing() }
                                } else {
                                    let input = deviceValue(device.id)?.input ?? ""
                                    Text(input.isEmpty ? L("Paste the device token, key or URL from the Bark app") : input)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(input.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

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
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing(device.id) }
                        .onTapGesture {
                            if selectedDeviceID != device.id { finishEditing() }
                            selectedDeviceID = device.id
                        }
                        .listRowBackground(selectedDeviceID == device.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                    .listStyle(.plain)
                    .frame(height: min(180, max(72, CGFloat(model.general.barkDevices.count) * 52)))

                    Divider()

                    HStack(spacing: 0) {
                        Button {
                            model.addBarkDevice()
                            selectedDeviceID = model.general.barkDevices.last?.id
                            if let selectedDeviceID { beginEditing(selectedDeviceID) }
                        } label: {
                            Image(systemName: "plus").frame(width: 28, height: 26)
                        }
                        .help(L("Add Device"))

                        Divider().frame(height: 20)

                        Button {
                            guard let selectedDeviceID, hasValidDeviceSelection else { return }
                            finishEditing()
                            pendingDeviceRemovalID = selectedDeviceID
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
        .onChange(of: model.general.barkDevices.map(\.id)) { deviceIDs in
            if selectedDeviceID.map(deviceIDs.contains) != true {
                selectedDeviceID = nil
            }
            if editingDeviceID.map(deviceIDs.contains) != true { finishEditing() }
        }
        .confirmationDialog(
            "\(L("Remove")) “\(pendingDeviceRemovalLabel)”?",
            isPresented: Binding(
                get: { pendingDeviceRemovalID != nil },
                set: { if !$0 { pendingDeviceRemovalID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Remove"), role: .destructive) {
                guard let pendingDeviceRemovalID else { return }
                model.removeBarkDevice(id: pendingDeviceRemovalID)
                selectedDeviceID = nil
                self.pendingDeviceRemovalID = nil
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

    private var pendingDeviceRemovalLabel: String {
        guard let pendingDeviceRemovalID,
              let device = model.general.barkDevices.first(where: { $0.id == pendingDeviceRemovalID }) else { return "" }
        let input = device.input.trimmingCharacters(in: .whitespacesAndNewlines)
        return input.isEmpty ? "\(L("Device token or key")) (—)" : input
    }

    private func beginEditing(_ id: UUID) {
        selectedDeviceID = id
        editingDeviceID = id
        DispatchQueue.main.async { focusedDeviceID = id }
    }

    private func finishEditing() {
        focusedDeviceID = nil
        editingDeviceID = nil
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
