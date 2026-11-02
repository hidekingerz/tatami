// Tatami/App/AppModel.swift
import AppKit
import Observation
import SwiftUI

/// アプリ全体で 1 つだけ持つ依存の束。
///
/// 初期化ではエンジンを組み立てて権限変化の通知を購読するだけにし、
/// 権限要求、ショートカット登録、権限のポーリングといった外部への副作用は `start()` で行う。
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let permission = PermissionGate()
    @ObservationIgnored let engine: SnapEngine
    @ObservationIgnored let settings = CommandSettings()
    /// メニューは store 自身を観測するので、ここでは観測対象にしない。
    @ObservationIgnored let layoutSets = LayoutSetStore()
    @ObservationIgnored let hud = ResultHUD()
    @ObservationIgnored let runner: LayoutSetRunner
    /// 設定画面の「いまの配置を保存」が使う。
    @ObservationIgnored let capture: LayoutCapture
    /// runner に渡したものと同じインスタンス。設定画面の警告が読む。
    @ObservationIgnored let dockPreferences: any DockPreferencesReading
    @ObservationIgnored let missionControl: any MissionControlShortcutReading
    @ObservationIgnored private var poller: TrustPoller?
    /// ピッカー。初めて開くときに作る。
    @ObservationIgnored private var picker: PickerPanel?
    @ObservationIgnored let favorites = FavoriteRegions()
    @ObservationIgnored private let inputSource: any InputSourceSwitching = CarbonInputSourceSwitcher()
    /// `MenuBarView` が表示されたときに預ける設定画面を開くアクション。
    /// ピッカーは `App` のシーン外にあり `@Environment(\.openSettings)` を直接使えないため。
    @ObservationIgnored var openSettingsAction: OpenSettingsAction?

    /// メニュー表示用の権限状態。通知やポーリングのたびに `refreshTrust()` で読み直す。
    /// スナップ時の判定は SnapEngine が毎回 OS に問い合わせるので、この値には依存しない。
    private(set) var isTrusted: Bool

    /// 設定画面で選ばれているタブ。ピッカーの ⌘⏎ が「セット」タブと開くセットを指定する。
    var settingsTab: SettingsTab = .commands(.halves)

    init() {
        // 全プロパティの初期化前は self を捕捉できないので、クロージャにはローカル定数だけを渡す。
        let permission = self.permission
        let hud = self.hud
        let windowService = AccessibilityWindowService()
        let screens = NSScreenProvider()
        let enumerator = AccessibilityWindowEnumerator()
        let dockPreferences = DockPreferences()
        let missionControl = MissionControlShortcuts()
        let engine = SnapEngine(
            windowService: windowService,
            screens: screens,
            permission: permission,
            onFailure: { _ in NSSound.beep() }
        )
        self.engine = engine
        self.dockPreferences = dockPreferences
        self.missionControl = missionControl
        capture = LayoutCapture(enumerator: enumerator, screens: screens)
        runner = LayoutSetRunner(
            enumerator: enumerator,
            windowService: windowService,
            placer: WindowPlacer(windowService: windowService, screens: screens),
            spaceMover: CGEventSpaceMover(
                shortcuts: missionControl, enumerator: enumerator, windowService: windowService
            ),
            dockPreferences: dockPreferences,
            permission: permission,
            onStarted: { set in hud.showPersistent("\(set.name) を適用中…") },
            onFinished: { result in
                // セットが窓を動かしたので、直前のスナップの記憶はもう当てにならない。
                engine.clearMemory()
                hud.show(result.summary)
            }
        )
        isTrusted = permission.isTrusted

        // アクセシビリティ権限が変わると TCC がこの分散通知を投げる。ただし通知が届いた時点では
        // TCC がまだ古い判定を返すことがあるため、未許可の間は start() のポーリングが本命。
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshTrust() }
        }

        // `NSApp.terminate` はウィンドウを閉じないので、ピッカーが開いたままだと `dismiss` が走らず
        // 入力ソースが ABC のまま残る。終了時に閉じて元に戻す。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePicker() }
        }
    }

    /// 権限要求とショートカット登録を行う。テストホストとして起動されたときは何もしない
    /// （`xcodebuild test` のたびに権限プロンプトが出たり、グローバルなホットキーを奪ったりしないように）。
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
        permission.requestAccess()
        ShortcutRegistrar.register(engine: engine, settings: settings, isBusy: { [runner] in runner.isRunning })
        ShortcutRegistrar.registerLayoutSets(
            store: layoutSets,
            isBusy: { [runner] in runner.isRunning },
            onPicker: { [weak self] in self?.openPicker() },
            onApply: { [weak self] in self?.apply($0) }
        )
        watchTrustUntilGranted()
    }

    /// レイアウトセットを適用する。実行中や権限なしで適用できなかったら beep する。
    /// ピッカーが開いていると tatami が前面に残り、合成マウス操作を邪魔するので先に閉じる。
    func apply(_ set: LayoutSet) {
        closePicker()
        let runner = self.runner
        Task {
            if await !runner.apply(set) {
                NSSound.beep()
            }
        }
    }

    /// ピッカーを開く。出ていれば閉じる。
    func openPicker() {
        let picker = self.picker ?? PickerPanel(
            store: layoutSets,
            favorites: favorites,
            settings: settings,
            inputSource: inputSource,
            onApply: { [weak self] set in self?.apply(set) },
            onApplyRegion: { [weak self] action in self?.apply(action) },
            onEdit: { [weak self] set in self?.openSettings(for: set) },
            onEditRegion: { [weak self] category in self?.openSettings(for: category) },
            // 記憶を消すだけにする。パネルの再入ガードは、ここで何も開いたりアクティブにしたりしない前提。
            onDismiss: { [weak self] in self?.engine.forgetRememberedWindow() }
        )
        self.picker = picker
        // これから開くときだけ、動かす対象を記憶する（PickerPanel.show() が tatami をアクティブにする前に）。
        // tatami 自身が前面なら、前面アプリの窓は tatami の窓なので記憶しない。
        if !picker.isVisible {
            if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current {
                engine.forgetRememberedWindow()
            } else {
                engine.rememberFocusedWindow()
            }
        }
        picker.toggle()
    }

    /// ピッカーで選んだ区画を、ピッカーを開く前に前面にあった窓へ当てる。
    /// 記憶は `closePicker()`（dismiss → onDismiss）で消えるので、閉じる前に適用する。
    /// 失敗時の beep は engine の `onFailure` が鳴らすので、ここでは HUD だけ出す。
    func apply(_ action: SnapAction) {
        guard !runner.isRunning else {
            closePicker()
            NSSound.beep()
            return
        }
        let failure = engine.applyToRememberedWindow(action)
        closePicker()
        switch failure {
        case nil: break
        case .noTargetWindow: hud.show("対象のウィンドウがありません")
        case .notTrusted: break
        default: hud.show("ウィンドウを動かせませんでした")
        }
    }

    /// ピッカーを閉じる。開いていなければ何もしない。
    func closePicker() {
        picker?.close()
    }

    /// 設定画面の「セット」タブを開き、set があればそれを展開する。
    private func openSettings(for set: LayoutSet?) {
        settingsTab = .layoutSets(selectedID: set?.id)
        presentSettings()
    }

    /// 設定画面のカテゴリのタブを開く。ピッカーの区画の ⌘⏎ から使う。
    private func openSettings(for category: SnapCommand.Category) {
        settingsTab = .commands(category)
        presentSettings()
    }

    /// 設定画面を前面に出す。
    /// メニューを一度も開いていないと `openSettingsAction` が nil なので、そのときは
    /// 非公開セレクタ `showSettingsWindow:` を送る。
    private func presentSettings() {
        NSApp.activate()
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        // 経路 B が効かなかったときに、窓のないまま tatami がアクティブに残り、
        // 押したキーがすべて beep し続けないように、少し待って窓がなければアクティブをやめる。
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if NSApp.keyWindow == nil && NSApp.isActive { NSApp.deactivate() }
        }
    }

    /// 許可されるまで 1 秒おきに権限を読み直す。許可を検知したらメニュー表示を更新して止まる。
    private func watchTrustUntilGranted() {
        let poller = TrustPoller(permission: permission) { [weak self] in
            self?.poller = nil
            self?.refreshTrust()
        }
        self.poller = poller
        poller.start()
    }

    /// 権限状態を OS から読み直す。取り消されていたら、再び許可されるまでのポーリングを始める。
    func refreshTrust() {
        let trusted = permission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
        if !trusted, poller == nil {
            watchTrustUntilGranted()
        }
    }
}
