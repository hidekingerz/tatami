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

    /// query で絞った見出し付きの一覧。セット、区画の順。区画はお気に入りを先頭に、カテゴリ順を保つ。
    /// 一致が 0 件の見出しは含めない。
    static func sections(sets: [LayoutSet], favorites: Set<SnapAction>, query: String) -> [PickerSection] {
        let tokens = PickerQuery.tokens(query)
        let matchedSets = sets.filter { PickerQuery.matches(tokens: tokens, terms: PickerQuery.terms(of: $0)) }
        let all = SnapAction.allInCategoryOrder
        let ordered = all.filter(favorites.contains) + all.filter { !favorites.contains($0) }
        let matchedRegions = ordered.filter { PickerQuery.matches(tokens: tokens, terms: $0.searchTerms) }

        var result: [PickerSection] = []
        if !matchedSets.isEmpty {
            result.append(PickerSection(title: "セット", items: matchedSets.map(PickerItem.set)))
        }
        if !matchedRegions.isEmpty {
            result.append(PickerSection(title: "区画", items: matchedRegions.map(PickerItem.region)))
        }
        return result
    }

    /// 見出しを外して一列にした行。選択位置はこの並びで数える。
    static func flatten(_ sections: [PickerSection]) -> [PickerItem] {
        sections.flatMap(\.items)
    }

    /// 開くたびに、検索と選択と内訳を初期状態に戻し、検索欄へフォーカスを移す。
    func reset() {
        query = ""
        selectedIndex = 0
        expandedID = nil
        focusRequest += 1
    }
}

/// レイアウトセットと区画を選んで適用するピッカーの中身。上に検索欄、中に見出し付きの行、下にキーのヒント。
///
/// キー操作は検索欄がフォーカスを持っていても効くよう、ルートの `.onKeyPress` で受ける
/// （`NSPanel.keyDown` はフィールドエディタが先に消費するので届かない）。
struct PickerView: View {
    static let width: CGFloat = 620
    /// 行の一覧の高さの上限。超えたらスクロールする。
    private static let maxListHeight: CGFloat = 400

    let store: LayoutSetStore
    let favorites: FavoriteRegions
    let settings: CommandSettings
    let state: PickerState
    let onApply: (LayoutSet) -> Void
    let onApplyRegion: (SnapAction) -> Void
    let onEdit: (LayoutSet?) -> Void
    let onEditRegion: (SnapCommand.Category) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool
    /// 行の一覧の中身の高さ。ScrollView を中身の高さに合わせ、パネルの高さを内容に応じさせる。
    @State private var listHeight: CGFloat = 0

    init(
        store: LayoutSetStore,
        favorites: FavoriteRegions,
        settings: CommandSettings,
        state: PickerState,
        onApply: @escaping (LayoutSet) -> Void,
        onApplyRegion: @escaping (SnapAction) -> Void,
        onEdit: @escaping (LayoutSet?) -> Void,
        onEditRegion: @escaping (SnapCommand.Category) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        self.store = store
        self.favorites = favorites
        self.settings = settings
        self.state = state
        self.onApply = onApply
        self.onApplyRegion = onApplyRegion
        self.onEdit = onEdit
        self.onEditRegion = onEditRegion
        self.onClose = onClose
    }

    private var sections: [PickerSection] {
        PickerState.sections(sets: store.sets, favorites: favorites.regions, query: state.query)
    }

    private var items: [PickerItem] {
        PickerState.flatten(sections)
    }

    /// 選択中の行。一覧が空なら nil。選択位置が一覧の外なら端に寄せる。
    private var selected: PickerItem? {
        let items = items
        guard !items.isEmpty else { return nil }
        return items[min(max(state.selectedIndex, 0), items.count - 1)]
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
            guard let set = selected?.setValue else { return .ignored }
            state.expandedID = set.id
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
        .onKeyPress(characters: CharacterSet(charactersIn: "dD"), phases: .down) { press in
            guard press.modifiers.contains(.command), let region = selected?.region else { return .ignored }
            toggleFavorite(region)
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
            TextField("セットや区画を検索…", text: Binding(get: { state.query }, set: { state.query = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isSearchFocused)
            Text("\(items.count) 件")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            message("一致する項目はありません")
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
        let sections = sections
        let selectedID = selected?.id
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 10)
                        ForEach(section.items) { item in
                            row(for: item, isSelected: item.id == selectedID)
                                .id(item.id)
                        }
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

    @ViewBuilder
    private func row(for item: PickerItem, isSelected: Bool) -> some View {
        switch item {
        case .set(let set):
            PickerRow(set: set, isSelected: isSelected, isExpanded: set.id == state.expandedID)
                .contentShape(Rectangle())
                .onTapGesture { onApply(set) }
        case .region(let action):
            RegionRow(
                action: action,
                isSelected: isSelected,
                isFavorite: favorites.contains(action),
                keyLabel: keyLabel(for: action),
                onToggleFavorite: { toggleFavorite(action) }
            )
            .contentShape(Rectangle())
            .onTapGesture { onApplyRegion(action) }
        }
    }

    /// 区画に単独で対応するコマンドがあり、有効で、キーが割り当てられているときだけ、そのキーの表記。
    private func keyLabel(for action: SnapAction) -> String? {
        guard let command = action.singleCommand, settings.isEnabled(command) else { return nil }
        return KeyboardShortcuts.getShortcut(for: command.shortcutName)?.description
    }

    private var hints: some View {
        Text("⏎ 適用  ↑↓ 選択  →← 内訳  ⌘D ★  ⌘⏎ 編集  esc 閉じる")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    /// 選択を動かす。見出しをまたいで一列に数え、端で止まり、循環しない。
    /// ★ を付け外しし、並びが変わるので選択を同じ区画の新しい位置に移す。
    private func toggleFavorite(_ region: SnapAction) {
        favorites.toggle(region)
        state.selectedIndex = items.firstIndex(of: .region(region)) ?? state.selectedIndex
    }

    private func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        state.selectedIndex = min(max(state.selectedIndex + delta, 0), count - 1)
    }

    /// ⏎ は選択中の行を適用し、⌘⏎ は設定で編集する。区画の編集はその区画のコマンドのカテゴリのタブを開く。
    private func submit(edit: Bool) {
        guard let selected else { return }
        switch selected {
        case .set(let set):
            if edit {
                onEdit(set)
            } else {
                onApply(set)
            }
        case .region(let action):
            if edit {
                onEditRegion(action.singleCommand?.category ?? .halves)
            } else {
                onApplyRegion(action)
            }
        }
    }
}

/// ピッカーの区画の 1 行。グリフ、区画名、割当キー、★。セットの行より低い 1 行。
private struct RegionRow: View {
    let action: SnapAction
    let isSelected: Bool
    let isFavorite: Bool
    let keyLabel: String?
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RegionGlyph(action: action)
                .size(width: 36, height: 22)
                .highlighted(isSelected)
            Text(action.title)
                .font(.system(size: 14))
                .foregroundStyle(primaryStyle)
            Spacer(minLength: 8)
            if let keyLabel {
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
            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(starStyle)
            }
            .buttonStyle(.borderless)
            .help("★ を付ける／外す")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    private var primaryStyle: Color {
        isSelected ? .white : .primary
    }

    private var secondaryStyle: Color {
        isSelected ? .white.opacity(0.85) : .secondary
    }

    /// 付いている ★ はアクセント色で目立たせる。選択中は背景がアクセント色なので白にする。
    private var starStyle: Color {
        guard isFavorite else { return secondaryStyle }
        return isSelected ? .white : .accentColor
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
