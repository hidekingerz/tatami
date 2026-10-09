import Foundation

/// Accessibility 権限の確認と要求。
@MainActor
protocol PermissionChecking: AnyObject {
    /// 今この瞬間に許可されているか。キャッシュしない。
    var isTrusted: Bool { get }
    /// システムのプロンプトを出して許可を求める。
    func requestAccess()
}
