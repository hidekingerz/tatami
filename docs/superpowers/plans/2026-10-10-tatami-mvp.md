# tatami MVP 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ⌃⌥ + b/f/p/n/m/c で最前面ウィンドウを 10 区画へスナップするメニューバー常駐 macOS アプリを、単体テスト付きで動く状態にする。

**Architecture:** SwiftUI App（MenuBarExtra + Settings）が `SnapEngine` にコマンドを渡し、エンジンは純粋ロジック（`CycleResolver` / `LayoutCalculator` / `CoordinateConverter` / `ScreenLocator`）で目標枠を計算して `WindowService` protocol 経由で適用する。AX API・NSScreen・権限確認はすべて protocol の裏に隠し、テストでは Fake に差し替える。

**Tech Stack:** Swift 6 言語モード、SwiftUI、ApplicationServices (AXUIElement)、sindresorhus/KeyboardShortcuts（SwiftPM）、Swift Testing、Xcode 26 / xcodebuild。

**Spec:** `docs/superpowers/specs/2026-10-10-tatami-mvp-design.md`

## Global Constraints

- 最低 macOS 26（`MACOSX_DEPLOYMENT_TARGET = 26.0`）。Swift 6 言語モード（`SWIFT_VERSION = 6.0`、strict concurrency）。
- Bundle ID は `dev.hidekingerz.tatami`。テストは `dev.hidekingerz.tatamiTests`。
- Dock 非表示（`LSUIElement = YES`）。App Sandbox OFF。Hardened Runtime ON。
- 修飾キーは ⌃⌥。デフォルトは b=cycleLeft, f=cycleRight, p=topHalf, n=bottomHalf, m=maximize, c=centerThird。
- ループ順は 半分 → 1/3 → 2/3 → 半分。ループ判定の許容誤差は各辺 2pt。
- 座標は `WindowService` の境界で AX 座標（左上原点）、`LayoutCalculator` と `ScreenLocator` は NS 座標（左下原点）。プライマリ画面は `NSScreen.screens[0]`。
- 1/3・半分の端数は右端・上端の区画に寄せ、区画間に隙間と重なりを作らない。
- 失敗時のユーザー向け表示は `NSSound.beep()` のみ。ログは `os.Logger`、サブシステム `dev.hidekingerz.tatami`。
- ビルドとテストは `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS'` で通ること。
- ソースと設計書のコメントは日本語。識別子は英語。
- 各 Task の最後にコミットする。コミットメッセージ末尾に `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` を付ける。

## Review Focus

1. **最小サイズ制約のあるウィンドウ**: 1/3 幅まで縮まらないウィンドウでも、次に同じキーを押せば 2/3 へ進むこと（Task 7 `SnapEngineTests` の「実枠が目標と違ってもループが進む」で検証）。
2. **visibleFrame の原点がゼロでない画面**: Dock を左に置いた画面や、プライマリの左側にある画面（負の x）でも区画が visibleFrame の内側に収まること（Task 3 `LayoutCalculatorTests` の原点オフセット付きケース、Task 4 `CoordinateConverterTests` の負座標ケースで検証）。
3. **ウィンドウ中心が 2 画面の境界線上**: どちらか一方の画面に決定的に決まり、クラッシュや nil にならないこと（Task 6 `ScreenLocatorTests` の境界ケースで検証）。
4. **権限がセッション途中で取り消された**: 起動時に許可されていても、押下時に未許可なら `setFrame` を呼ばず、再要求だけ行うこと（Task 7 `SnapEngineTests` の権限未許可ケースで検証）。
5. **適用後の枠の読み直しに失敗**: `setFrame` 成功後に `frame(of:)` が throw した場合、記憶を壊さず失敗フックを呼ぶこと（Task 7 `SnapEngineTests` の読み直し失敗ケースで検証）。

---

## ファイル構成

```
Tatami.xcodeproj/
  project.pbxproj                                   Task 1
  xcshareddata/xcschemes/Tatami.xcscheme            Task 1
  project.xcworkspace/xcshareddata/swiftpm/Package.resolved  Task 1（xcodebuild が生成）
Tatami/
  App/TatamiApp.swift                               Task 1（骨組み）, Task 9（配線）
  App/AppModel.swift                                Task 9
  App/MenuBarView.swift                             Task 9
  App/SettingsView.swift                            Task 9
  App/ShortcutRegistrar.swift                       Task 9
  Model/SnapAction.swift                            Task 2
  Model/SnapCommand.swift                           Task 2
  Model/WindowHandle.swift                          Task 2
  Model/CycleMemory.swift                           Task 2
  Engine/LayoutCalculator.swift                     Task 3
  Engine/CoordinateConverter.swift                  Task 4
  Engine/CycleResolver.swift                        Task 5
  Engine/ScreenLocator.swift                        Task 6
  Engine/SnapEngine.swift                           Task 7
  System/WindowService.swift                        Task 7（protocol とエラー）
  System/PermissionChecking.swift                   Task 7（protocol）
  System/ScreenProviding.swift                      Task 7（protocol）
  System/AccessibilityWindowService.swift           Task 8
  System/PermissionGate.swift                       Task 8
  System/NSScreenProvider.swift                     Task 8
  Resources/Assets.xcassets/                        Task 1
TatamiTests/
  SnapCommandTests.swift                            Task 2
  LayoutCalculatorTests.swift                       Task 3
  CoordinateConverterTests.swift                    Task 4
  CycleResolverTests.swift                          Task 5
  ScreenLocatorTests.swift                          Task 6
  SnapEngineTests.swift                             Task 7
  Fakes/FakeWindowService.swift                     Task 7
  Fakes/FakePermission.swift                        Task 7
  Fakes/FakeScreenProvider.swift                    Task 7
```

Xcode 16 以降の `PBXFileSystemSynchronizedRootGroup` を使うので、`Tatami/` と `TatamiTests/` 配下に置いたファイルは pbxproj を編集せずにターゲットへ入る。Info.plist は `GENERATE_INFOPLIST_FILE = YES` と `INFOPLIST_KEY_LSUIElement = YES` で生成する（設計書の「Resources/Info.plist」はこの方式で代替する。生成される plist に `LSUIElement` が入ることを Task 1 で確認する）。

---

### Task 1: Xcode プロジェクトの骨組み

