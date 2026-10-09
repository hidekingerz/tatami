// Tatami/System/AccessibilityWindowService.swift
import AppKit
import ApplicationServices

/// AXUIElement を使った WindowService の実装。
struct AccessibilityWindowService: WindowService {
    func focusedWindow() throws -> WindowHandle {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowServiceError.noFrontmostApplication
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else {
            throw WindowServiceError.noFocusedWindow
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw WindowServiceError.invalidValue
        }
        return WindowHandle(element: value as! AXUIElement)
    }

    func frame(of window: WindowHandle) throws -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        try read(kAXPositionAttribute, as: .cgPoint, into: &origin, from: window)
        try read(kAXSizeAttribute, as: .cgSize, into: &size, from: window)
        return CGRect(origin: origin, size: size)
    }

    /// size → position → size の順で適用する。
    /// 先に size を縮めておくことで、画面端での position のクランプを避ける。
    func setFrame(_ frame: CGRect, of window: WindowHandle) throws {
        var size = frame.size
        var origin = frame.origin
        try write(kAXSizeAttribute, as: .cgSize, value: &size, to: window)
        try write(kAXPositionAttribute, as: .cgPoint, value: &origin, to: window)
        try write(kAXSizeAttribute, as: .cgSize, value: &size, to: window)
    }

    private func read<T>(
        _ attribute: String, as type: AXValueType, into out: inout T, from window: WindowHandle
    ) throws {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window.element, attribute as CFString, &value)
        guard result == .success else {
            throw WindowServiceError.axError(result)
        }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID(),
              withUnsafeMutablePointer(to: &out, { AXValueGetValue(value as! AXValue, type, $0) })
        else {
            throw WindowServiceError.invalidValue
        }
    }

    private func write<T>(
        _ attribute: String, as type: AXValueType, value: inout T, to window: WindowHandle
    ) throws {
        guard let axValue = withUnsafePointer(to: &value, { AXValueCreate(type, $0) }) else {
            throw WindowServiceError.invalidValue
        }
        let result = AXUIElementSetAttributeValue(window.element, attribute as CFString, axValue)
        guard result == .success else {
            throw WindowServiceError.axError(result)
        }
    }
}
