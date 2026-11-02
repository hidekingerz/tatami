import Foundation

extension SnapAction {
    /// ピッカーの検索語彙（すべて小文字、重複なし）。
    /// 日本語名・英語名は全体と空白で分けた各語の両方を含む。
    var searchTerms: [String] {
        let alias = aliases
        let phrases = [title, alias.english]
        let words = phrases.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        var seen = Set<String>()
        return (phrases + words + alias.abbreviations + alias.romaji + alias.symbols)
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
    }

    /// 別名表（仕様 §2.3）。`last` のような語は入れない。
    private var aliases: (english: String, abbreviations: [String], romaji: [String], symbols: [String]) {
        switch self {
        case .leftHalf: ("left half", ["lh", "l"], ["hidari", "hanbun"], ["<"])
        case .rightHalf: ("right half", ["rh", "r"], ["migi", "hanbun"], [">"])
        case .topHalf: ("top half", ["th", "t", "up"], ["ue", "hanbun"], ["^"])
        case .bottomHalf: ("bottom half", ["bh", "b", "down"], ["shita", "hanbun"], ["v"])
        case .maximize: ("maximize", ["max", "m", "full"], ["saidai"], [])
        case .leftThird: ("left third", ["l3", "l13"], ["hidari"], ["<", "1/3"])
        case .centerThird: ("center third", ["c3", "c13"], ["chuo", "mannaka"], ["1/3"])
        case .rightThird: ("right third", ["r3", "r13"], ["migi"], [">", "1/3"])
        case .leftTwoThirds: ("left two thirds", ["l23"], ["hidari"], ["<", "2/3"])
        case .rightTwoThirds: ("right two thirds", ["r23"], ["migi"], [">", "2/3"])
        case .firstFourth: ("left quarter", ["l4", "q1"], ["hidari"], ["<", "1/4"])
        case .secondFourth: ("second quarter", ["q2"], [], ["1/4", "2"])
        case .thirdFourth: ("third quarter", ["q3"], [], ["1/4", "3"])
        case .lastFourth: ("right quarter", ["r4", "q4"], ["migi"], [">", "1/4"])
        case .topLeftQuarter: ("top left", ["tl"], ["hidariue"], ["<^", "^<"])
        case .topRightQuarter: ("top right", ["tr"], ["migiue"], [">^", "^>"])
        case .bottomLeftQuarter: ("bottom left", ["bl"], ["hidarishita"], ["<v", "v<"])
        case .bottomRightQuarter: ("bottom right", ["br"], ["migishita"], [">v", "v>"])
        case .topLeftSixth: ("top left sixth", ["tl6"], ["hidariue"], ["<^", "^<", "1/6"])
        case .topCenterSixth: ("top center sixth", ["tc6"], ["chuo", "ue"], ["^", "1/6"])
        case .topRightSixth: ("top right sixth", ["tr6"], ["migiue"], [">^", "^>", "1/6"])
        case .bottomLeftSixth: ("bottom left sixth", ["bl6"], ["hidarishita"], ["<v", "v<", "1/6"])
        case .bottomCenterSixth: ("bottom center sixth", ["bc6"], ["chuo", "shita"], ["v", "1/6"])
        case .bottomRightSixth: ("bottom right sixth", ["br6"], ["migishita"], [">v", "v>", "1/6"])
        case .maximizeHeight: ("max height", ["h"], ["takasa"], [])
        case .maximizeWidth: ("max width", ["w"], ["haba"], [])
        case .center: ("center", ["c"], ["chuo", "mannaka"], [])
        }
    }
}
