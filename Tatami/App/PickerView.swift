// Tatami/App/PickerView.swift
import KeyboardShortcuts
import Observation
import SwiftUI

/// ピッカーの入力状態。パネルを閉じても残り、開くたびに `reset()` で初期化する。
@MainActor
@Observable
final class PickerState {
    /// 検索欄の文字。変わると選択を先頭に戻す。
    var query = "" {
        didSet { selectedIndex = 0 }
    }
    /// 絞り込んだ一覧の中での選択位置。
    var selectedIndex = 0
    /// 内訳を開いているセット。
    var expandedID: UUID?
    /// 増えるたびに検索欄へフォーカスを移す合図。パネルは使い回すので onAppear だけでは足りない。
    private(set) var focusRequest = 0

    /// query で絞ったセット。名前とアプリ名への部分一致、大文字小文字を無視。
    static func filter(_ sets: [LayoutSet], query: String) -> [LayoutSet] {
        guard !query.isEmpty else { return sets }
        return sets.filter { set in
            set.name.localizedCaseInsensitiveContains(query)
                || set.rows.contains { $0.appName.localizedCaseInsensitiveContains(query) }
        }
    }

    /// 開くたびに、検索と選択と内訳を初期状態に戻し、検索欄へフォーカスを移す。
    func reset() {
        query = ""
        selectedIndex = 0
        expandedID = nil
        focusRequest += 1
    }
}

/// レイアウトセットを選んで適用するピッカーの中身。上に検索欄、中にセットの行、下にキーのヒント。
///
/// キー操作は検索欄がフォーカスを持っていても効くよう、ルートの `.onKeyPress` で受ける
/// （`NSPanel.keyDown` はフィールドエディタが先に消費するので届かない）。
struct PickerView: View {
    static let width: CGFloat = 620
    /// 行の一覧の高さの上限。超えたらスクロールする。
    private static let maxListHeight: CGFloat = 400

    let store: LayoutSetStore
    let state: PickerState
    let onApply: (LayoutSet) -> Void
    let onEdit: (LayoutSet?) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool
    /// 行の一覧の中身の高さ。ScrollView を中身の高さに合わせ、パネルの高さを内容に応じさせる。
    @State private var listHeight: CGFloat = 0

    init(
        store: LayoutSetStore,
        state: PickerState,
        onApply: @escaping (LayoutSet) -> Void,
        onEdit: @escaping (LayoutSet?) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        self.store = store
        self.state = state
        self.onApply = onApply
        self.onEdit = onEdit
        self.onClose = onClose
    }

    private var filtered: [LayoutSet] {
        PickerState.filter(store.sets, query: state.query)
    }

    /// 選択中のセット。一覧が空なら nil。選択位置が一覧の外なら端に寄せる。
    private var selected: LayoutSet? {
        let sets = filtered
        guard !sets.isEmpty else { return nil }
        return sets[min(max(state.selectedIndex, 0), sets.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            hints
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard let selected else { return .ignored }
            state.expandedID = selected.id
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard state.expandedID != nil else { return .ignored }
            state.expandedID = nil
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            submit(edit: press.modifiers.contains(.command))
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onAppear { isSearchFocused = true }
        .onChange(of: state.focusRequest) { isSearchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("レイアウトセットを検索…", text: Binding(get: { state.query }, set: { state.query = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
            Text("\(filtered.count) セット")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.sets.isEmpty {
            message("設定でセットを作ってください")
        } else if filtered.isEmpty {
            message("一致するセットはありません")
        } else {
            list
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    private var list: some View {
        let sets = filtered
        let selectedID = selected?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(sets) { set in
                        PickerRow(
                            set: set,
                            isSelected: set.id == selectedID,
                            isExpanded: set.id == state.expandedID
                        )
                        .id(set.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onApply(set) }
                    }
                }
                .padding(6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, Self.maxListHeight))
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var hints: some View {
        Text("⏎ 適用  ↑↓ 選択  →← 内訳  ⌘⏎ 編集  esc 閉じる")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    /// 選択を動かす。端で止まり、循環しない。
    private func moveSelection(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        state.selectedIndex = min(max(state.selectedIndex + delta, 0), count - 1)
    }

    /// ⏎ は選択中のセットを適用し、⌘⏎ は設定で編集する。セットが 1 件もなければどちらも設定を開く。
    private func submit(edit: Bool) {
        if store.sets.isEmpty {
            onEdit(nil)
            return
        }
        guard let selected else { return }
        if edit {
            onEdit(selected)
        } else {
            onApply(selected)
        }
    }
}

/// ピッカーの 1 行。グリフ、名前、要約、デスクトップのバッジ、割当キー。開いていれば下に内訳。
private struct PickerRow: View {
    let set: LayoutSet
    let isSelected: Bool
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                RegionGlyph(actions: set.rows.compactMap(\.action))
                    .size(width: 48, height: 32)
                    .highlighted(isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryStyle)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(secondaryStyle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                ForEach(desktops, id: \.self) { desktop in
                    Text("デスクトップ \(desktop)")
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryStyle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(secondaryStyle, lineWidth: 1))
                }
                Text(keyLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryStyle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08))
                    )
            }
            if isExpanded {
                breakdown
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    /// 内訳。行ごとに「アプリ名 / 区画名 / デスクトップ N」。ここではウィンドウとの照合はしない。
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(set.rows.filter { !$0.isNoOp }) { row in
                HStack(spacing: 0) {
                    Text(row.appName)
                        .frame(width: 160, alignment: .leading)
                    Text(row.action?.title ?? "変えない")
                        .frame(width: 120, alignment: .leading)
                    if let desktop = row.desktop {
                        Text("デスクトップ \(desktop)")
                    }
                }
                .lineLimit(1)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(secondaryStyle)
        // グリフの幅（48）と間隔（12）だけ字下げして、名前の列に揃える。
        .padding(.leading, 60)
    }

    /// 「アプリ名 区画名」を「 ・ 」でつないだ要約。何もしない行は除く。
    private var summary: String {
        // 先頭の `set` はセッター節と解釈されるので self を付ける。
        self.set.rows
            .filter { !$0.isNoOp }
            .map { row in [row.appName, row.action?.title].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: " ・ ")
    }

    /// 行に出てくるデスクトップ番号（重複なし、昇順）。
    private var desktops: [Int] {
        Array(Set(set.rows.compactMap(\.desktop))).sorted()
    }

    private var keyLabel: String {
        KeyboardShortcuts.getShortcut(for: set.shortcutName)?.description ?? "未割当"
    }

    private var primaryStyle: Color {
        isSelected ? .white : .primary
    }

    private var secondaryStyle: Color {
        isSelected ? .white.opacity(0.85) : .secondary
    }
}
