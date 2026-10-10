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
        Button("設定…") {
            NSApp.activate()
            openSettings()
        }
        Divider()
        Button("tatami を終了") {
            NSApp.terminate(nil)
        }
    }
}
