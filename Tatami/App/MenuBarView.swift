// Tatami/App/MenuBarView.swift
import SwiftUI

/// メニューバー項目をクリックしたときのメニュー。開くたびに body が評価されるので権限状態は毎回読む。
struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permission.isTrusted {
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
