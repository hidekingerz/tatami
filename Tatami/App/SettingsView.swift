// Tatami/App/SettingsView.swift
import KeyboardShortcuts
import SwiftUI

/// コマンドの有効/無効とショートカットを変更する設定画面。カテゴリごとにタブを分ける。
/// キーの保存は KeyboardShortcuts が、有効/無効の保存は CommandSettings が UserDefaults に行う。
struct SettingsView: View {
    let settings: CommandSettings

    var body: some View {
        TabView {
            ForEach(SnapCommand.Category.allCases, id: \.self) { category in
                CommandListTab(category: category, settings: settings)
                    .tabItem {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(nsImage: RegionGlyph.tabImage(for: category))
                        }
                    }
            }
        }
        .frame(width: 480)
    }
}

/// 1 カテゴリ分のコマンド一覧。
struct CommandListTab: View {
    let category: SnapCommand.Category
    let settings: CommandSettings

    var body: some View {
        Form {
            Section {
                ForEach(category.commands, id: \.self) { command in
                    CommandRow(command: command, settings: settings)
                }
            } header: {
                HStack {
                    Text(category.title)
                    Spacer()
                    Text("\(enabledCount) / \(category.commands.count) を使用中")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var enabledCount: Int {
        category.commands.filter(settings.isEnabled).count
    }
}

/// 1 コマンド分の行: トグル / 区画グリフ / 名前 / キーのレコーダー。
///
/// 無効のときは Recorder を操作不可にする。KeyboardShortcuts はキーを記録した時点でホットキーを登録するので、
/// 無効中に記録できると「無効なのに効く」状態になる。
struct CommandRow: View {
    let command: SnapCommand
    let settings: CommandSettings

    var body: some View {
        let isOn = settings.isEnabled(command)
        HStack(spacing: 10) {
            Toggle(command.title, isOn: Binding(
                get: { settings.isEnabled(command) },
                set: { settings.setEnabled($0, for: command) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            RegionGlyph(action: command.sequence[0], isEnabled: isOn)

            Text(command.isCycle ? "\(command.title) ⟳" : command.title)
                .foregroundStyle(isOn ? .primary : .secondary)

            Spacer()

            KeyboardShortcuts.Recorder(for: command.shortcutName)
                .disabled(!isOn)
        }
    }
}
