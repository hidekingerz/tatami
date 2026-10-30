// Tatami/App/SettingsView.swift
import KeyboardShortcuts
import SwiftUI

/// 設定画面のタブ。`.layoutSets` の selectedID は、開いたときに展開するセット。
enum SettingsTab: Hashable {
    case commands(SnapCommand.Category)
    case layoutSets(selectedID: UUID?)

    /// `TabView` の tag と突き合わせる形。selectedID はタブの識別には使わない。
    var tag: SettingsTab {
        switch self {
        case .commands: self
        case .layoutSets: .layoutSets(selectedID: nil)
        }
    }
}

/// コマンドの有効/無効とショートカット、レイアウトセットを変更する設定画面。カテゴリごとにタブを分ける。
/// キーの保存は KeyboardShortcuts が、有効/無効の保存は CommandSettings が、セットの保存は LayoutSetStore が UserDefaults に行う。
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView(selection: Binding(
            get: { model.settingsTab.tag },
            set: { model.settingsTab = $0 }
        )) {
            ForEach(SnapCommand.Category.allCases, id: \.self) { category in
                CommandListTab(category: category, settings: model.settings)
                    .tabItem {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(nsImage: RegionGlyph.tabImage(for: category))
                        }
                    }
                    .tag(SettingsTab.commands(category))
            }
            LayoutSetsTab(model: model)
                .tabItem {
                    Label("セット", systemImage: "rectangle.3.group")
                }
                .tag(SettingsTab.layoutSets(selectedID: nil))
        }
        .frame(width: 640)
        .background(SettingsWindowCloseObserver())
    }
}

/// 設定ウィンドウが閉じたら tatami を非アクティブにし、前に使っていたアプリへフォーカスを返す。
/// メニューバーアプリは窓を閉じてもアクティブなままで、そのままだと 27 コマンドが
/// `NSApp.isActive` の判定で beep してしまうため。ホストしている NSWindow を直接つかんで通知を購読する。
private struct SettingsWindowCloseObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token {
                NotificationCenter.default.removeObserver(token)
                self.token = nil
            }
            guard let window else { return }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { NSApp.deactivate() }
            }
        }
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
                .accessibilityHidden(true)

            Spacer()

            KeyboardShortcuts.Recorder(for: command.shortcutName)
                .accessibilityLabel(command.title)
                .disabled(!isOn)
        }
    }
}
