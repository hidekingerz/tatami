// Tatami/App/LayoutSetsTab.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

/// 設定画面の「セット」タブ。ピッカーのキー、セットアップの警告、セットの一覧と編集を並べる。
///
/// セットの読み書きは `LayoutSetStore` のメソッドだけで行い、変更はその場で保存する。
/// `store.onChange` は ShortcutRegistrar がホットキーの同期に使う唯一の口なので、ここでは触らない。
struct LayoutSetsTab: View {
    let model: AppModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// 展開しているセット。
    @State private var expanded: Set<UUID> = []
    /// Mission Control の自動並べ替え（mru-spaces）がオンか。表示のたびに読み直す。
    @State private var rearrangesSpaces = false
    /// 「デスクトップ N へ切り替え」が有効な N。表示のたびに読み直す。
    @State private var enabledDesktopShortcuts: Set<Int> = []
    @State private var isConfirmingDisable = false
    @State private var disableFailed = false
    @State private var isCapturing = false

    init(model: AppModel) {
        self.model = model
    }

    private var store: LayoutSetStore { model.layoutSets }

    /// いずれかのセットの行が指しているデスクトップ番号。
    private var usedDesktops: Set<Int> {
        Set(store.sets.flatMap(\.rows).compactMap(\.desktop))
    }

    /// 使っているのにショートカットがオフのデスクトップ番号。
    private var desktopsWithoutShortcut: [Int] {
        usedDesktops.subtracting(enabledDesktopShortcuts).sorted()
    }

    var body: some View {
        Form {
            Section("ピッカー") {
                KeyboardShortcuts.Recorder("ピッカーを開く", name: ShortcutRegistrar.pickerName)
            }

            if rearrangesSpaces && !usedDesktops.isEmpty {
                Section {
                    warning(
                        "Mission Control の『最新の使用状況に基づいて操作スペースを自動的に並べ替える』がオンです。"
                            + "オンの間はデスクトップ番号への移動を飛ばします。",
                        buttonTitle: "オフにする…"
                    ) {
                        isConfirmingDisable = true
                    }
                }
            }

            if !desktopsWithoutShortcut.isEmpty {
                Section {
                    warning(
                        "デスクトップ \(desktopsWithoutShortcut.map(String.init).joined(separator: "、")) "
                            + "へ切り替えるショートカットがオフです。"
                            + "システム設定 → キーボード → キーボードショートカット → Mission Control で有効にしてください。",
                        buttonTitle: "システム設定を開く"
                    ) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") {
                            openURL(url)
                        }
                    }
                }
            }

