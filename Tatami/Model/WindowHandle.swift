import ApplicationServices

/// AXUIElement を値型として扱うためのラッパー。
/// 同一性は CFEqual / CFHash に委譲する（同じウィンドウを指す要素は等しい）。
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
