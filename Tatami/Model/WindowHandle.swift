import ApplicationServices

/// AXUIElement を値型として扱うためのラッパー。
/// 同一性は CFEqual / CFHash に委譲する（同じウィンドウを指す要素は等しい）。
///
/// `@unchecked Sendable` の根拠: AXUIElement は生成後に中身が変わらない CF の参照トークンで、
/// 保持しているのはその参照だけ。等価性・ハッシュも CFEqual / CFHash で読むだけなので、
/// アクター間で受け渡しても共有可変状態は生じない。
struct WindowHandle: Hashable, @unchecked Sendable {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
