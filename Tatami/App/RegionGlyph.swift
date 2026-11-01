// Tatami/App/RegionGlyph.swift
import AppKit
import SwiftUI

/// 画面の中のどこに置かれるかを示す小さな図。
/// 形は LayoutCalculator から得るので、計算と表示が必ず一致する。
struct RegionGlyph: View {
    /// 1 枚の画面に重ねて描く区画。描く順に並べる。
    let actions: [SnapAction]
    var isEnabled = true
    /// 図の大きさ。既定はメニューや設定のアイコン用。
    private var size = CGSize(width: 24, height: 15)
    /// 塗りつぶした選択行の上に置くときは、アクセント色ではなく白で描く。
    private var isHighlighted = false

    init(action: SnapAction, isEnabled: Bool = true) {
        self.init(actions: [action], isEnabled: isEnabled)
    }

    init(actions: [SnapAction], isEnabled: Bool = true) {
        self.actions = actions
        self.isEnabled = isEnabled
    }

    /// 大きさを変えた図を返す。
    func size(width: CGFloat, height: CGFloat) -> RegionGlyph {
        var copy = self
        copy.size = CGSize(width: width, height: height)
        return copy
    }

    /// 選択行（アクセント色の塗り）の上に置くための白い図を返す。
    func highlighted(_ isHighlighted: Bool) -> RegionGlyph {
        var copy = self
        copy.isHighlighted = isHighlighted
        return copy
    }

    /// 形を求めるときの基準画面。LayoutCalculator は幅を floor するので、2・3・4 で割り切れる大きさにする。
    nonisolated static let referenceScreen = CGRect(x: 0, y: 0, width: 1200, height: 600)
    /// サイズ系コマンド用の代表的な現在枠（中央に置いた 0.5 × 0.6）。
    nonisolated static let sampleWindow = CGRect(x: 300, y: 120, width: 600, height: 360)

    /// 0...1 に正規化した区画。NS 座標（左下原点）。
    /// 純粋な計算なので、メインアクター外（テストの関数参照など）からも呼べるようにする。
    nonisolated static func normalizedRegion(for action: SnapAction) -> CGRect {
        let frame = LayoutCalculator.frame(for: action, in: referenceScreen, current: sampleWindow)
        return CGRect(
            x: frame.minX / referenceScreen.width,
            y: frame.minY / referenceScreen.height,
            width: frame.width / referenceScreen.width,
            height: frame.height / referenceScreen.height
        )
    }

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(Path(roundedRect: screen, cornerRadius: 2), with: .color(strokeColor), lineWidth: 1)

            // 重なる区画も見分けられるよう、複数のときは半透明で重ねる。
            let opacity = actions.count > 1 ? 0.7 : 1
            for action in actions {
                let region = Self.normalizedRegion(for: action)
                // NS 座標は下が原点なので、描画時に上下を反転する。
                let rect = CGRect(
                    x: screen.minX + region.minX * screen.width,
                    y: screen.minY + (1 - region.maxY) * screen.height,
                    width: region.width * screen.width,
                    height: region.height * screen.height
                ).insetBy(dx: 1, dy: 1)
                context.fill(Path(rect), with: .color(fillColor.opacity(opacity)))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        if isHighlighted { return .white }
        return isEnabled ? .accentColor : Color(nsColor: .tertiaryLabelColor)
    }

    private var strokeColor: Color {
        if isHighlighted { return .white.opacity(0.8) }
        return isEnabled ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .tertiaryLabelColor)
    }
}

extension RegionGlyph {
    @MainActor private static var tabImages: [SnapCommand.Category: NSImage] = [:]

    /// タブのアイコン。カテゴリの先頭コマンドの区画をテンプレート画像にして、システムが色を付ける。
    @MainActor
    static func tabImage(for category: SnapCommand.Category) -> NSImage {
        if let cached = tabImages[category] {
            return cached
        }
        let action = category.commands[0].sequence[0]
        let renderer = ImageRenderer(content: RegionGlyph(action: action))
        // ディスプレイ間の移動で解像度が変わっても十分な固定 2 倍。
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 24, height: 15))
        image.isTemplate = true
        tabImages[category] = image
        return image
    }
}
