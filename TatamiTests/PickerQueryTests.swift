import Testing
@testable import Tatami

struct PickerQueryTests {
    @Test func 空白で分けて小文字にする() {
        #expect(PickerQuery.tokens("Left  1/3") == ["left", "1/3"])
        #expect(PickerQuery.tokens("右　1/3") == ["右", "1/3"])   // 全角空白
        #expect(PickerQuery.tokens("   ") == [])
        #expect(PickerQuery.tokens("") == [])
    }

    @Test func 全部の語がどれかの語彙に前方一致すれば残る() {
        let terms = ["右 1/3", "右", "1/3", "right third", "right", "third", "r3", ">"]
        #expect(PickerQuery.matches(tokens: [], terms: terms))
        #expect(PickerQuery.matches(tokens: ["r"], terms: terms))
        #expect(PickerQuery.matches(tokens: [">", "1/3"], terms: terms))
        #expect(PickerQuery.matches(tokens: ["right", "thi"], terms: terms))
        #expect(!PickerQuery.matches(tokens: ["2/3"], terms: terms))
        #expect(!PickerQuery.matches(tokens: [">", "2/3"], terms: terms))
        #expect(!PickerQuery.matches(tokens: ["ight"], terms: terms))   // 途中からは一致しない
    }

    @Test func セットの語彙は名前とアプリ名() {
        let set = LayoutSet(name: "Agent Coding", rows: [
            LayoutRow(bundleIdentifier: "wez", appName: "WezTerm", action: .leftTwoThirds),
            LayoutRow(bundleIdentifier: "chrome", appName: "Google Chrome", action: .rightThird),
        ])
        let terms = PickerQuery.terms(of: set)
        #expect(terms.contains("agent coding"))
        #expect(terms.contains("coding"))
        #expect(terms.contains("wezterm"))
        #expect(terms.contains("google chrome"))
        #expect(terms.contains("chrome"))
        #expect(terms.allSatisfy { $0 == $0.lowercased() })
    }
}
