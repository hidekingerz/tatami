import ApplicationServices
import CoreGraphics
import Testing
@testable import Tatami

struct CycleResolverTests {
    /// テスト用のウィンドウ識別子。pid が違えば別のウィンドウとして扱われる。
    func window(_ pid: pid_t) -> WindowHandle {
        WindowHandle(element: AXUIElementCreateApplication(pid))
    }

    let frame = CGRect(x: 0, y: 0, width: 500, height: 700)

    @Test func 記憶がなければ系列の先頭() {
        let action = CycleResolver.resolve(command: .cycleLeft, memory: nil,
                                           window: window(1), currentFrame: frame)
        #expect(action == .leftHalf)
    }

    @Test func 同じウィンドウで枠が一致すれば次へ進む() {
        let memory = CycleMemory(window: window(1), action: .leftHalf, appliedFrame: frame)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: frame)
        #expect(action == .leftThird)
    }

    @Test func 系列の末尾からは先頭へ戻る() {
        let memory = CycleMemory(window: window(1), action: .leftTwoThirds, appliedFrame: frame)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: frame)
        #expect(action == .leftHalf)
    }

    @Test func 別のウィンドウなら先頭から() {
        let memory = CycleMemory(window: window(1), action: .leftThird, appliedFrame: frame)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(2), currentFrame: frame)
        #expect(action == .leftHalf)
    }

    @Test func 手で動かして枠が変わっていれば先頭から() {
        let memory = CycleMemory(window: window(1), action: .leftThird, appliedFrame: frame)
        let moved = frame.offsetBy(dx: 40, dy: 0)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: moved)
        #expect(action == .leftHalf)
    }

    @Test func 許容誤差2pt以内なら一致とみなす() {
        let memory = CycleMemory(window: window(1), action: .leftHalf, appliedFrame: frame)
        let slightlyOff = CGRect(x: 2, y: -2, width: 498, height: 702)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: slightlyOff)
        #expect(action == .leftThird)
    }

    @Test func 許容誤差を超えたら先頭から() {
        let memory = CycleMemory(window: window(1), action: .leftHalf, appliedFrame: frame)
        let tooFar = CGRect(x: 3, y: 0, width: 500, height: 700)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: tooFar)
        #expect(action == .leftHalf)
    }

    @Test func 別の系列の記憶があっても先頭から() {
        // 左ループ中に右ループを押した。
        let memory = CycleMemory(window: window(1), action: .leftThird, appliedFrame: frame)
        let action = CycleResolver.resolve(command: .cycleRight, memory: memory,
                                           window: window(1), currentFrame: frame)
        #expect(action == .rightHalf)
    }

    @Test func 単発コマンド後にループを押すと先頭から() {
        let memory = CycleMemory(window: window(1), action: .maximize, appliedFrame: frame)
        let action = CycleResolver.resolve(command: .cycleLeft, memory: memory,
                                           window: window(1), currentFrame: frame)
        #expect(action == .leftHalf)
    }

    @Test(arguments: [SnapCommand.topHalf, .bottomHalf, .maximize, .centerThird])
    func 単発コマンドは記憶に関係なく固定(command: SnapCommand) {
        let memory = CycleMemory(window: window(1), action: command.sequence[0], appliedFrame: frame)
        let action = CycleResolver.resolve(command: command, memory: memory,
                                           window: window(1), currentFrame: frame)
        #expect(action == command.sequence[0])
    }
}
