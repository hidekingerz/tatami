// Tatami/App/PickerPanel.swift
import AppKit
import SwiftUI

/// レイアウトセットと区画のピッカーを出すパネル。開いている間は入力ソースを ASCII にし、閉じたら戻す。
///
/// 検索欄に文字を入れるため、非アクティブ化パネルではなく通常の key window にする（tatami を前面にする）。
/// 閉じるときは開く前に前面だったアプリへ戻す。メニューバーアプリは窓を閉じてもアクティブなままで、
/// 戻さないと既存コマンドが `NSApp.isActive` の判定で beep し続けるため。
@MainActor
final class PickerPanel: NSPanel {
    /// メインディスプレイの可視領域の上端から、パネル上端までの割合。
    private static let topRatio: CGFloat = 1.0 / 5

    private let store: LayoutSetStore
    private let inputSource: any InputSourceSwitching
    private let state = PickerState()
    private let onApply: @MainActor (LayoutSet) -> Void
    private let onApplyRegion: @MainActor (SnapAction) -> Void
    private let onEdit: @MainActor (LayoutSet?) -> Void
    private let onEditRegion: @MainActor (SnapCommand.Category) -> Void
    /// 閉じるたびに（どの経路でも）1 回呼ぶ。
    private let onDismiss: @MainActor () -> Void
    /// 開く前に前面だったアプリ。閉じるときにアクティブへ戻す。
    private var previousApp: NSRunningApplication?
    /// 表示中のパネル上端の y（NS 座標）。内容に応じて高さが変わっても上端を動かさない。
    private var anchorTop: CGFloat?
    /// 閉じている途中。orderOut から resignKey 経由で再入しても restore / onDismiss を二重に呼ばない。
    private var isDismissing = false

    init(
        store: LayoutSetStore,
        favorites: FavoriteRegions,
        settings: CommandSettings,
        inputSource: any InputSourceSwitching,
        onApply: @escaping @MainActor (LayoutSet) -> Void,
        onApplyRegion: @escaping @MainActor (SnapAction) -> Void,
        onEdit: @escaping @MainActor (LayoutSet?) -> Void,
        onEditRegion: @escaping @MainActor (SnapCommand.Category) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.inputSource = inputSource
        self.onApply = onApply
        self.onApplyRegion = onApplyRegion
        self.onEdit = onEdit
        self.onEditRegion = onEditRegion
        self.onDismiss = onDismiss
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: PickerView.width, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        // 中身の大きさに合わせてパネルの大きさが変わる（NSHostingView の既定の sizingOptions）。
        contentView = NSHostingView(
            rootView: PickerView(
                store: store,
                favorites: favorites,
                settings: settings,
                state: state,
                onApply: { [weak self] set in self?.apply(set) },
                onApplyRegion: { [weak self] action in self?.applyRegion(action) },
                onEdit: { [weak self] set in self?.edit(set) },
                onEditRegion: { [weak self] category in self?.editRegion(category) },
                onClose: { [weak self] in self?.close() }
            )
        )
    }

    /// 枠なしパネルは既定で key になれないので、検索欄に入力できるよう許す。
    override var canBecomeKey: Bool { true }

    /// 出ていれば閉じ、出ていなければメイン画面の中央上寄りに出して key にする。
    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// 閉じて、開く前に前面だったアプリへ戻す。閉じていれば何もしない。
    override func close() {
        dismiss(restoringPreviousApp: true)
    }

    /// フォーカスを失ったら閉じる（別のアプリをクリックした、など）。
    /// 元のアプリに戻すのは tatami がまだ前面のときだけ。利用者が別アプリをクリックした場合は
    /// そのアプリに任せる（戻すと、クリックしたアプリからフォーカスを奪ってしまう）。
    override func resignKey() {
        super.resignKey()
        dismiss(restoringPreviousApp: NSApp.isActive)
    }

    /// 検索欄のフィールドエディタが esc を `cancelOperation:` にして送ってきた場合の受け口。
    /// 通常は PickerView の `.onKeyPress(.escape)` が先に処理する。
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    /// 内容に応じて高さが変わっても、上端を固定して下に伸び縮みさせる。
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let anchorTop {
            frame.origin.y = anchorTop - frame.height
        }
        super.setFrame(frame, display: flag)
    }

    private func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == NSRunningApplication.current ? nil : frontmost
        inputSource.enterASCII()
        state.reset()

        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let top = visible.maxY - visible.height * Self.topRatio
        anchorTop = top
        let size = contentView?.fittingSize ?? frame.size
        setFrame(
            CGRect(x: visible.midX - PickerView.width / 2, y: top - size.height, width: PickerView.width, height: size.height),
            display: false
        )

        // activateIgnoringOtherApps は macOS 14 で非推奨（効果なし）なので、協調的アクティブ化を使う。
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    private func dismiss(restoringPreviousApp: Bool) {
        guard isVisible, !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        // orderOut の途中で resignKey から close が再入しても二重に戻さないよう、先に手放す。
        let previous = previousApp
        previousApp = nil
        anchorTop = nil
        orderOut(nil)
        inputSource.restore()
        onDismiss()
        if restoringPreviousApp {
            previous?.activate()
        }
    }

    /// 閉じてから適用する。適用中に tatami が前面に残ると合成マウス操作を邪魔するため。
    private func apply(_ set: LayoutSet) {
        close()
        onApply(set)
    }

    /// 区画は閉じずに渡す。覚えておいたウィンドウに適用してから閉じるのは受け取り側の役目。
    private func applyRegion(_ action: SnapAction) {
        onApplyRegion(action)
    }

    /// 設定画面を開くので、元のアプリには戻さずに閉じる。
    private func edit(_ set: LayoutSet?) {
        dismiss(restoringPreviousApp: false)
        onEdit(set)
    }

    /// 区画のカテゴリのタブを設定画面で開くので、元のアプリには戻さずに閉じる。
    private func editRegion(_ category: SnapCommand.Category) {
        dismiss(restoringPreviousApp: false)
        onEditRegion(category)
    }
}
