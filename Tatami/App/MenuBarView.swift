// Tatami/App/MenuBarView.swift
import SwiftUI

/// メニューバー項目をクリックしたときのメニュー。
/// 権限状態は AppModel の観測対象の値を読む（更新は AppModel 側のポーリングと通知が担う）。
struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.isTrusted {
            Button("アクセシビリティ権限が必要です…") {
                model.permission.openSystemSettings()
            }
            Divider()
        }
        Button("レイアウトセット…") {
            model.openPicker()
        }
        if !model.layoutSets.sets.isEmpty {
            ForEach(model.layoutSets.sets) { set in
                Button(set.name) {
                    model.apply(set)
                }
            }
            Divider()
        }
        Button("設定…") {
            NSApp.activate()
            openSettings()
        }
        if DebugMenu.isEnabled {
            DebugMenu()
        }
        Divider()
        Button("tatami を終了") {
            NSApp.terminate(nil)
        }
    }
}
