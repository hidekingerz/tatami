import Foundation

/// レイアウトセット検索の語の分割と照合。純粋関数のみ。
enum PickerQuery {
    /// 半角・全角の空白で分け、小文字にする。空の語は除く。
    static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// 全ての語が、語彙のどれかに前方一致すれば true。語が空なら true。
    static func matches(tokens: [String], terms: [String]) -> Bool {
        tokens.allSatisfy { token in terms.contains { $0.hasPrefix(token) } }
    }

    /// セットの語彙。名前と各行のアプリ名について、全体と各語を小文字で集める。
    static func terms(of set: LayoutSet) -> [String] {
        var result: Set<String> = []
        for text in [set.name] + set.rows.map(\.appName) {
            let lowered = text.lowercased()
            result.insert(lowered)
            for word in lowered.split(whereSeparator: \.isWhitespace) {
                result.insert(String(word))
            }
        }
        return result.sorted()
    }
}
