import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            GeneralSettingsView(model: model)
                .tabItem { Label(L("General"), systemImage: "gearshape") }
                .tag(AppModel.SettingsTab.general)
            RulesSettingsView(model: model)
                .tabItem { Label(L("Forwarding Rules"), systemImage: "line.3.horizontal.decrease.circle") }
                .tag(AppModel.SettingsTab.rules)
            ClientSettingsView(model: model)
                .tabItem { Label(L("Client"), systemImage: "iphone") }
                .tag(AppModel.SettingsTab.client)
        }
        .id(model.language.language)
        .environment(\.locale, model.language.locale)
    }
}

/// `Form` uses the old, centered two-column preferences layout on Monterey. Keep the native
/// grouped form on newer systems and give macOS 12 a compact, top-aligned scrolling layout.
struct SettingsForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder var body: some View {
        if #available(macOS 13.0, *) {
            Form { content }
                .formStyle(.grouped)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
