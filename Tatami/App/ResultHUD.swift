// Tatami/App/ResultHUD.swift
import AppKit
import SwiftUI

/// レイアウトセットの適用結果を画面の中央下に短く出す HUD。
///
/// 前面のアプリを奪わないよう、非アクティブ化パネルで出す。`.canJoinAllSpaces` なので、表示中にデスクトップを
/// 切り替えてもどの空間（フルスクリーン空間を含む）でも見えたままになる。`.transient` は Mission Control / Exposé に
/// 関するもので、そこでは HUD を窓として扱わない。
@MainActor
final class ResultHUD {
    /// 1 行に収める幅の上限。これを超える文は折り返す。
    private static let maxTextWidth: CGFloat = 520
    /// 画面の下端（Dock を除いた可視領域）から HUD の下端までの距離。
    private static let bottomMargin: CGFloat = 120

    private let panel: NSPanel
    /// 中身の SwiftUI。折り返し後の大きさを測るために、ビューではなくコントローラで持つ。
    private let hosting: NSHostingController<HUDContent>
    /// 表示中の消去タイマー。次の表示の前に必ず cancel する。
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        hosting = NSHostingController(rootView: HUDContent(text: "", onTap: {}))
        hosting.sizingOptions = []
        panel.contentView = hosting.view
    }

    /// 中央下に text を出し、duration 後に消す。duration が nil なら文字数で決める。
    /// 前の表示が残っていればその消去タイマーを cancel してから出す。クリックで即閉じる。
    func show(_ text: String, duration: Duration? = nil) {
        present(text, ignoresMouse: false)
        let duration = duration ?? Self.duration(for: text)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// 消えないまま出す（「適用中…」用）。次の show で置き換わる。
    /// 適用中は合成マウス操作の掴む点に HUD が重なっても困らないよう、マウスを素通しする。
    func showPersistent(_ text: String) {
        present(text, ignoresMouse: true)
    }

    /// 40 字まで 2 秒、以後 20 字ごとに 0.5 秒足し、上限 4 秒。
    static func duration(for text: String) -> Duration {
        let extraSteps = max(0, (text.count - 40 + 19) / 20)
        return .milliseconds(min(2000 + 500 * extraSteps, 4000))
    }

    private func present(_ text: String, ignoresMouse: Bool) {
        hideTask?.cancel()
        hideTask = nil

        hosting.rootView = HUDContent(text: text) { [weak self] in self?.hide() }
        panel.ignoresMouseEvents = ignoresMouse

        let size = hosting.sizeThatFits(
            in: CGSize(width: Self.maxTextWidth + HUDContent.horizontalPadding * 2, height: .greatestFiniteMagnitude)
        )
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + Self.bottomMargin)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel.orderOut(nil)
    }
}

/// HUD の中身。角丸の素材の上に文言を置き、タップで閉じる。
private struct HUDContent: View {
    static let horizontalPadding: CGFloat = 16

    let text: String
    let onTap: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onTap)
    }
}