**Files:**
- Create: `Tatami.xcodeproj/project.pbxproj`
- Create: `Tatami.xcodeproj/xcshareddata/xcschemes/Tatami.xcscheme`
- Create: `Tatami/App/TatamiApp.swift`
- Create: `Tatami/Resources/Assets.xcassets/Contents.json`
- Create: `Tatami/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `TatamiTests/SmokeTests.swift`（Task 2 で削除）

**Interfaces:**
- Consumes: なし
- Produces: `Tatami` アプリターゲット（モジュール名 `Tatami`）、`TatamiTests` テストターゲット、KeyboardShortcuts パッケージ依存。

- [ ] **Step 1: pbxproj を書く**

```bash
mkdir -p Tatami.xcodeproj/xcshareddata/xcschemes Tatami/App Tatami/Resources/Assets.xcassets/AppIcon.appiconset TatamiTests
cat > Tatami.xcodeproj/project.pbxproj <<'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		AA0000000000000000000042 /* KeyboardShortcuts in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000041 /* KeyboardShortcuts */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		AA0000000000000000000030 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = AA0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = AA0000000000000000000010;
			remoteInfo = Tatami;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		AA0000000000000000000006 /* Tatami.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Tatami.app; sourceTree = BUILT_PRODUCTS_DIR; };
		AA0000000000000000000007 /* TatamiTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TatamiTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000004 /* Tatami */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Tatami;
			sourceTree = "<group>";
		};
		AA0000000000000000000005 /* TatamiTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = TatamiTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		AA0000000000000000000013 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000042 /* KeyboardShortcuts in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000016 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AA0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000004 /* Tatami */,
				AA0000000000000000000005 /* TatamiTests */,
				AA0000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		AA0000000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000006 /* Tatami.app */,
				AA0000000000000000000007 /* TatamiTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AA0000000000000000000010 /* Tatami */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000023 /* Build configuration list for PBXNativeTarget "Tatami" */;
			buildPhases = (
				AA0000000000000000000012 /* Sources */,
				AA0000000000000000000013 /* Frameworks */,
				AA0000000000000000000014 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000004 /* Tatami */,
			);
			name = Tatami;
			packageProductDependencies = (
				AA0000000000000000000041 /* KeyboardShortcuts */,
			);
			productName = Tatami;
			productReference = AA0000000000000000000006 /* Tatami.app */;
			productType = "com.apple.product-type.application";
		};
		AA0000000000000000000011 /* TatamiTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000026 /* Build configuration list for PBXNativeTarget "TatamiTests" */;
			buildPhases = (
				AA0000000000000000000015 /* Sources */,
				AA0000000000000000000016 /* Frameworks */,
				AA0000000000000000000017 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				AA0000000000000000000031 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000005 /* TatamiTests */,
			);
			name = TatamiTests;
			packageProductDependencies = (
			);
			productName = TatamiTests;
			productReference = AA0000000000000000000007 /* TatamiTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AA0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {
					AA0000000000000000000010 = {
						CreatedOnToolsVersion = 26.0;
					};
					AA0000000000000000000011 = {
						CreatedOnToolsVersion = 26.0;
						TestTargetID = AA0000000000000000000010;
					};
				};
			};
			buildConfigurationList = AA0000000000000000000020 /* Build configuration list for PBXProject "Tatami" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = AA0000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				AA0000000000000000000040 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = AA0000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AA0000000000000000000010 /* Tatami */,
				AA0000000000000000000011 /* TatamiTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		AA0000000000000000000014 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000017 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		AA0000000000000000000012 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		AA0000000000000000000015 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		AA0000000000000000000031 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = AA0000000000000000000010 /* Tatami */;
			targetProxy = AA0000000000000000000030 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		AA0000000000000000000021 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MACOSX_DEPLOYMENT_TARGET = 26.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		AA0000000000000000000022 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				MACOSX_DEPLOYMENT_TARGET = 26.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
		AA0000000000000000000024 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.hidekingerz.tatami;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Debug;
		};
		AA0000000000000000000025 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.hidekingerz.tatami;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Release;
		};
		AA0000000000000000000027 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.hidekingerz.tatamiTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tatami.app/Contents/MacOS/Tatami";
			};
			name = Debug;
		};
		AA0000000000000000000028 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.hidekingerz.tatamiTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Tatami.app/Contents/MacOS/Tatami";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AA0000000000000000000020 /* Build configuration list for PBXProject "Tatami" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000021 /* Debug */,
				AA0000000000000000000022 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000023 /* Build configuration list for PBXNativeTarget "Tatami" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000024 /* Debug */,
				AA0000000000000000000025 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000026 /* Build configuration list for PBXNativeTarget "TatamiTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000027 /* Debug */,
				AA0000000000000000000028 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
		AA0000000000000000000040 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sindresorhus/KeyboardShortcuts";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.0.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		AA0000000000000000000041 /* KeyboardShortcuts */ = {
			isa = XCSwiftPackageProductDependency;
			package = AA0000000000000000000040 /* XCRemoteSwiftPackageReference "KeyboardShortcuts" */;
			productName = KeyboardShortcuts;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = AA0000000000000000000001 /* Project object */;
}
EOF
```

- [ ] **Step 2: 共有スキームを書く**

```bash
cat > Tatami.xcodeproj/xcshareddata/xcschemes/Tatami.xcscheme <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "AA0000000000000000000010"
               BuildableName = "Tatami.app"
               BlueprintName = "Tatami"
               ReferencedContainer = "container:Tatami.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "AA0000000000000000000011"
               BuildableName = "TatamiTests.xctest"
               BlueprintName = "TatamiTests"
               ReferencedContainer = "container:Tatami.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistenceIssues = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AA0000000000000000000010"
            BuildableName = "Tatami.app"
            BlueprintName = "Tatami"
            ReferencedContainer = "container:Tatami.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AA0000000000000000000010"
            BuildableName = "Tatami.app"
            BlueprintName = "Tatami"
            ReferencedContainer = "container:Tatami.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
EOF
```

- [ ] **Step 3: Asset Catalog と最小の App を書く**

```bash
cat > Tatami/Resources/Assets.xcassets/Contents.json <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
cat > Tatami/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json <<'EOF'
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
```

```swift
// Tatami/App/TatamiApp.swift
import SwiftUI

/// アプリのエントリポイント。Task 9 でメニューと設定画面を配線する。
@main
struct TatamiApp: App {
    var body: some Scene {
        MenuBarExtra("tatami", systemImage: "rectangle.split.2x1") {
            Button("tatami を終了") {
                NSApp.terminate(nil)
            }
        }
    }
}
```

```swift
// TatamiTests/SmokeTests.swift
import Testing
@testable import Tatami

/// プロジェクトの配線確認用。Task 2 で削除する。
@Test func smoke() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 4: ビルドが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`。初回は KeyboardShortcuts の解決でネットワークアクセスが入る。

失敗したら、エラー行を `grep -E "error:|warning: .*Info.plist"` で抽出して pbxproj の該当設定を直す。よくある原因: `objectVersion = 77` を認識しない古い xcodebuild（Xcode 26 なら問題なし）、スキームが見つからない（`xcshareddata` のパス誤り）。

- [ ] **Step 5: 生成された Info.plist に LSUIElement が入っていることを確認する**

Run:
```bash
APP=$(xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Tatami.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Tatami.app/Contents/Info.plist"
```
Expected: `true` と `dev.hidekingerz.tatami`。

- [ ] **Step 6: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "Test (Suite|Case)|passed|failed|TEST" | tail -8`
Expected: `smoke` が passed、最後に `** TEST SUCCEEDED **`。

- [ ] **Step 7: Package.resolved を含めてコミットする**

```bash
git add Tatami.xcodeproj Tatami TatamiTests
git status --short   # Package.resolved が Tatami.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/ にあることを確認
git commit -m "chore: scaffold Xcode project with KeyboardShortcuts dependency

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: モデル型

**Files:**
- Create: `Tatami/Model/SnapAction.swift`
- Create: `Tatami/Model/SnapCommand.swift`
- Create: `Tatami/Model/WindowHandle.swift`
- Create: `Tatami/Model/CycleMemory.swift`
- Create: `TatamiTests/SnapCommandTests.swift`
- Delete: `TatamiTests/SmokeTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `enum SnapAction: CaseIterable, Sendable` — 10 ケース。
  - `enum SnapCommand: CaseIterable, Sendable` — 6 ケース。`var sequence: [SnapAction]`。
  - `struct WindowHandle: Hashable, Sendable` — `init(element: AXUIElement)`、`let element: AXUIElement`。
  - `struct CycleMemory: Equatable, Sendable` — `window: WindowHandle`, `action: SnapAction`, `appliedFrame: CGRect`。

- [ ] **Step 1: 失敗するテストを書く**

```swift
// TatamiTests/SnapCommandTests.swift
import Testing
@testable import Tatami

struct SnapCommandTests {
    @Test func 区画は10種類ある() {
        #expect(SnapAction.allCases.count == 10)
    }

    @Test func コマンドは6種類ある() {
        #expect(SnapCommand.allCases.count == 6)
    }

    @Test func 左ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleLeft.sequence == [.leftHalf, .leftThird, .leftTwoThirds])
    }

    @Test func 右ループの系列は半分_1_3_2_3の順() {
        #expect(SnapCommand.cycleRight.sequence == [.rightHalf, .rightThird, .rightTwoThirds])
    }

    @Test(arguments: [
        (SnapCommand.topHalf, SnapAction.topHalf),
        (SnapCommand.bottomHalf, SnapAction.bottomHalf),
        (SnapCommand.maximize, SnapAction.maximize),
        (SnapCommand.centerThird, SnapAction.centerThird),
    ])
    func 単発コマンドの系列は1要素(command: SnapCommand, action: SnapAction) {
        #expect(command.sequence == [action])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `rm TatamiTests/SmokeTests.swift && xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -5`
Expected: `cannot find 'SnapAction' in scope` などのコンパイルエラー。

- [ ] **Step 3: モデルを実装する**

```swift
// Tatami/Model/SnapAction.swift
import Foundation

/// ウィンドウを配置する区画。
enum SnapAction: CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
}
```

```swift
// Tatami/Model/SnapCommand.swift
import Foundation