            Section("セット") {
                if store.sets.isEmpty {
                    Text("セットはまだありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.sets) { set in
                    LayoutSetEditor(set: set, store: store, isExpanded: expansion(for: set.id))
                }
            }

            Section {
                HStack {
                    Button("セットを追加") {
                        let set = LayoutSet(name: "名称未設定")
                        store.add(set)
                        expanded.insert(set.id)
                    }
                    Button("いまの配置を保存") {
                        isCapturing = true
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Dock を再起動します。デスクトップの並びが変わることがあります。",
            isPresented: $isConfirmingDisable
        ) {
            Button("オフにする") {
                disableAutomaticRearrangement()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("自動並べ替えをオフにできませんでした", isPresented: $disableFailed) {
            Button("OK") {}
        } message: {
            Text("システム設定 → デスクトップと Dock で手動でオフにしてください")
        }
        .sheet(isPresented: $isCapturing) {
            CaptureSheet { desktop in
                captureCurrentLayout(desktop: desktop)
            }
        }
        .onAppear {
            refreshWarnings()
            expandSelectedSet()
        }
        .onChange(of: scenePhase) {
            refreshWarnings()
        }
        // 設定画面が開いたままピッカーの ⌘⏎ で別のセットを指定された場合も展開する。
        .onChange(of: model.settingsTab) {
            expandSelectedSet()
        }
    }

    private func warning(_ message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(buttonTitle, action: action)
        }
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }

    /// ピッカーから指定されたセットを展開し、指定を消費する（次に開いたときに勝手に開き直さないように）。
    private func expandSelectedSet() {
        guard case let .layoutSets(selectedID?) = model.settingsTab else { return }
        expanded.insert(selectedID)
        model.settingsTab = .layoutSets(selectedID: nil)
    }

    /// OS 側の設定（自動並べ替えとデスクトップ切り替えのショートカット）を読み直す。
    private func refreshWarnings() {
        rearrangesSpaces = model.dockPreferences.rearrangesSpacesAutomatically
        enabledDesktopShortcuts = Set(LayoutRow.desktopRange.filter {
            model.missionControl.switchToDesktopShortcut($0) != nil
        })
    }

    /// mru-spaces を書き換えて Dock を再起動する（終了を待つので少し固まる）。
    /// Dock の再起動で利用者が別のデスクトップへ飛ぶことがあり onAppear は当てにならないので、直後に読み直す。
    private func disableAutomaticRearrangement() {
        do {
            try model.dockPreferences.disableAutomaticRearrangement()
        } catch {
            disableFailed = true
        }
        refreshWarnings()
    }

    /// いまの配置を行にした「名称未設定」セットを足して開く。
    private func captureCurrentLayout(desktop: Int?) {
        let set = LayoutSet(name: "名称未設定", rows: model.capture.capture(desktop: desktop))
        store.add(set)
        expanded.insert(set.id)
    }
}

/// 1 セット分の編集欄。ヘッダに名前・キー・削除、開くと行の一覧。
struct LayoutSetEditor: View {
    let set: LayoutSet
    let store: LayoutSetStore
    @Binding var isExpanded: Bool

    /// 同じアプリの行が 2 つ以上あり、どれもタイトルで絞り込んでいない bundle identifier。
    private var ambiguousBundleIDs: Set<String> {
        let groups = Dictionary(grouping: set.rows, by: \.bundleIdentifier)
        return Set(groups.filter { $0.value.count >= 2 && $0.value.allSatisfy(\.titleFilter.isEmpty) }.keys)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let ambiguous = ambiguousBundleIDs
            ForEach(set.rows) { row in
                LayoutRowEditor(
                    row: row,
                    showsDuplicateHint: ambiguous.contains(row.bundleIdentifier),
                    onChange: { updated in
                        edit { set in
                            guard let index = set.rows.firstIndex(where: { $0.id == updated.id }) else { return }
                            set.rows[index] = updated
                        }
                    },
                    onDelete: {
                        edit { set in set.rows.removeAll { $0.id == row.id } }
                    }
                )
            }
            .onMove { offsets, destination in
                edit { set in set.rows.move(fromOffsets: offsets, toOffset: destination) }
            }
            Button("行を追加") {
                edit { set in set.rows.append(LayoutRow(bundleIdentifier: "", appName: "")) }
            }
        } label: {
            HStack {
                TextField("セット名", text: Binding(
                    get: { set.name },
                    set: { name in edit { set in set.name = name } }
                ))
                .labelsHidden()
                KeyboardShortcuts.Recorder(for: set.shortcutName)
                Button(role: .destructive) {
                    store.remove(id: set.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("セットを削除")
            }
        }
    }

    /// store にある最新の値を変更して保存する。描画時点の `set` を元にすると、
    /// 再描画の前に続けて届いた変更を上書きしてしまうため。
    private func edit(_ transform: (inout LayoutSet) -> Void) {
        guard var latest = store.set(id: set.id) else { return }
        transform(&latest)
        store.update(latest)
    }
}

/// 1 行分の編集欄: アプリ / タイトルの絞り込み / 区画 / デスクトップ / 削除。
struct LayoutRowEditor: View {
    /// アプリの Picker で「bundle identifier を入力…」を表す tag。bundle identifier と重ならない値にする。
    private static let customBundleIDTag = "\u{0}custom"

    let row: LayoutRow
    let showsDuplicateHint: Bool
    let onChange: (LayoutRow) -> Void
    let onDelete: () -> Void

    @State private var isEnteringBundleID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isEnteringBundleID {
                    TextField("bundle identifier", text: Binding(
                        get: { row.bundleIdentifier },
                        set: { id in
                            var updated = row
                            updated.bundleIdentifier = id
                            updated.appName = Self.appName(for: id)
                            onChange(updated)
                        }
                    ))
                    .onSubmit { isEnteringBundleID = false }
                    .frame(width: 200)
                } else {
                    appPicker
                }
                TextField("タイトル", text: Binding(
                    get: { row.titleFilter },
                    set: { filter in
                        var updated = row
                        updated.titleFilter = filter
                        onChange(updated)
                    }
                ), prompt: Text("タイトルに含む文字（任意）"))
                .labelsHidden()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("行を削除")
            }
            HStack {
                regionMenu
                desktopPicker
                if row.isNoOp {
                    Text("何もしない")
                }
                Spacer()
            }
            if showsDuplicateHint {
                Text("同じアプリが複数あります。区別するなら絞り込みを入れてください")
                    .font(.caption)
            }
        }
        .foregroundStyle(row.isNoOp ? .secondary : .primary)
        .padding(.vertical, 2)
    }

    /// 起動中の通常アプリを名前順に。同じ bundle identifier は 1 つにまとめる。
    private var runningApps: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var appPicker: some View {
        let apps = runningApps
        let isListed = apps.contains { $0.bundleID == row.bundleIdentifier }
        return Picker("アプリ", selection: Binding(
            get: { row.bundleIdentifier },
            set: { id in
                if id == Self.customBundleIDTag {
                    isEnteringBundleID = true
                    return
                }
                var updated = row
                updated.bundleIdentifier = id
                updated.appName = apps.first { $0.bundleID == id }?.name ?? Self.appName(for: id)
                onChange(updated)
            }
        )) {
            // 起動していないアプリ（または未選択）でも、いまの値を先頭に出す。
            if !isListed {
                Text(currentAppLabel).tag(row.bundleIdentifier)
                Divider()
            }
            ForEach(apps, id: \.bundleID) { app in
                Text(app.name).tag(app.bundleID)
            }
            Divider()
            Text("bundle identifier を入力…").tag(Self.customBundleIDTag)
        }
        .labelsHidden()
        .frame(width: 200)
    }

    private var currentAppLabel: String {
        if row.bundleIdentifier.isEmpty { return "アプリを選択" }
        return row.appName.isEmpty ? row.bundleIdentifier : row.appName
    }

    private var regionMenu: some View {
        Menu {
            Button("変えない") { setAction(nil) }
            Divider()
            ForEach(SnapCommand.Category.allCases, id: \.self) { category in
                Menu(category.title) {
                    ForEach(category.actions, id: \.self) { action in
                        Button {
                            setAction(action)
                        } label: {
                            Label {
                                Text(action.title)
                            } icon: {
                                Image(nsImage: RegionMenuImages.image(for: action))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let action = row.action {
                    RegionGlyph(action: action, isEnabled: !row.isNoOp)
                    Text(action.title)
                } else {
                    Text("変えない")
                }
            }
        }
        .fixedSize()
    }

    private var desktopPicker: some View {
        Picker("デスクトップ", selection: Binding(
            get: { row.desktop },
            set: { desktop in
                var updated = row
                updated.desktop = desktop
                onChange(updated)
            }
        )) {
            Text("変えない").tag(Int?.none)
            ForEach(Array(LayoutRow.desktopRange), id: \.self) { number in
                Text("\(number)").tag(Int?.some(number))
            }
        }
        .fixedSize()
    }

    private func setAction(_ action: SnapAction?) {
        var updated = row
        updated.action = action
        onChange(updated)
    }

    /// bundle identifier からアプリ名を引く。起動中ならその名前、インストール済みならアプリのファイル名、どちらでもなければ id のまま。
    private static func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

/// 「いまの配置を保存」で、全行に入れるデスクトップ番号を 1 回だけ聞くシート。
private struct CaptureSheet: View {
    let onSave: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var desktop: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("いまの配置を保存")
                .font(.headline)
            Picker("このセットはデスクトップ何番ですか", selection: $desktop) {
                Text("指定しない").tag(Int?.none)
                ForEach(Array(LayoutRow.desktopRange), id: \.self) { number in
                    Text("\(number)").tag(Int?.some(number))
                }
            }
            Text("いま表示しているデスクトップの番号です。macOS は番号を教えてくれないので、tatami は推測しません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(desktop)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private extension SnapCommand.Category {
    /// このカテゴリの区画。各コマンドの先頭の区画で、ループ系は半分の区画になる。27 区画がちょうど 1 回ずつ現れる。
    var actions: [SnapAction] {
        commands.map { $0.sequence[0] }
    }
}

/// 区画メニューの項目に付ける画像。NSMenu は SwiftUI のビューを描けないので NSImage にする。
@MainActor
private enum RegionMenuImages {
    private static var cache: [SnapAction: NSImage] = [:]

    static func image(for action: SnapAction) -> NSImage {
        if let cached = cache[action] {
            return cached
        }
        let renderer = ImageRenderer(content: RegionGlyph(action: action))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 24, height: 15))
        image.isTemplate = true
        cache[action] = image
        return image
    }
}
