// Tatami/App/TatamiApp.swift
import SwiftUI

/// アプリのエントリポイント。メニューバー項目と設定ウィンドウの 2 シーンを持つ。
@main
struct TatamiApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra("tatami", systemImage: "rectangle.split.2x1") {
            MenuBarView(model: model)
        }
        Settings {
            SettingsView()
        }
    }
}