/// ショートカット 1 つに対応するコマンド。
/// ループ系は複数の区画を順に巡り、単発系は 1 つの区画に固定される。
enum SnapCommand: CaseIterable, Sendable {
    case cycleLeft
    case cycleRight
    case topHalf
    case bottomHalf
    case maximize
    case centerThird

    /// このコマンドが巡る区画の系列。単発系は 1 要素。
    var sequence: [SnapAction] {
        switch self {
        case .cycleLeft: [.leftHalf, .leftThird, .leftTwoThirds]
        case .cycleRight: [.rightHalf, .rightThird, .rightTwoThirds]
        case .topHalf: [.topHalf]
        case .bottomHalf: [.bottomHalf]
        case .maximize: [.maximize]
        case .centerThird: [.centerThird]
        }
    }
}
```

```swift
// Tatami/Model/WindowHandle.swift
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
```

```swift
// Tatami/Model/CycleMemory.swift
import CoreGraphics

/// 直前のスナップの記憶。ループ判定に使う。
struct CycleMemory: Equatable, Sendable {
    /// 操作したウィンドウ。
    let window: WindowHandle
    /// 適用した区画。
    let action: SnapAction
    /// 適用後に読み直した実枠（AX 座標）。
    let appliedFrame: CGRect
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/Model TatamiTests
git commit -m "feat: add SnapAction, SnapCommand, WindowHandle, CycleMemory

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: LayoutCalculator

**Files:**
- Create: `Tatami/Engine/LayoutCalculator.swift`
- Create: `TatamiTests/LayoutCalculatorTests.swift`

**Interfaces:**
- Consumes: `SnapAction`
- Produces: `enum LayoutCalculator { static func frame(for action: SnapAction, in visibleFrame: CGRect) -> CGRect }`（入出力とも NS 座標、左下原点）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// TatamiTests/LayoutCalculatorTests.swift
import CoreGraphics
import Testing
@testable import Tatami

struct LayoutCalculatorTests {
    /// 幅 1000・高さ 700 は 3 でも 2 でも割り切れない。
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    /// Dock を左に置き、プライマリの左側にある画面を想定した原点オフセット。
    let offsetScreen = CGRect(x: -1440, y: 25, width: 1440, height: 875)

    @Test func 最大化はvisibleFrameそのもの() {
        #expect(LayoutCalculator.frame(for: .maximize, in: screen) == screen)
    }

    @Test func 左半分と右半分は隙間なく幅を埋める() {
        let left = LayoutCalculator.frame(for: .leftHalf, in: screen)
        let right = LayoutCalculator.frame(for: .rightHalf, in: screen)
        #expect(left == CGRect(x: 0, y: 0, width: 500, height: 700))
        #expect(right == CGRect(x: 500, y: 0, width: 500, height: 700))
    }

