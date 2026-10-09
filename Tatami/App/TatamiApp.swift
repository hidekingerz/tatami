// Tatami/App/TatamiApp.swift
import SwiftUI

/// アプリのエントリポイント。Task 9 でメニューと設定画面を配線する。
@main
struct TatamiApp: App {
    var body: some Scene {
        MenuBarExtra("tatami", systemImage: "rectangle.split.2x1") {
            Button("tatami を終了") {
                NSApp.terminate(nil)
            }
        }
    }
}
