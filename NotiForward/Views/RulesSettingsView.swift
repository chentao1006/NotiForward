import AppKit
import SwiftUI

struct RulesSettingsView: View {
    @Bindable var model: AppModel
    @State private var isChoosingApps = false

    /// Selected apps, including ones not found in the scanned folders.
    private var selectedApps: [CatalogApp] {
        model.rules.appBundleIDs
            .map { id in model.catalog.first { $0.bundleID == id } ?? CatalogApp.resolve(bundleID: id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                Picker(L("Forwarding strategy"), selection: $model.rules.appMode) {
                    Text(L("Only forward selected apps")).tag(AppFilterMode.onlyAllowed)
                    Text(L("Forward all except selected apps")).tag(AppFilterMode.allExceptBlocked)
                }
                .onChange(of: model.rules.appMode) { _, _ in model.saveSettings() }
                if selectedApps.isEmpty {
                    Text(L("No apps selected."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedApps) { app in
                        HStack(spacing: 10) {
                            AppIconView(app: app, size: 22)
                            Text(app.name)
                            Spacer()
                            Button {
                                model.rules.appBundleIDs.remove(app.bundleID)
                                model.saveSettings()
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(L("Remove"))
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(L("Choose Apps…")) { isChoosingApps = true }
                }
            } header: {
                Text(L("Apps"))
            } footer: {
                Group {
                    if model.rules.appMode == .allExceptBlocked {
                        Text(L("Notifications from these apps are not forwarded."))
                    } else {
                        Text(L("Only notifications from these apps are forwarded."))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L("Enable keyword filtering"), isOn: $model.rules.keywordFilteringEnabled)
                    .onChange(of: model.rules.keywordFilteringEnabled) { _, _ in model.saveSettings() }
                Group {
                    Picker(L("Keyword strategy"), selection: $model.rules.keywordMode) {
                        Text(L("Block matching notifications")).tag(KeywordFilterMode.blocked)
                        Text(L("Only forward matching notifications")).tag(KeywordFilterMode.allowed)
                    }
                    .onChange(of: model.rules.keywordMode) { _, _ in model.saveSettings() }
                    TextField(L("Keywords"), text: Binding(
                        get: { model.rules.keywords.joined(separator: "\n") },
                        set: { model.rules.keywords = $0.components(separatedBy: .newlines); model.saveSettings() }
                    ), prompt: Text(L("One keyword per line")), axis: .vertical)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
                }
                .disabled(!model.rules.keywordFilteringEnabled)
            } header: {
                Text(L("Keywords"))
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isChoosingApps) { AppPickerView(model: model) }
    }
}

private struct AppPickerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredApps: [CatalogApp] {
        search.isEmpty ? model.catalog : model.catalog.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search apps"), text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

            List(filteredApps) { app in
                Toggle(isOn: binding(for: app.bundleID)) {
                    HStack(spacing: 10) {
                        AppIconView(app: app, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 2)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()

            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 480, height: 540)
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { model.rules.appBundleIDs.contains(bundleID) },
            set: { selected in
                if selected { model.rules.appBundleIDs.insert(bundleID) }
                else { model.rules.appBundleIDs.remove(bundleID) }
                model.saveSettings()
            }
        )
    }
}

private struct AppIconView: View {
    let app: CatalogApp
    let size: CGFloat

    var body: some View {
        Image(nsImage: app.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