    @Test func 奇数幅の半分は右に端数を寄せる() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 700)
        let left = LayoutCalculator.frame(for: .leftHalf, in: odd)
        let right = LayoutCalculator.frame(for: .rightHalf, in: odd)
        #expect(left.width == 500)
        #expect(right.minX == 500)
        #expect(right.width == 501)
    }

    @Test func 上半分と下半分は隙間なく高さを埋める_上に端数を寄せる() {
        let top = LayoutCalculator.frame(for: .topHalf, in: screen)
        let bottom = LayoutCalculator.frame(for: .bottomHalf, in: screen)
        // NS 座標は下が原点。700 / 2 = 350 で割り切れるが、原点オフセット付きで端数も検証する。
        #expect(bottom == CGRect(x: 0, y: 0, width: 1000, height: 350))
        #expect(top == CGRect(x: 0, y: 350, width: 1000, height: 350))

        let oddTop = LayoutCalculator.frame(for: .topHalf, in: offsetScreen)
        let oddBottom = LayoutCalculator.frame(for: .bottomHalf, in: offsetScreen)
        #expect(oddBottom == CGRect(x: -1440, y: 25, width: 1440, height: 437))
        #expect(oddTop == CGRect(x: -1440, y: 462, width: 1440, height: 438))
    }

    @Test func 三分割は隙間なく幅を埋める_右に端数を寄せる() {
        let left = LayoutCalculator.frame(for: .leftThird, in: screen)
        let center = LayoutCalculator.frame(for: .centerThird, in: screen)
        let right = LayoutCalculator.frame(for: .rightThird, in: screen)
        #expect(left == CGRect(x: 0, y: 0, width: 333, height: 700))
        #expect(center == CGRect(x: 333, y: 0, width: 333, height: 700))
        #expect(right == CGRect(x: 666, y: 0, width: 334, height: 700))
    }

    @Test func 三分の二は三分の一と組み合わせて幅を埋める() {
        let leftTwo = LayoutCalculator.frame(for: .leftTwoThirds, in: screen)
        let rightTwo = LayoutCalculator.frame(for: .rightTwoThirds, in: screen)
        #expect(leftTwo == CGRect(x: 0, y: 0, width: 666, height: 700))
        #expect(rightTwo == CGRect(x: 333, y: 0, width: 667, height: 700))
    }

    @Test(arguments: SnapAction.allCases)
    func 全区画が原点オフセット付きvisibleFrameの内側に収まる(action: SnapAction) {
        let frame = LayoutCalculator.frame(for: action, in: offsetScreen)
        #expect(offsetScreen.contains(frame), "\(action) が画面外にはみ出している: \(frame)")
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test func 原点オフセット付きでも三分割は端から端まで埋める() {
        let left = LayoutCalculator.frame(for: .leftThird, in: offsetScreen)
        let right = LayoutCalculator.frame(for: .rightThird, in: offsetScreen)
        #expect(left.minX == offsetScreen.minX)
        #expect(right.maxX == offsetScreen.maxX)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'LayoutCalculator' in scope`。

- [ ] **Step 3: 実装する**

```swift
// Tatami/Engine/LayoutCalculator.swift
import CoreGraphics

/// 区画の目標枠を計算する純粋関数。入出力とも NS 座標（左下原点）。
///
/// 分割の端数は右端・上端の区画に寄せ、区画同士に隙間と重なりを作らない。
enum LayoutCalculator {
    static func frame(for action: SnapAction, in visible: CGRect) -> CGRect {
        let halfWidth = (visible.width / 2).rounded(.down)
        let halfHeight = (visible.height / 2).rounded(.down)
        let thirdWidth = (visible.width / 3).rounded(.down)

        switch action {
        case .maximize:
            return visible

        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.minX + halfWidth, y: visible.minY,
                          width: visible.width - halfWidth, height: visible.height)

        // NS 座標は下が原点なので、下半分が minY から始まり、上半分に端数を寄せる。
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfHeight)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY + halfHeight,
                          width: visible.width, height: visible.height - halfHeight)

        case .leftThird:
            return CGRect(x: visible.minX, y: visible.minY, width: thirdWidth, height: visible.height)
        case .centerThird:
            return CGRect(x: visible.minX + thirdWidth, y: visible.minY, width: thirdWidth, height: visible.height)
        case .rightThird:
            return CGRect(x: visible.minX + thirdWidth * 2, y: visible.minY,
                          width: visible.width - thirdWidth * 2, height: visible.height)

        case .leftTwoThirds:
            return CGRect(x: visible.minX, y: visible.minY, width: thirdWidth * 2, height: visible.height)
        case .rightTwoThirds:
            return CGRect(x: visible.minX + thirdWidth, y: visible.minY,
                          width: visible.width - thirdWidth, height: visible.height)
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/Engine/LayoutCalculator.swift TatamiTests/LayoutCalculatorTests.swift
git commit -m "feat: add LayoutCalculator for the 10 snap regions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: CoordinateConverter

**Files:**
- Create: `Tatami/Engine/CoordinateConverter.swift`
- Create: `TatamiTests/CoordinateConverterTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `enum CoordinateConverter`
  - `static func toScreen(_ axFrame: CGRect, primaryHeight: CGFloat) -> CGRect`（AX → NS）
  - `static func toAccessibility(_ screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect`（NS → AX）

- [ ] **Step 1: 失敗するテストを書く**

```swift
// TatamiTests/CoordinateConverterTests.swift
import CoreGraphics
import Testing
@testable import Tatami

struct CoordinateConverterTests {
    /// プライマリ画面の高さ。
    let primaryHeight: CGFloat = 1080

    @Test func プライマリ画面の左上のウィンドウ() {
        // AX: 左上原点で (0, 0) は画面の左上。NS: 左下原点なので y = 1080 - 100 = 980。
        let ax = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: 0, y: 980, width: 200, height: 100))
    }

    @Test func プライマリ画面の左下のウィンドウ() {
        let ns = CGRect(x: 0, y: 0, width: 200, height: 100)
        let ax = CoordinateConverter.toAccessibility(ns, primaryHeight: primaryHeight)
        #expect(ax == CGRect(x: 0, y: 980, width: 200, height: 100))
    }

    @Test func 右側のセカンダリ画面では x はそのまま() {
        let ax = CGRect(x: 1920 + 10, y: 50, width: 300, height: 200)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns.minX == 1930)
        #expect(ns == CGRect(x: 1930, y: 1080 - 250, width: 300, height: 200))
    }

    @Test func 左側のセカンダリ画面では x が負になる() {
        let ax = CGRect(x: -1440, y: 0, width: 100, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: -1440, y: 980, width: 100, height: 100))
    }

    @Test func プライマリより上にある画面では AX の y が負になる() {
        // プライマリの上に高さ 900 の画面がある。その画面の上端は AX では y = -900。
        let ax = CGRect(x: 0, y: -900, width: 100, height: 100)
        let ns = CoordinateConverter.toScreen(ax, primaryHeight: primaryHeight)
        #expect(ns == CGRect(x: 0, y: 1080 + 800, width: 100, height: 100))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 1, height: 1),
        CGRect(x: 123, y: 456, width: 789, height: 12),
        CGRect(x: -1440, y: -900, width: 640, height: 480),
        CGRect(x: 3000, y: 2000, width: 10, height: 10),
    ])
    func 往復変換は元に戻る(frame: CGRect) {
        let roundTrip = CoordinateConverter.toAccessibility(
            CoordinateConverter.toScreen(frame, primaryHeight: primaryHeight),
            primaryHeight: primaryHeight
        )
        #expect(roundTrip == frame)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'CoordinateConverter' in scope`。

- [ ] **Step 3: 実装する**

```swift
// Tatami/Engine/CoordinateConverter.swift
import CoreGraphics

/// AX 座標（左上原点）と NS 座標（左下原点）を相互変換する純粋関数。
///
/// どちらの座標系もプライマリ画面（`NSScreen.screens[0]`）を基準にする。
/// y 軸だけが反転するので、`y' = primaryHeight - (y + height)` を両方向に適用する。
enum CoordinateConverter {
    /// AX 座標 → NS 座標。
    static func toScreen(_ axFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipY(axFrame, primaryHeight: primaryHeight)
    }

    /// NS 座標 → AX 座標。
    static func toAccessibility(_ screenFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipY(screenFrame, primaryHeight: primaryHeight)
    }

    private static func flipY(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryHeight - (frame.minY + frame.height),
            width: frame.width,
            height: frame.height
        )
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/Engine/CoordinateConverter.swift TatamiTests/CoordinateConverterTests.swift
git commit -m "feat: add CoordinateConverter between AX and NSScreen coordinates

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: CycleResolver

**Files:**
- Create: `Tatami/Engine/CycleResolver.swift`
- Create: `TatamiTests/CycleResolverTests.swift`

**Interfaces:**
- Consumes: `SnapCommand`, `SnapAction`, `CycleMemory`, `WindowHandle`
- Produces: `enum CycleResolver { static func resolve(command: SnapCommand, memory: CycleMemory?, window: WindowHandle, currentFrame: CGRect, tolerance: CGFloat = 2) -> SnapAction }`

- [ ] **Step 1: 失敗するテストを書く**

```swift
// TatamiTests/CycleResolverTests.swift
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
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'CycleResolver' in scope`。

- [ ] **Step 3: 実装する**

```swift
// Tatami/Engine/CycleResolver.swift
import CoreGraphics

/// ループ系コマンドで次に適用する区画を決める純粋ロジック。
///
/// 「同じウィンドウに、同じ系列の区画を、直前に適用し、その枠がまだ保たれている」
/// ときだけ系列の次へ進む。それ以外は系列の先頭から始める。
enum CycleResolver {
    static func resolve(
        command: SnapCommand,
        memory: CycleMemory?,
        window: WindowHandle,
        currentFrame: CGRect,
        tolerance: CGFloat = 2
    ) -> SnapAction {
        let sequence = command.sequence
        guard sequence.count > 1 else {
            return sequence[0]
        }

        guard let memory,
              memory.window == window,
              let index = sequence.firstIndex(of: memory.action),
              isClose(memory.appliedFrame, currentFrame, tolerance: tolerance)
        else {
            return sequence[0]
        }

        return sequence[(index + 1) % sequence.count]
    }

    /// 各辺の差がすべて tolerance 以内なら一致とみなす。
    private static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

`別のウィンドウなら先頭から` だけが失敗する場合は、`AXUIElementCreateApplication` の CFEqual が pid を区別していない。その場合は `WindowHandle` に `init(testIdentifier: Int)` を足すのではなく、`WindowHandle` を `struct WindowHandle: Hashable { let element: AXUIElement; let identity: ObjectIdentifier }` にして `identity = ObjectIdentifier(element)` で比較するよう変更し、結果をこの計画に追記する。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/Engine/CycleResolver.swift TatamiTests/CycleResolverTests.swift
git commit -m "feat: add CycleResolver with hybrid cycle detection

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: ScreenLocator

**Files:**
- Create: `Tatami/Engine/ScreenLocator.swift`
- Create: `TatamiTests/ScreenLocatorTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `struct ScreenRegion: Equatable, Sendable { let frame: CGRect; let visibleFrame: CGRect }`（NS 座標）
  - `enum ScreenLocator { static func region(containing windowFrame: CGRect, in screens: [ScreenRegion]) -> ScreenRegion? }`

- [ ] **Step 1: 失敗するテストを書く**

```swift
// TatamiTests/ScreenLocatorTests.swift
import CoreGraphics
import Testing
@testable import Tatami

struct ScreenLocatorTests {
    let primary = ScreenRegion(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 985)
    )
    let secondary = ScreenRegion(
        frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1415)
    )
    var screens: [ScreenRegion] { [primary, secondary] }

    @Test func 中心がプライマリにあればプライマリ() {
        let window = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == primary)
    }

    @Test func 中心がセカンダリにあればセカンダリ() {
        let window = CGRect(x: 2000, y: 100, width: 400, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == secondary)
    }

    @Test func 画面をまたぐウィンドウは中心のある側() {
        // x: 1700〜2300。中心は 2000 なのでセカンダリ。
        let window = CGRect(x: 1700, y: 100, width: 600, height: 300)
        #expect(ScreenLocator.region(containing: window, in: screens) == secondary)
    }

    @Test func 中心が境界線上なら配列で先に来る画面() {
        // 中心 x = 1920。プライマリの frame は maxX = 1920 を含まない（CGRect.contains は半開区間）。
        // セカンダリの minX = 1920 は含むので、決定的にセカンダリになる。
        let window = CGRect(x: 1720, y: 100, width: 400, height: 300)
        let region = ScreenLocator.region(containing: window, in: screens)
        #expect(region == secondary)
    }

    @Test func どの画面にも含まれなければnil() {
        let window = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        #expect(ScreenLocator.region(containing: window, in: screens) == nil)
    }

    @Test func 画面が空ならnil() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(ScreenLocator.region(containing: window, in: []) == nil)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ScreenRegion' in scope`。

- [ ] **Step 3: 実装する**

```swift
// Tatami/Engine/ScreenLocator.swift
import CoreGraphics

/// 1 枚のディスプレイの領域。NS 座標（左下原点）。
struct ScreenRegion: Equatable, Sendable {
    /// ディスプレイ全体。
    let frame: CGRect
    /// メニューバーと Dock を除いた領域。
    let visibleFrame: CGRect
}

/// ウィンドウがどの画面にあるかを決める純粋関数。
enum ScreenLocator {
    /// ウィンドウの中心点を含む最初の画面を返す。含む画面がなければ nil。
    static func region(containing windowFrame: CGRect, in screens: [ScreenRegion]) -> ScreenRegion? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.first { $0.frame.contains(center) }
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/Engine/ScreenLocator.swift TatamiTests/ScreenLocatorTests.swift
git commit -m "feat: add ScreenLocator to pick the screen under a window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: WindowService / 権限 / 画面の protocol と SnapEngine

**Files:**
- Create: `Tatami/System/WindowService.swift`
- Create: `Tatami/System/PermissionChecking.swift`
- Create: `Tatami/System/ScreenProviding.swift`
- Create: `Tatami/Engine/SnapEngine.swift`
- Create: `TatamiTests/Fakes/FakeWindowService.swift`
- Create: `TatamiTests/Fakes/FakePermission.swift`
- Create: `TatamiTests/Fakes/FakeScreenProvider.swift`
- Create: `TatamiTests/SnapEngineTests.swift`

**Interfaces:**
- Consumes: `CycleResolver.resolve`, `LayoutCalculator.frame(for:in:)`, `CoordinateConverter.toScreen/toAccessibility`, `ScreenLocator.region(containing:in:)`, `ScreenRegion`, `CycleMemory`, `WindowHandle`
- Produces:
  - `enum WindowServiceError: Error { case noFrontmostApplication, noFocusedWindow, axError(AXError), invalidValue }`
  - `protocol WindowService { func focusedWindow() throws -> WindowHandle; func frame(of window: WindowHandle) throws -> CGRect; func setFrame(_ frame: CGRect, of window: WindowHandle) throws }`（`@MainActor`、AX 座標）
  - `protocol PermissionChecking: AnyObject { var isTrusted: Bool { get }; func requestAccess() }`（`@MainActor`）
  - `protocol ScreenProviding { var primaryHeight: CGFloat { get }; var screens: [ScreenRegion] { get }; var mainScreen: ScreenRegion? { get } }`（`@MainActor`）
  - `enum SnapFailure { case notTrusted, noScreen, window(WindowServiceError), unknown(any Error) }`
  - `@MainActor final class SnapEngine { init(windowService:screens:permission:onFailure:); func perform(_ command: SnapCommand); private(set) var memory: CycleMemory? }`

- [ ] **Step 1: protocol を書く**

```swift
// Tatami/System/WindowService.swift
import ApplicationServices
import CoreGraphics

/// ウィンドウ操作で起こりうる失敗。
enum WindowServiceError: Error, Sendable {
    /// 最前面アプリが取れない。
    case noFrontmostApplication
    /// 最前面アプリにフォーカスウィンドウがない（デスクトップなど）。
    case noFocusedWindow
    /// AX API がエラーを返した。
    case axError(AXError)
    /// AXValue の中身を取り出せなかった。
    case invalidValue
}

/// 最前面ウィンドウの取得と枠の読み書き。座標はすべて AX 座標（左上原点）。
@MainActor
protocol WindowService {
    /// 最前面アプリのフォーカスウィンドウ。
    func focusedWindow() throws -> WindowHandle
    /// 現在の枠。
    func frame(of window: WindowHandle) throws -> CGRect
    /// 枠を設定する。実装は size → position → size の順で適用する。
    func setFrame(_ frame: CGRect, of window: WindowHandle) throws
}
```

```swift
// Tatami/System/PermissionChecking.swift
import Foundation

/// Accessibility 権限の確認と要求。
@MainActor
protocol PermissionChecking: AnyObject {
    /// 今この瞬間に許可されているか。キャッシュしない。
    var isTrusted: Bool { get }
    /// システムのプロンプトを出して許可を求める。
    func requestAccess()
}
```

```swift
// Tatami/System/ScreenProviding.swift
import CoreGraphics

/// 接続中のディスプレイ情報。NS 座標（左下原点）。
@MainActor
protocol ScreenProviding {
    /// プライマリ画面（原点 (0,0) を持つ画面）の高さ。座標変換の基準。
    var primaryHeight: CGFloat { get }
    /// 接続中の全画面。
    var screens: [ScreenRegion] { get }
    /// フォールバックに使う画面。
    var mainScreen: ScreenRegion? { get }
}
```

- [ ] **Step 2: Fake を書く**

```swift
// TatamiTests/Fakes/FakeWindowService.swift
import ApplicationServices
import CoreGraphics
@testable import Tatami

/// テスト用の WindowService。枠はメモリ上に持ち、setFrame に制約を掛けられる。
@MainActor
final class FakeWindowService: WindowService {
    var window = WindowHandle(element: AXUIElementCreateApplication(1))
    var currentFrame = CGRect(x: 0, y: 0, width: 800, height: 600)

    /// focusedWindow() で投げるエラー。nil なら成功。
    var focusedWindowError: WindowServiceError?
    /// frame(of:) で投げるエラー。nil なら成功。
    var frameError: WindowServiceError?
    /// setFrame 直後の 1 回の frame(of:) だけで投げるエラー。読み直し失敗を再現する。
    var frameErrorAfterSet: WindowServiceError?
    /// setFrame で投げるエラー。
    var setFrameError: WindowServiceError?
    /// ウィンドウの最小幅。目標がこれより小さければこの幅に丸められる。
    var minimumWidth: CGFloat = 0

    private(set) var setFrameCalls: [CGRect] = []
    private var pendingReadError: WindowServiceError?

    func focusedWindow() throws -> WindowHandle {
        if let focusedWindowError { throw focusedWindowError }
        return window
    }

    func frame(of window: WindowHandle) throws -> CGRect {
        if let frameError { throw frameError }
        if let pendingReadError {
            self.pendingReadError = nil
            throw pendingReadError
        }
        return currentFrame
    }

    func setFrame(_ frame: CGRect, of window: WindowHandle) throws {
        if let setFrameError { throw setFrameError }
        setFrameCalls.append(frame)
        pendingReadError = frameErrorAfterSet
        var applied = frame
        if applied.width < minimumWidth {
            applied.size.width = minimumWidth
        }
        currentFrame = applied
    }
}
```

```swift
// TatamiTests/Fakes/FakePermission.swift
@testable import Tatami

@MainActor
final class FakePermission: PermissionChecking {
    var isTrusted = true
    private(set) var requestAccessCount = 0

    func requestAccess() {
        requestAccessCount += 1
    }
}
```

```swift
// TatamiTests/Fakes/FakeScreenProvider.swift
import CoreGraphics
@testable import Tatami

@MainActor
struct FakeScreenProvider: ScreenProviding {
    var primaryHeight: CGFloat
    var screens: [ScreenRegion]
    var mainScreen: ScreenRegion?

    /// 1920×1080 の単一画面。メニューバー 25pt、Dock 45pt を除いた visibleFrame。
    static let single = FakeScreenProvider(
        primaryHeight: 1080,
        screens: [ScreenRegion(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 45, width: 1920, height: 1010)
        )],
        mainScreen: ScreenRegion(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 45, width: 1920, height: 1010)
        )
    )
}
```

- [ ] **Step 3: 失敗するテストを書く**

```swift
// TatamiTests/SnapEngineTests.swift
import CoreGraphics
import Testing
@testable import Tatami

@MainActor
struct SnapEngineTests {
    let windows = FakeWindowService()
    let permission = FakePermission()
    let screens = FakeScreenProvider.single

    /// visibleFrame (0, 45, 1920, 1010) の NS 座標を AX 座標にしたもの。
    /// AX の y = 1080 - (45 + 1010) = 25。
    let visibleAX = CGRect(x: 0, y: 25, width: 1920, height: 1010)

    func makeEngine(onFailure: @escaping @MainActor (SnapFailure) -> Void = { _ in }) -> SnapEngine {
        SnapEngine(windowService: windows, screens: screens, permission: permission, onFailure: onFailure)
    }

    @Test func 最大化はvisibleFrameをAX座標で適用する() {
        let engine = makeEngine()
        engine.perform(.maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 左半分はAX座標で左側の枠になる() {
        let engine = makeEngine()
        engine.perform(.cycleLeft)
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 25, width: 960, height: 1010)])
    }

    @Test func 上半分はAX座標でyが小さい側になる() {
        let engine = makeEngine()
        engine.perform(.topHalf)
        // NS: y = 45 + 505 = 550, height = 505 → AX: y = 1080 - (550 + 505) = 25
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 25, width: 1920, height: 505)])
    }

    @Test func 下半分はAX座標でyが大きい側になる() {
        let engine = makeEngine()
        engine.perform(.bottomHalf)
        // NS: y = 45, height = 505 → AX: y = 1080 - (45 + 505) = 530
        #expect(windows.setFrameCalls == [CGRect(x: 0, y: 530, width: 1920, height: 505)])
    }

    @Test func 同じキーを3回押すと半分_1_3_2_3と進む() {
        let engine = makeEngine()
        engine.perform(.cycleRight)
        engine.perform(.cycleRight)
        engine.perform(.cycleRight)
        let widths = windows.setFrameCalls.map(\.width)
        #expect(widths == [960, 640, 1280])
        #expect(engine.memory?.action == .rightTwoThirds)
    }

    @Test func 最小幅制約で1_3にならなくてもループは進む() {
        windows.minimumWidth = 800
        let engine = makeEngine()
        engine.perform(.cycleLeft)   // 半分 960
        engine.perform(.cycleLeft)   // 1/3 を要求するが 800 に丸められる
        #expect(windows.currentFrame.width == 800)
        engine.perform(.cycleLeft)   // 実枠 800 と記憶が一致するので 2/3 へ
        #expect(windows.setFrameCalls.last?.width == 1280)
    }

    @Test func 権限がなければsetFrameを呼ばず再要求する() {
        permission.isTrusted = false
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        #expect(permission.requestAccessCount == 1)
        #expect(captured.count == 1)
        if case .notTrusted = captured[0] {} else {
            Issue.record("notTrusted ではなく \(captured[0])")
        }
    }

    @Test func ウィンドウが取れなければ失敗フックを呼ぶ() {
        windows.focusedWindowError = .noFocusedWindow
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        #expect(captured.count == 1)
        if case .window(.noFocusedWindow) = captured[0] {} else {
            Issue.record("window(noFocusedWindow) ではなく \(captured[0])")
        }
    }

    @Test func 適用後の読み直しに失敗しても記憶を壊さない() {
        var captured: [SnapFailure] = []
        let engine = makeEngine { captured.append($0) }
        engine.perform(.cycleLeft)
        let before = engine.memory
        #expect(before?.action == .leftHalf)

        windows.frameErrorAfterSet = .axError(.failure)
        engine.perform(.cycleLeft)
        #expect(windows.setFrameCalls.count == 2)
        #expect(engine.memory == before)
        #expect(captured.count == 1)
    }

    @Test func 画面が見つからなければmainScreenにフォールバックする() {
        windows.currentFrame = CGRect(x: 10000, y: 10000, width: 100, height: 100)
        let engine = makeEngine()
        engine.perform(.maximize)
        #expect(windows.setFrameCalls == [visibleAX])
    }

    @Test func 画面もmainScreenもなければ失敗フックを呼ぶ() {
        var captured: [SnapFailure] = []
        let empty = FakeScreenProvider(primaryHeight: 1080, screens: [], mainScreen: nil)
        let engine = SnapEngine(windowService: windows, screens: empty, permission: permission,
                                onFailure: { captured.append($0) })
        engine.perform(.maximize)
        #expect(windows.setFrameCalls.isEmpty)
        if case .noScreen = captured.first {} else {
            Issue.record("noScreen ではなく \(String(describing: captured.first))")
        }
    }
}
```

- [ ] **Step 4: テストが失敗することを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SnapEngine' in scope`。

