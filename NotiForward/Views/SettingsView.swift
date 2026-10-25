import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

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
#if APP_STORE
            ProSettingsView(model: model)
                .tabItem { Label(L("Pro"), systemImage: "sparkles") }
                .tag(AppModel.SettingsTab.pro)
#endif
        }
        .id(model.language.language)
        .task { await model.start() }
        // The app is a menu bar agent (LSUIElement); show a Dock icon only while Settings is open.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
