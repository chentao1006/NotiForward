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

    /// Free users can only allow-list; picking the block list opens the Pro tab instead.
    private var appMode: Binding<AppFilterMode> {
        Binding(
            get: { model.effectiveRules.appMode },
            set: { mode in
                guard model.isPro || mode == .onlyAllowed else { return model.showPro() }
                model.rules.appMode = mode
                model.saveSettings()
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L("Forwarding strategy"), selection: appMode) {
                    Text(L("Only forward selected apps")).tag(AppFilterMode.onlyAllowed)
                    Text(model.isPro ? L("Forward all except selected apps") : L("Forward all except selected apps (Pro)"))
                        .tag(AppFilterMode.allExceptBlocked)
                }
                if selectedApps.isEmpty {
                    Text(L("No apps selected."))
                        .foregroundStyle(.secondary)
                } else {
                    let freeApps = ProLimits.freeApps(in: model.rules)
                    ForEach(selectedApps) { app in
                        let isLimited = !model.isPro && !freeApps.contains(app.bundleID)
                        HStack(spacing: 10) {
                            AppIconView(app: app, size: 22)
                            Text(app.name)
                            if isLimited { ProBadge() }
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
                        .opacity(isLimited ? 0.5 : 1)
                    }
                }
                HStack {
                    if !model.isPro {
                        Button(L("Upgrade to Pro")) { model.showPro() }
                    }
                    Spacer()
                    Button(L("Choose Apps…")) { isChoosingApps = true }
                }
            } header: {
                Text(L("Apps"))
            } footer: {
                Group {
                    if !model.isPro {
                        Text(L("The free version forwards notifications from one app."))
                    } else if model.rules.appMode == .allExceptBlocked {
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
                HStack(spacing: 6) {
                    Text(L("Keywords"))
                    if !model.isPro { ProBadge() }
                }
            } footer: {
                if !model.isPro {
                    HStack {
                        Text(L("Keyword filtering is a Pro feature.")).font(.caption).foregroundStyle(.secondary)
                        Button(L("Upgrade to Pro")) { model.showPro() }.controlSize(.small)
                    }
                }
            }
            .disabled(!model.isPro)
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

            if !model.isPro {
                HStack(spacing: 6) {
                    Text(L("The free version forwards notifications from one app.")).font(.caption).foregroundStyle(.secondary)
                    ProBadge()
                    Spacer()
                }
            }

            List(filteredApps) { app in
                let isSelected = model.rules.appBundleIDs.contains(app.bundleID)
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
                .disabled(!model.isPro && !isSelected && model.rules.appBundleIDs.count >= ProLimits.freeAppCount)
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