- [ ] **Step 5: SnapEngine を実装する**

```swift
// Tatami/Engine/SnapEngine.swift
import CoreGraphics
import os

/// スナップが成立しなかった理由。UI 側は beep とログに使う。
enum SnapFailure: Sendable {
    case notTrusted
    case noScreen
    case window(WindowServiceError)
    case unknown(any Error)
}

/// ショートカット 1 回分のスナップを実行する司令塔。
///
/// 権限確認 → ウィンドウ取得 → 画面特定 → 区画決定 → 枠計算 → 適用 → 記憶更新 の順に進む。
/// 座標は WindowService との境界で AX 座標、レイアウト計算は NS 座標。
@MainActor
final class SnapEngine {
    private let windowService: any WindowService
    private let screens: any ScreenProviding
    private let permission: any PermissionChecking
    private let onFailure: @MainActor (SnapFailure) -> Void
    private let logger = Logger(subsystem: "dev.hidekingerz.tatami", category: "SnapEngine")

    /// 直前のスナップの記憶。ループ判定に使う。
    private(set) var memory: CycleMemory?

    init(
        windowService: any WindowService,
        screens: any ScreenProviding,
        permission: any PermissionChecking,
        onFailure: @escaping @MainActor (SnapFailure) -> Void
    ) {
        self.windowService = windowService
        self.screens = screens
        self.permission = permission
        self.onFailure = onFailure
    }

    func perform(_ command: SnapCommand) {
        guard permission.isTrusted else {
            permission.requestAccess()
            fail(.notTrusted)
            return
        }

        do {
            let window = try windowService.focusedWindow()
            let currentAX = try windowService.frame(of: window)
            let primaryHeight = screens.primaryHeight
            let currentNS = CoordinateConverter.toScreen(currentAX, primaryHeight: primaryHeight)

            guard let region = ScreenLocator.region(containing: currentNS, in: screens.screens)
                    ?? screens.mainScreen
            else {
                fail(.noScreen)
                return
            }

            let action = CycleResolver.resolve(
                command: command, memory: memory, window: window, currentFrame: currentAX
            )
            let targetNS = LayoutCalculator.frame(for: action, in: region.visibleFrame)
            let targetAX = CoordinateConverter.toAccessibility(targetNS, primaryHeight: primaryHeight)

            try windowService.setFrame(targetAX, of: window)
            let appliedAX = try windowService.frame(of: window)
            memory = CycleMemory(window: window, action: action, appliedFrame: appliedAX)
            logger.debug("\(String(describing: action)) -> \(String(describing: appliedAX))")
        } catch let error as WindowServiceError {
            fail(.window(error))
        } catch {
            fail(.unknown(error))
        }
    }

    private func fail(_ failure: SnapFailure) {
        logger.error("snap failed: \(String(describing: failure))")
        onFailure(failure)
    }
}
```

