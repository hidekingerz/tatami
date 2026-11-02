import Testing
@testable import Tatami

struct InputSourcePolicyTests {
    let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", isASCIICapable: true, isSelectable: true, isKeyboardLayout: true)
    let us = InputSourceInfo(id: "com.apple.keylayout.US", isASCIICapable: true, isSelectable: true, isKeyboardLayout: true)
    let japanese = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", isASCIICapable: false, isSelectable: true, isKeyboardLayout: false)
    let romaji = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", isASCIICapable: true, isSelectable: true, isKeyboardLayout: false)
    let emoji = InputSourceInfo(id: "com.apple.CharacterPaletteIM", isASCIICapable: true, isSelectable: false, isKeyboardLayout: false)

    @Test func いまがASCII可能なら切り替えない() {
        #expect(InputSourcePolicy.target(current: abc, candidates: [abc, japanese]) == nil)
        #expect(InputSourcePolicy.target(current: us, candidates: [abc, us]) == nil)
    }

    @Test func ABCがあればABC() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, us, abc]) == abc)
    }

    @Test func ABCがなければ最初のASCII可能なキーボードレイアウト() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, romaji, us]) == us)
    }

    @Test func 選択不可や入力メソッドは選ばない() {
        #expect(InputSourcePolicy.target(current: japanese, candidates: [japanese, emoji, romaji]) == nil)
    }
}
