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