- [ ] **Step 6: テストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "passed|failed|TEST" | tail -5`
Expected: 全件 passed、`** TEST SUCCEEDED **`。

Swift 6 のエラーで `FakeScreenProvider` の `static let single` が `@MainActor` 文脈外と言われたら、`static let single` を `static var single: FakeScreenProvider { ... }` の computed property に変える。

- [ ] **Step 7: コミットする**

```bash
git add Tatami/System Tatami/Engine/SnapEngine.swift TatamiTests
git commit -m "feat: add SnapEngine with WindowService, permission, and screen protocols

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: AX / NSScreen / 権限の実装

**Files:**
- Create: `Tatami/System/AccessibilityWindowService.swift`
- Create: `Tatami/System/PermissionGate.swift`
- Create: `Tatami/System/NSScreenProvider.swift`

**Interfaces:**
- Consumes: `WindowService`, `WindowServiceError`, `WindowHandle`, `PermissionChecking`, `ScreenProviding`, `ScreenRegion`
- Produces:
  - `struct AccessibilityWindowService: WindowService`
  - `@MainActor final class PermissionGate: PermissionChecking { func openSystemSettings() }`
  - `struct NSScreenProvider: ScreenProviding`

このタスクは AX API のラッパーなので単体テストはしない（設計書 7 章）。ビルドが通ることと、Task 9 の手動確認で検証する。

