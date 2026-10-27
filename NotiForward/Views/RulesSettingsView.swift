import AppKit
import SwiftUI

struct RulesSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var isChoosingApps = false
    @State private var selectedAppID: String?
    @State private var pendingAppRemovalID: String?

    /// Selected apps, including ones not found in the scanned folders.
    private var selectedApps: [CatalogApp] {
        model.rules.appBundleIDs
            .map { id in model.catalog.first { $0.bundleID == id } ?? CatalogApp.resolve(bundleID: id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SettingsForm {
            Section {
                Picker(L("Forwarding strategy"), selection: $model.rules.appMode) {
                    Text(L("Only forward selected apps")).tag(AppFilterMode.onlyAllowed)
                    Text(L("Forward all except selected apps")).tag(AppFilterMode.allExceptBlocked)
                }
                .onChange(of: model.rules.appMode) { _ in model.saveSettings() }
                VStack(spacing: 0) {
                    List(selectedApps) { app in
                        HStack(spacing: 10) {
                            AppIconView(app: app, size: 22)
                            Text(app.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAppID = app.bundleID }
                        .listRowBackground(selectedAppID == app.bundleID ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                    .listStyle(.plain)
                    .overlay {
                        if selectedApps.isEmpty {
                            Text(L("No apps selected."))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: min(220, max(86, CGFloat(selectedApps.count) * 34)))

                    Divider()

                    HStack(spacing: 0) {
                        Button { isChoosingApps = true } label: {
                            Image(systemName: "plus").frame(width: 28, height: 26)
                        }
                        .help(L("Choose Apps…"))

                        Divider().frame(height: 20)

                        Button {
                            guard let selectedAppID, hasValidAppSelection else { return }
                            pendingAppRemovalID = selectedAppID
                        } label: {
                            Image(systemName: "minus").frame(width: 28, height: 26)
                        }
                        .disabled(!hasValidAppSelection)
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
                    .onChange(of: model.rules.keywordFilteringEnabled) { _ in model.saveSettings() }
                Group {
                    Picker(L("Keyword strategy"), selection: $model.rules.keywordMode) {
                        Text(L("Block matching notifications")).tag(KeywordFilterMode.blocked)
                        Text(L("Only forward matching notifications")).tag(KeywordFilterMode.allowed)
                    }
                    .onChange(of: model.rules.keywordMode) { _ in model.saveSettings() }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: Binding(
                            get: { model.rules.keywords.joined(separator: "\n") },
                            set: { model.rules.keywords = $0.components(separatedBy: .newlines); model.saveSettings() }
                        ))
                        .font(.body)
                        if model.rules.keywords.joined().isEmpty {
                            Text(L("One keyword per line"))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 78, maxHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
                }
                .disabled(!model.rules.keywordFilteringEnabled)
            } header: {
                Text(L("Keywords"))
            }
        }
        .sheet(isPresented: $isChoosingApps) { AppPickerView(model: model) }
        .onChange(of: selectedApps.map(\.bundleID)) { appIDs in
            if selectedAppID.map(appIDs.contains) != true {
                selectedAppID = nil
            }
        }
        .confirmationDialog(
            "\(L("Remove")) “\(pendingAppRemovalName)”?",
            isPresented: Binding(
                get: { pendingAppRemovalID != nil },
                set: { if !$0 { pendingAppRemovalID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Remove"), role: .destructive) {
                guard let pendingAppRemovalID else { return }
                model.rules.appBundleIDs.remove(pendingAppRemovalID)
                model.saveSettings()
                selectedAppID = nil
                self.pendingAppRemovalID = nil
            }
        }
    }

    private var hasValidAppSelection: Bool {
        guard let selectedAppID else { return false }
        return selectedApps.contains { $0.bundleID == selectedAppID }
    }

    private var pendingAppRemovalName: String {
        guard let pendingAppRemovalID else { return "" }
        return selectedApps.first(where: { $0.bundleID == pendingAppRemovalID })?.name ?? pendingAppRemovalID
    }
}

private struct AppPickerView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredApps: [CatalogApp] {
        search.isEmpty ? model.catalog : model.catalog.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    private var filteredRecentSources: [RecentNotificationSource] {
        search.isEmpty ? model.recentSources : model.recentSources.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.identifier.localizedCaseInsensitiveContains(search)
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

            List {
                if !filteredRecentSources.isEmpty {
                    Section(L("Recent Sources")) {
                        ForEach(filteredRecentSources) { source in
                            Toggle(isOn: binding(for: source.identifier)) {
                                HStack(spacing: 10) {
                                    AppIconView(app: .resolve(bundleID: source.identifier), size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(source.name)
                                        HStack(spacing: 6) {
                                            if source.name != source.identifier {
                                                Text(source.identifier)
                                            }
                                            Text(source.lastSeenAt, style: .relative)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(L("Apps")) {
                    ForEach(filteredApps) { app in
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
                }
            }
            .listStyle(.bordered)

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
