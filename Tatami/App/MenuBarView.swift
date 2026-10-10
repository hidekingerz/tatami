// Tatami/App/MenuBarView.swift
import SwiftUI

/// メニューバー項目をクリックしたときのメニュー。
/// 権限状態は AppModel の観測対象の値を読み、メニューを開くたびにも読み直して古い表示を正す。
struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            content
        }
        .onAppear {
            // Group の修飾子は子ごとに効くので複数回呼ばれうるが、refreshTrust は冪等。
            model.refreshTrust()
        }
    }

    @ViewBuilder
    private var content: some View {
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
