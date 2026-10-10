// Tatami/App/SettingsView.swift
import KeyboardShortcuts
import SwiftUI

/// ショートカットを変更する設定画面。保存は KeyboardShortcuts が UserDefaults に行う。
struct SettingsView: View {
    var body: some View {
        Form {
            ForEach(SnapCommand.allCases, id: \.self) { command in
                KeyboardShortcuts.Recorder(command.title, name: command.shortcutName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