- [ ] **Step 1: AccessibilityWindowService を書く**

```swift
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
              AXValueGetValue(value as! AXValue, type, &out)
        else {
            throw WindowServiceError.invalidValue
        }
    }

    private func write<T>(
        _ attribute: String, as type: AXValueType, value: inout T, to window: WindowHandle
    ) throws {
        guard let axValue = AXValueCreate(type, &value) else {
            throw WindowServiceError.invalidValue
        }
        let result = AXUIElementSetAttributeValue(window.element, attribute as CFString, axValue)
        guard result == .success else {
            throw WindowServiceError.axError(result)
        }
    }
}
```

- [ ] **Step 2: PermissionGate を書く**

```swift
// Tatami/System/PermissionGate.swift
import AppKit
import ApplicationServices

/// Accessibility 権限の確認と、システム設定への誘導。
@MainActor
final class PermissionGate: PermissionChecking {
    /// 毎回 OS に問い合わせる。許可直後に再起動なしで動くようにするため。
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// システムのプロンプトを出して許可を求める。
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く。
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: NSScreenProvider を書く**

```swift
// Tatami/System/NSScreenProvider.swift
import AppKit

/// NSScreen から ScreenProviding を組み立てる。
struct NSScreenProvider: ScreenProviding {
    /// プライマリ画面は `NSScreen.screens[0]`。`NSScreen.main` はキーウィンドウのある画面なので使わない。
    var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    var screens: [ScreenRegion] {
        NSScreen.screens.map { ScreenRegion(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    var mainScreen: ScreenRegion? {
        NSScreen.main.map { ScreenRegion(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}
```

- [ ] **Step 4: ビルドとテストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:|passed|failed|TEST" | tail -6`
Expected: エラーなし、全件 passed、`** TEST SUCCEEDED **`。

Swift 6 で `value as! AXUIElement` がコンパイルできない場合は、`CFGetTypeID` で検査済みであることをコメントに残したまま `unsafeBitCast(value, to: AXUIElement.self)` に置き換える。

- [ ] **Step 5: コミットする**

```bash
git add Tatami/System
git commit -m "feat: add AX, NSScreen, and permission adapters

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: ショートカット登録・メニュー・設定画面・配線と手動確認

**Files:**
- Create: `Tatami/App/ShortcutRegistrar.swift`
- Create: `Tatami/App/AppModel.swift`
- Create: `Tatami/App/MenuBarView.swift`
- Create: `Tatami/App/SettingsView.swift`
- Modify: `Tatami/App/TatamiApp.swift`
- Modify: `docs/superpowers/specs/2026-10-10-tatami-mvp-design.md`（6 章にホットキー重複の確認結果を追記）

**Interfaces:**
- Consumes: `SnapEngine`, `SnapCommand`, `AccessibilityWindowService`, `NSScreenProvider`, `PermissionGate`, `SnapFailure`
- Produces: `extension KeyboardShortcuts.Name`（6 つ）、`extension SnapCommand { var shortcutName; var title }`、`ShortcutRegistrar.register(engine:)`、`AppModel`

- [ ] **Step 1: ショートカット名とデフォルトを定義する**

```swift
// Tatami/App/ShortcutRegistrar.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let cycleLeft = Self("cycleLeft", default: .init(.b, modifiers: [.control, .option]))
    static let cycleRight = Self("cycleRight", default: .init(.f, modifiers: [.control, .option]))
    static let topHalf = Self("topHalf", default: .init(.p, modifiers: [.control, .option]))
    static let bottomHalf = Self("bottomHalf", default: .init(.n, modifiers: [.control, .option]))
    static let maximize = Self("maximize", default: .init(.m, modifiers: [.control, .option]))
    static let centerThird = Self("centerThird", default: .init(.c, modifiers: [.control, .option]))
}

extension SnapCommand {
    /// KeyboardShortcuts に登録する名前。
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .cycleLeft: .cycleLeft
        case .cycleRight: .cycleRight
        case .topHalf: .topHalf
        case .bottomHalf: .bottomHalf
        case .maximize: .maximize
        case .centerThird: .centerThird
        }
    }

    /// 設定画面に表示するラベル。
    var title: String {
        switch self {
        case .cycleLeft: "左半分 / 左 1/3 / 左 2/3"
        case .cycleRight: "右半分 / 右 1/3 / 右 2/3"
        case .topHalf: "上半分"
        case .bottomHalf: "下半分"
        case .maximize: "最大化"
        case .centerThird: "中央 1/3"
        }
    }
}

/// 6 つのショートカットを SnapEngine に接続する。
@MainActor
enum ShortcutRegistrar {
    static func register(engine: SnapEngine) {
        for command in SnapCommand.allCases {
            KeyboardShortcuts.onKeyDown(for: command.shortcutName) {
                engine.perform(command)
            }
        }
    }
}
```

`onKeyDown` のクロージャが `@MainActor` でないとコンパイラに言われたら、クロージャの中身を `Task { @MainActor in engine.perform(command) }` にする。

- [ ] **Step 2: AppModel を書く**

```swift
// Tatami/App/AppModel.swift
import AppKit
import Observation

/// アプリ全体で 1 つだけ持つ依存の束。起動時に権限を要求し、ショートカットを登録する。
@MainActor
@Observable
final class AppModel {
    let permission = PermissionGate()
    let engine: SnapEngine

    init() {
        let permission = self.permission
        engine = SnapEngine(
            windowService: AccessibilityWindowService(),
            screens: NSScreenProvider(),
            permission: permission,
            onFailure: { _ in NSSound.beep() }
        )
        permission.requestAccess()
        ShortcutRegistrar.register(engine: engine)
    }
}
```

- [ ] **Step 3: MenuBarView と SettingsView を書く**

```swift
// Tatami/App/MenuBarView.swift
import SwiftUI

/// メニューバー項目をクリックしたときのメニュー。開くたびに body が評価されるので権限状態は毎回読む。
struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permission.isTrusted {
            Button("アクセシビリティ権限が必要です…") {
                model.permission.openSystemSettings()
            }
            Divider()
        }
        Button("設定…") {
            NSApp.activate()
            openSettings()
        }
        Divider()
        Button("tatami を終了") {
            NSApp.terminate(nil)
        }
    }
}
```

```swift
// Tatami/App/SettingsView.swift
import KeyboardShortcuts
import SwiftUI

/// ショートカットを変更する設定画面。保存は KeyboardShortcuts が UserDefaults に行う。
struct SettingsView: View {
    var body: some View {
        Form {
            ForEach(SnapCommand.allCases, id: \.self) { command in
                KeyboardShortcuts.Recorder(command.title, name: command.shortcutName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
```

- [ ] **Step 4: TatamiApp を配線する**

```swift
// Tatami/App/TatamiApp.swift
import SwiftUI

/// アプリのエントリポイント。メニューバー項目と設定ウィンドウの 2 シーンを持つ。
@main
struct TatamiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("tatami", systemImage: "rectangle.split.2x1") {
            MenuBarView(model: model)
        }
        Settings {
            SettingsView()
        }
    }
}
```

- [ ] **Step 5: ビルドとテストが通ることを確認する**

Run: `xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test 2>&1 | grep -E "error:|passed|failed|TEST" | tail -6`
Expected: エラーなし、全件 passed、`** TEST SUCCEEDED **`。

- [ ] **Step 6: アプリを起動して権限プロンプトを確認する**

Run:
```bash
APP=$(xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $3}')
open "$APP/Tatami.app"
```
Expected:
- Dock にアイコンが出ない。メニューバーに分割矩形のアイコンが出る。
- 初回起動でシステムの Accessibility 許可ダイアログが出る。
- メニューを開くと「アクセシビリティ権限が必要です…」が見え、クリックするとシステム設定のアクセシビリティ画面が開く。
- システム設定で Tatami を許可する。

注意: ad-hoc 署名（`CODE_SIGN_IDENTITY = "-"`）なので、再ビルドのたびに署名が変わり、システム設定で一度 Tatami を削除して再許可する必要があることがある。Apple Developer のチームを持っているなら `DEVELOPMENT_TEAM` を設定すると再許可が不要になる（この計画の範囲外）。

- [ ] **Step 7: 6 つのショートカットを手動で確認する**

許可後、Tatami を終了して再起動（`pkill -x Tatami; open "$APP/Tatami.app"`）し、任意のアプリ（たとえば TextEdit）のウィンドウを前面にして確認する。

| 操作 | 期待 |
|---|---|
| ⌃⌥b を 1 回 | 左半分 |
| ⌃⌥b をさらに 1 回 | 左 1/3 |
| ⌃⌥b をさらに 1 回 | 左 2/3 |
| ⌃⌥b をさらに 1 回 | 左半分に戻る |
| ⌃⌥f を 3 回 | 右半分 → 右 1/3 → 右 2/3 |
| ⌃⌥p | 上半分 |
| ⌃⌥n | 下半分 |
| ⌃⌥m | 最大化（メニューバーと Dock を除く） |
| ⌃⌥c | 中央 1/3 |
| 左 1/3 の状態で手でウィンドウを動かしてから ⌃⌥b | 左半分（先頭に戻る） |
| デスクトップをクリックして Finder のウィンドウがない状態で ⌃⌥m | beep が鳴るだけ |
| 外部ディスプレイがあれば、そちらのウィンドウで ⌃⌥m | その画面で最大化 |

- [ ] **Step 8: 設定画面を確認する**

メニューの「設定…」をクリック。
Expected: 6 行のレコーダーが並んだウィンドウが前面に出る。「最大化」を ⌃⌥x に変えて ⌃⌥x で最大化できること。Tatami を再起動しても ⌃⌥x のままであること。確認後、レコーダーの × で既定に戻す。

- [ ] **Step 9: ホットキー重複時の挙動を確認して設計書に追記する**

同じキーを 2 つのプロセスが登録したときにどちらへ届くかを確認する。Tatami を起動したまま、別のウィンドウ管理アプリ（Rectangle など）がインストールされていればそれで ⌃⌥b を割り当てて試す。なければ、Tatami をもう 1 つ別の Bundle ID で起動するのは手間なので、以下の最小スクリプトで確認する。

```bash
mkdir -p .build/hotkey-probe && cat > .build/hotkey-probe/main.swift <<'EOF'
import Carbon
import AppKit

// ⌃⌥b (keycode 11) を登録して、届いたら標準出力に出す。
var hotKeyRef: EventHotKeyRef?
var hotKeyID = EventHotKeyID(signature: OSType(0x54544D49), id: 1)
RegisterEventHotKey(11, UInt32(controlKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    print("probe received ⌃⌥b"); fflush(stdout); return noErr
}, 1, &spec, nil, nil)
print("probe registered"); fflush(stdout)
NSApplication.shared.run()
EOF
swiftc -O .build/hotkey-probe/main.swift -o .build/hotkey-probe/probe && .build/hotkey-probe/probe
```

手順: Tatami を先に起動 → probe を起動 → ⌃⌥b を押す → どちらが反応したか記録。次に probe を先に起動 → Tatami を起動 → ⌃⌥b を押す → 記録。

設計書 6 章の「先に登録したアプリが優先されると理解している。実装時に実機で確認し、結果をこの節に追記する」を、確認結果（先勝ちか後勝ちか、あるいは両方に届くか）で置き換える。

- [ ] **Step 10: コミットする**

```bash
git add Tatami/App docs/superpowers/specs/2026-10-10-tatami-mvp-design.md
git commit -m "feat: wire shortcuts, menu bar, and settings window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: なし
- Produces: ビルド・実行・ショートカット一覧を書いた README。

- [ ] **Step 1: README を書き換える**

```markdown
# tatami

Snap macOS windows into place with keyboard shortcuts.

キーボードショートカットで最前面ウィンドウを決まった区画へ移動・リサイズするメニューバー常駐アプリです。

## 動作環境

- macOS 26 以降
- アクセシビリティ権限（初回起動時に案内が出ます）

## ショートカット

修飾キーはすべて ⌃⌥（Control + Option）です。設定画面から変更できます。

| キー | 動作 |
|---|---|
| ⌃⌥b | 左半分 → 左 1/3 → 左 2/3 →（ループ） |
| ⌃⌥f | 右半分 → 右 1/3 → 右 2/3 →（ループ） |
| ⌃⌥p | 上半分 |
| ⌃⌥n | 下半分 |
| ⌃⌥m | 最大化 |
| ⌃⌥c | 中央 1/3 |

## ビルド

Xcode 26 以降が必要です。

```sh
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' build
xcodebuild -project Tatami.xcodeproj -scheme Tatami -destination 'platform=macOS' test
```

Xcode で `Tatami.xcodeproj` を開いて Run しても動きます。

## ライセンス

MIT
```

- [ ] **Step 2: コミットする**

```bash
git add README.md
git commit -m "docs: describe shortcuts and build steps in README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
