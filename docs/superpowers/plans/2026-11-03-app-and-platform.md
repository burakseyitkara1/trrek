# trrek Platform Köprüleri, Menü Çubuğu Uygulaması ve Liquid Glass Arayüz — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Jest motorunu gerçek trackpad'e, sistem olaylarına ve haptiğe bağlayan platform hattı; ayarlar, menü çubuğu menüsü, Liquid Glass ayar ve karşılama pencereleri ile overlay'i olan çalışan `trrek.app`; elle test listesi, performans ölçümü ve `v0.1.0` sürümü (spec Aşama 1).

**Architecture:** `TrrekPlatform` içine test edilebilir bir hat eklenir: `FrameConverter` (ham dokunma → `Frame`), `GesturePipeline` (akış + kilit + watchdog + etkinlik), `CommandDispatcher` (komut → protokol arkasındaki sistem eylemleri). Uygulama mantığı (`Settings`, `SettingsStore`, `ConfigMapper`) yeni `TrrekAppCore` kütüphanesinde test edilir; `Trrek` yürütülebilir hedefi AppKit yaşam döngüsü, menü ve SwiftUI pencerelerini taşır.

**Tech Stack:** Swift 6 (tools 6.0), Swift Testing, AppKit, SwiftUI (macOS 26 Liquid Glass: `glassEffect`, `TabView`, `Form`), CoreGraphics event tap'leri, private CoreBrightness (dlsym/NSClassFromString), ServiceManagement, IOKit bildirimleri.

**Spec:** `docs/superpowers/specs/2026-11-03-trrek-design.md` (bölüm 3, 6, 7, 8, 9, 10, 11) ve `docs/superpowers/specs/2026-11-03-spike-results.md`

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 dil modu, `.macOS("26.0")`, yalnızca arm64; Swift 6.3+ dil özellikleri ve macOS 27 API'leri yok (CI: Xcode 26.6 / Swift 6.2).
- Private semboller yalnızca `Sources/TrrekPlatform/PrivateSymbols.swift` içinde (dlopen/dlsym; CoreBrightness için sınıf ve selector adları da burada); eksik sembol özelliği kapatır, çökertmez.
- Projede başka uygulama/kütüphane/proje adı geçmez; kod ve UI İngilizce; belgeler Türkçe. Uygulama adı `trrek`, bundle `com.burakseyitkara.trrek`.
- Performans: boşta %0 CPU, 15 MB altı bellek; kare yolunda heap ayırma yok; periyodik zamanlayıcı yok (yalnızca slide watchdog ve overlay gizleme tek seferlik); SwiftUI pencereleri kapanınca serbest.
- Kare callback'i framework thread'indedir; Engine çağrıları `os_unfair_lock` altında; AppKit/SwiftUI işleri `MainActor`'da.
- Her görev kendi dalında PR ile; `make check` yerelde yeşil; squash merge.
- Menü ve ayar penceresi yerleşimi spec 7.2 ve 7.3'teki gibi; ayar alanları ve varsayılanları spec 7.4'teki gibi.

## Review Focus

1. Trackpad listesi boşken ya da uyku sonrası cihaz yeniden sayımında hat çökmeden "Trackpad not found" durumuna düşmeli, cihaz gelince kendiliğinden başlamalı (Görev 2 `DeviceHotplugObserver` + Görev 3 durum satırı; elle test `docs/testing.md`).
2. Bozuk ya da eski şemalı ayar verisi (`schemaVersion` farklı, bilinmeyen enum değeri) varsayılanlara düşmeli, çökmemeli (Görev 3 testi `storeFallsBackToDefaultsOnCorruptData`).
3. `appSwitchCommit` gelmeden uygulama kapanırsa ⌘ basılı kalmamalı (Görev 1 `CommandDispatcher.releaseAll()` + Görev 3 çıkışta çağrı; test `releaseAllReleasesHeldModifier`).
4. Klavye arka ışığı köprüsü yokken alt kenar varsayılanı Media'ya düşmeli ve ayarlarda seçenek devre dışı olmalı (Görev 3 testi `bottomEdgeFallsBackToMediaWithoutBacklight`, Görev 4 arayüz).
5. Hold-to-Slide "Toggle" modunda modifier'ı başka bir tuşla birlikte basmak durumu değiştirmemeli (Görev 2 testi `toggleIgnoresModifierUsedAsChord`).

---

### Görev 1: Kare dönüştürücü, jest hattı ve komut dağıtıcı

**Files:**
- Create: `Sources/TrrekPlatform/Pipeline/Ports.swift`, `Sources/TrrekPlatform/Pipeline/FrameConverter.swift`, `Sources/TrrekPlatform/Pipeline/GesturePipeline.swift`, `Sources/TrrekPlatform/Pipeline/CommandDispatcher.swift`, `Sources/TrrekPlatform/Input/MousePoster.swift`, `Sources/TrrekPlatform/Input/SystemPosters.swift`
- Modify: `Sources/TrrekPlatform/Multitouch/RawFrameStream.swift` (`onFrame` `@Sendable`; `stop()` belgesi), `Sources/TrrekPlatform/Multitouch/MultitouchDevices.swift` (yeniden sayımda eski listeyi bırak), `Sources/TrrekPlatform/Haptics/ActuatorHaptics.swift` (`HapticPerforming`), `Sources/TrrekPlatform/Input/EventTapGuard.swift` (`.cghidEventTap`, `CursorFreezing`, `@MainActor` oluşturma), `Package.swift` (`TrrekPlatformTests` hedefi; `TrrekProbe` için açık `CMultitouch` bağımlılığı), `CHANGELOG.md`
- Create: `Tests/TrrekPlatformTests/FrameConverterTests.swift`, `Tests/TrrekPlatformTests/CommandDispatcherTests.swift`, `Tests/TrrekPlatformTests/Support/Fakes.swift`

**Interfaces:**
- Consumes: `MTTouch` (CMultitouch), `MultitouchDeviceInfo`, `RawFrameStream`, `ActuatorHaptics.actuate(waveform:)`, `MediaKeyPoster.post(_:fine:)`, `KeyPoster.press/modifierDown/modifierUp`, `EventTapGuard.setFreeze`, `GestureEngine`, `GestureCommand`, `HapticEvent`, `DeviceGeometry`, `Frame`.
- Produces:
  - `public enum HapticStrength: String, CaseIterable, Codable, Sendable { case off, light, medium, strong }`
  - `public enum OverlayKind: Sendable { case keyboardBacklight, externalBrightness, scrub }`
  - Protokoller (hepsi `Sendable`): `MediaKeyPosting { func post(_ key: MediaKey, fine: Bool) }`, `KeyPosting { func press(keyCode: CGKeyCode, flags: CGEventFlags); func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags); func modifierUp(_ keyCode: CGKeyCode) }`, `MousePosting { func middleClick() }`, `HapticPerforming { func perform(_ event: HapticEvent, strength: HapticStrength) }`, `CursorFreezing { func setFreeze(_ on: Bool) }`, `KeyboardBacklightControlling { var isAvailable: Bool { get }; func step(_ direction: Int, fine: Bool) -> Float? }` (yeni seviye 0…1), `LevelOverlayPresenting { func show(kind: OverlayKind, level: Float, label: String?) }`
  - `public enum FrameConverter { public static func frame(touches: UnsafeBufferPointer<MTTouch>, timestamp: Double, deviceID: UInt64, geometry: DeviceGeometry) -> Frame }` — yalnızca `state ∈ {3, 4}`; `x = nx`, `y = ny`, `majorAxisMM = majorAxis`; 16'dan fazlası atılır.
  - `public final class GesturePipeline: @unchecked Sendable { public init(engine: GestureEngine, lostTimeout: TimeInterval); public private(set) var isRunning: Bool; public var deviceCount: Int; public func start() throws; public func stop(); public func restart() }` — `MultitouchDevices.enumerate()` ile cihazları alır, `MTDeviceRef` → (`UInt64` kimlik, `DeviceGeometry`) tablosu kurar, `RawFrameStream.onFrame` içinde `FrameConverter` + `os_unfair_lock` altında `engine.process`; her karede `engine.stateKind ∈ {sliding, lost}` ise tek seferlik `DispatchSourceTimer`'ı `lostTimeout` ile yeniden kurar (dolunca kilit altında `engine.tick(now:)`); `sliding`'e girişte `ProcessInfo.processInfo.beginActivity(.userInitiated, reason: "trrek slide")`, çıkışta `endActivity`. `start()` cihaz yoksa `PipelineError.noDevices` fırlatır.
  - `public final class CommandDispatcher: CommandSink, @unchecked Sendable { public init(mediaKeys: any MediaKeyPosting, keys: any KeyPosting, mouse: any MousePosting, haptics: any HapticPerforming, freezer: any CursorFreezing, backlight: (any KeyboardBacklightControlling)?, overlay: (any LevelOverlayPresenting)?); public var hapticStrength: HapticStrength; public func handle(_ command: GestureCommand, device: UInt64); public func releaseAll() }` — eşleme: `stepVolume(+1/−1, fine)` → `soundUp/soundDown`; `stepBrightness` → `brightnessUp/Down`; `stepKeyboardBacklight` → `backlight?.step(dir, fine:)` ve dönen seviye ile `overlay?.show(kind: .keyboardBacklight, level:, label: nil)` (köprü yoksa hiçbir şey); `appSwitchStep(n)`: ilk adımda `modifierDown(55, .maskCommand)` ve `switcherHeld = true`, her adımda `press(48, n > 0 ? .maskCommand : [.maskCommand, .maskShift])`; `appSwitchCommit` → `modifierUp(55)`; `appSwitchCancel` → `press(53, .maskCommand)` sonra `modifierUp(55)`; `scrubStep/Commit/Cancel` → Aşama 1'de yok sayılır (log `info`); `mediaPlayPause/Next/Previous` → `play/next/previous`; `mute` → `mute`; `screenshot` → `press(23, [.maskCommand, .maskShift])`; `middleClick` → `mouse.middleClick()`; `haptic(e)` → `haptics.perform(e, strength:)`; `freezeCursor(b)` → `freezer.setFreeze(b)`. `releaseAll()`: `switcherHeld` ise `modifierUp(55)`, `freezer.setFreeze(false)`.
  - `public struct SystemMediaKeys: MediaKeyPosting`, `SystemKeys: KeyPosting`, `SystemMouse: MousePosting` (mevcut `MediaKeyPoster`/`KeyPoster`/`MousePoster` enum'larını sarar).
  - `public enum MousePoster { static func middleClick() }` — `CGEvent(mouseEventSource: EventStamp.source, mouseType: .otherMouseDown/.otherMouseUp, mouseCursorPosition: <imleç, CG koordinatı>, mouseButton: .center)`, `mouseButtonNumber = 2`, damgalı, `.cghidEventTap`.
  - `ActuatorHaptics: HapticPerforming`: `off` → hiçbir şey; `light/medium/strong` → dalga formu 4/5/6; `strong` ve olay `.start`/`.tap` ise ikinci darbe 60 ms sonra (`DispatchQueue.global().asyncAfter`, tek seferlik). `.limit` adım gibi.
  - `EventTapGuard: CursorFreezing`; tap konumu `.cghidEventTap`; `init` `@MainActor`.
  - Test sahteleri: `FakeMediaKeys`, `FakeKeys`, `FakeMouse`, `FakeHaptics`, `FakeFreezer`, `FakeBacklight(level:)`, `FakeOverlay` — çağrıları diziye kaydeder.

- [ ] **Step 1: Başarısız testler** — `FrameConverterTests.swift`:

```swift
@Test func converterKeepsOnlyTouchingStates() { /* state 1,3,4,5 → yalnızca 3 ve 4 (count 2) */ }
@Test func converterMapsFields() { /* nx 0.5, ny 0.25, majorAxis 8.5 → Touch x 0.5, y 0.25, majorAxisMM 8.5; id = identifier */ }
@Test func converterTruncatesAtSixteen() { /* 20 touching → count 16 */ }
```
`CommandDispatcherTests.swift`:
```swift
@Test func volumeStepsPostMediaKeys() { /* +1 → soundUp fine false; −1 fine true → soundDown fine true */ }
@Test func switcherProtocol() { /* appSwitchStep(1) → modifierDown(55, cmd) then press(48, cmd); appSwitchStep(-1) → press(48, cmd+shift) only; appSwitchCommit → modifierUp(55) */ }
@Test func switcherCancelSendsEscapeThenReleases() { }
@Test func releaseAllReleasesHeldModifier() { /* step then releaseAll → modifierUp(55) exactly once; freezer false */ }
@Test func backlightStepShowsOverlay() { /* FakeBacklight level 0.5 → step(+1,false) → overlay show(.keyboardBacklight, 0.5625) */ }
@Test func backlightMissingDoesNothing() { }
@Test func hapticsOffPerformsNothing() { /* strength off → FakeHaptics boş; medium → perform(.step, .medium) */ }
@Test func cornerAndMediaCommands() { /* mute → mute; screenshot → press(23, cmd+shift); mediaNext → next; middleClick → mouse 1 */ }
@Test func freezeCommandsForward() { }
```

- [ ] **Step 2: Çalıştır** — Run: `make test 2>&1 | tail -3` — Expected: derleme hatası (hedef/tipler yok).

- [ ] **Step 3: Package.swift** — `TrrekPlatformTests` (testTarget, dependencies: TrrekPlatform, TrrekEngine); `TrrekProbe` bağımlılıklarına `CMultitouch` ekle.

- [ ] **Step 4: Ports, FrameConverter, Dispatcher, posters, hijyen değişiklikleri** — Interfaces bloğundaki imzalar; `RawFrameStream.onFrame` tipi `(@Sendable (MTDeviceRef, UnsafeBufferPointer<MTTouch>, Double) -> Void)?`; `MultitouchDevices.enumerate()` önceki listeyi yalnızca hiçbir akış çalışmıyorken bırakır (basit: `retainedLists` yerine son liste tutulur, eskisi `stop()` sonrası serbest).

- [ ] **Step 5: GesturePipeline** — Interfaces bloğundaki davranış; kare callback'inde ayırma yok (tablo aramasında sözlük yerine küçük sabit dizi; cihaz sayısı ≤ 4).

- [ ] **Step 6: Çalıştır** — Run: `make test 2>&1 | tail -3` — Expected: tüm testler geçer (Engine 68 + Platform ≥ 12).

- [ ] **Step 7: Probe ile canlı doğrulama** — `TrrekProbe`'a `pipeline [saniye]` komutu ekle: `GestureEngine(config: EngineConfig(), sink: LoggingSink)` + `GesturePipeline`; her komutu bir satır yazdırır (hiçbir sistem eylemi göndermez). Run: `swift build && .build/debug/TrrekProbe pipeline 20` ve sağ kenarda yukarı kaydır — Expected: `stepVolume(1)` satırları ve `haptic(.step)`; kalkınca `freezeCursor(false)`.

- [ ] **Step 8: Commit ve PR** — `make check && git add -A && git commit -m "feat(platform): add frame converter, gesture pipeline and command dispatcher"`; dal `feat/platform-pipeline`; CHANGELOG satırı `- Platform: gesture pipeline, command dispatcher and testable ports`.

---

### Görev 2: Giriş izleme, Hold-to-Slide, klavye ışığı ve sistem gözlemcileri

**Files:**
- Create: `Sources/TrrekPlatform/Input/InputMonitor.swift`, `Sources/TrrekPlatform/Input/HoldKeyTracker.swift`, `Sources/TrrekPlatform/Keyboard/KeyboardBacklight.swift`, `Sources/TrrekPlatform/System/FrontmostObserver.swift`, `Sources/TrrekPlatform/System/WakeObserver.swift`, `Sources/TrrekPlatform/System/DeviceHotplugObserver.swift`, `Sources/TrrekPlatform/System/LaunchAtLogin.swift`
- Modify: `Sources/TrrekPlatform/PrivateSymbols.swift` (CoreBrightness: framework yolu, `KeyboardBrightnessClient` sınıf adı, selector adları), `Sources/TrrekPlatform/System/Permissions.swift` (`onChange`), `Sources/TrrekProbe/Commands.swift` (`backlight` ve `keys` komutları), `CHANGELOG.md`
- Create: `Tests/TrrekPlatformTests/HoldKeyTrackerTests.swift`

**Interfaces:**
- Consumes: `EventStamp.isOurs`, `KeyboardBacklightControlling`, `MultitouchDevices`.
- Produces:
  - `public enum HoldKey: String, CaseIterable, Codable, Sendable { case none, shift, control, option, command; var flag: CGEventFlags? }`, `public enum HoldKeyMode: String, CaseIterable, Codable, Sendable { case hold, toggle }`
  - `public struct HoldKeyTracker: Sendable { public init(key: HoldKey, mode: HoldKeyMode); public private(set) var isSatisfied: Bool; public mutating func handleFlagsChanged(_ flags: CGEventFlags, at: TimeInterval) -> Bool; public mutating func handleKeyDown(at: TimeInterval); public mutating func reset() }` — `none` → her zaman `true`; `hold` → modifier basılıyken `true`; `toggle` → modifier tek başına basılıp `≤ 0.3 s` içinde bırakılırsa ve arada `handleKeyDown` gelmediyse `isSatisfied.toggle()`; dönüş değeri "değişti mi".
  - `public final class InputMonitor { @MainActor public init(); public var isAvailable: Bool; public var onKeyDown: (@Sendable (TimeInterval) -> Void)?; public var onFlagsChanged: (@Sendable (CGEventFlags, TimeInterval) -> Void)?; @MainActor public func start(); @MainActor public func stop() }` — Tap A: `.cgSessionEventTap`, `.listenOnly`, `[keyDown, flagsChanged]`; damgalı olaylar yok sayılır; `tapDisabledByTimeout` → yeniden etkinleştir; callback'ler ana run loop'ta.
  - `public final class KeyboardBacklight: KeyboardBacklightControlling { public init?(); public var isAvailable: Bool; public func level() -> Float?; public func step(_ direction: Int, fine: Bool) -> Float? }` — `PrivateSymbols.coreBrightness` üzerinden `NSClassFromString("KeyboardBrightnessClient")`, `copyKeyboardBacklightIDs`, `brightnessForKeyboard:`, `setBrightness:fadeSpeed:commit:forKeyboard:` (`unsafeBitCast` ile `@convention(c)` IMP'ler); adım `1/16` (fine `1/64`), 0…1'e kırpılır; klavye kimliği yoksa `nil`.
  - `public final class FrontmostObserver { public init(); public var onChange: (@Sendable (String?) -> Void)?; public static var currentBundleID: String?; public func start(); public func stop() }` (`NSWorkspace.shared.notificationCenter`, `didActivateApplicationNotification`).
  - `public final class WakeObserver { public init(); public var onWake: (@Sendable () -> Void)?; start/stop }` (`NSWorkspace.didWakeNotification`).
  - `public final class DeviceHotplugObserver { public init(); public var onChange: (@Sendable () -> Void)?; start/stop }` — `IOServiceAddMatchingNotification` ile `AppleMultitouchDevice` `kIOMatchedNotification` ve `kIOTerminatedNotification`; iterator'lar boşaltılır; run loop kaynağı ana run loop'ta.
  - `public enum LaunchAtLogin { public static var isEnabled: Bool; public static func setEnabled(_ on: Bool) throws }` (`SMAppService.mainApp`).
  - `Permissions.onChange: (@Sendable (Bool) -> Void)?` + `startObserving()` (`DistributedNotificationCenter.default()` `"com.apple.accessibility.api"`).

- [ ] **Step 1: Başarısız testler** — `HoldKeyTrackerTests.swift`:

```swift
@Test func noneIsAlwaysSatisfied() { }
@Test func holdFollowsModifierState() { /* flags with .maskShift → true; without → false */ }
@Test func toggleFlipsOnLonePressRelease() { /* down at 0, up at 0.2 → true; again → false */ }
@Test func toggleIgnoresSlowRelease() { /* down 0, up 0.5 → unchanged */ }
@Test func toggleIgnoresModifierUsedAsChord() { /* down 0, keyDown 0.1, up 0.2 → unchanged */ }
@Test func resetClearsToggle() { }
```

- [ ] **Step 2: Çalıştır** — Expected: derleme hatası.
- [ ] **Step 3: HoldKeyTracker ve diğer köprüleri yaz** — Interfaces bloğu.
- [ ] **Step 4: Çalıştır** — Run: `make test 2>&1 | tail -3` — Expected: hepsi geçer.
- [ ] **Step 5: Probe komutları** — `backlight get|up|down` (CoreBrightness ile seviye), `keys [saniye]` (InputMonitor: her keyDown/flagsChanged için bir satır; damgalı olaylar görünmez). Run: `.build/debug/TrrekProbe backlight get` — Expected: 0…1 arası sayı ya da `unavailable`.
- [ ] **Step 6: Commit ve PR** — `feat(platform): add input monitor, hold-key tracker, keyboard backlight and system observers`; dal `feat/platform-system`; CHANGELOG satırı.

---

### Görev 3: Uygulama çekirdeği — ayarlar, koordinatör, menü çubuğu

**Files:**
- Create: `Sources/TrrekAppCore/Settings.swift`, `Sources/TrrekAppCore/SettingsStore.swift`, `Sources/TrrekAppCore/ConfigMapper.swift`
- Create: `Sources/Trrek/main.swift` (yeniden yaz), `Sources/Trrek/AppDelegate.swift`, `Sources/Trrek/Coordinator.swift`, `Sources/Trrek/Menu/StatusMenu.swift`, `Sources/Trrek/Menu/MenuIcon.swift`, `Sources/Trrek/UI/WindowRegistry.swift`
- Modify: `Package.swift` (`TrrekAppCore` library: bağımlılık TrrekEngine, TrrekPlatform; `Trrek` bağımlılığına ekle; `TrrekAppCoreTests`), `Resources/Info.plist.in` (değişmez), `CHANGELOG.md`
- Create: `Tests/TrrekAppCoreTests/SettingsStoreTests.swift`, `Tests/TrrekAppCoreTests/ConfigMapperTests.swift`

**Interfaces:**
- Consumes: Görev 1–2 tipleri, `EngineConfig`, `Thresholds`.
- Produces:
  - `public enum EdgeWidth: String, CaseIterable, Codable, Sendable { case narrow, standard, wide; public var millimetres: Float }` (7, 10, 14)
  - `public struct Settings: Codable, Equatable, Sendable` — spec 7.4 alanları ve varsayılanları; `corners: [Corner: CornerAction]` yerine dört alan `topLeft, topRight, bottomLeft, bottomRight: CornerAction`; `public static let current schemaVersion = 1`; `public init()`.
  - `public final class SettingsStore: @unchecked Sendable { public init(defaults: UserDefaults = .standard, key: String = "settings"); public func load() -> Settings; public func save(_ settings: Settings) }` — JSON; decode hatası ya da `schemaVersion != 1` → `Settings()` + log `error`.
  - `public enum ConfigMapper { public static func engineConfig(from settings: Settings, backlightAvailable: Bool) -> EngineConfig; public static func effectiveBottomEdge(_ settings: Settings, backlightAvailable: Bool) -> EdgeAction }` — swap sides: `left = volume, right = brightness`; `edgeWidthMM = settings.edgeWidth.millimetres`; `bottom = keyboardBacklight` ama köprü yoksa `.media`; `holdKeyRequired = settings.holdKey != .none`; `externalMonitorBrightness` ve `scrubVideo` Aşama 1'de EngineConfig'e etkisiz (scrubVideo seçiliyse `.off`).
  - `Coordinator` (`@MainActor final class`): `init(store: SettingsStore)`; `start()` (izin kontrolü → köprüler → engine → pipeline → input monitor → frontmost/wake/hotplug gözlemcileri → menü); `apply(_ settings: Settings)` (store'a yaz, `engine.update(config:)`, `dispatcher.hapticStrength`, `holdKeyTracker` yeniden kur, `LaunchAtLogin`); `statusText: String` ("trrek is active" / "Paused in <App>" / "Accessibility access needed" / "Trackpad not found" / "Trackpad data unavailable"); `pauseInFrontApp()`, `resumeInFrontApp()`; `openSettings()`, `showWelcome()`, `grantAccessibility()`; `terminate()` (`dispatcher.releaseAll()`, tap'ler kapat, pipeline durdur).
  - `StatusMenu` (`@MainActor`): `NSStatusItem` + `NSMenu` spec 7.2 düzeninde; `NSMenuDelegate.menuNeedsUpdate` ile tazeleme; ikon `MenuIcon.image(active:)` — kod ile çizilen 18×18 pt şablon görüntü (yuvarlatılmış dikdörtgen çerçeve + sağ kenarda dolu dikey şerit; Toggle aktifken sağ altta 4 pt nokta).
  - `WindowRegistry` (`@MainActor`): `settingsWindow`, `welcomeWindow` opsiyonel referanslar; Görev 4–5 doldurur; bu görevde `openSettings()`/`showWelcome()` yalnızca log yazar.
  - Başlatma argümanları (`AppDelegate`): `--settings`, `--welcome` (ilgili pencereyi açar; Görev 4–5'te etkinleşir), `--quit-after <saniye>` (perf/ekran görüntüsü için).

- [ ] **Step 1: Başarısız testler** — `SettingsStoreTests.swift`: `roundTripPreservesAllFields` (her alan varsayılandan farklı değerlerle), `storeFallsBackToDefaultsOnCorruptData` (`defaults.set(Data("x".utf8), forKey:)` → `Settings()`), `storeFallsBackOnSchemaMismatch`. `ConfigMapperTests.swift`: `defaultMappingMatchesSpec`, `swapSidesSwapsLeftRight`, `edgeWidthMapsToMillimetres` (7/10/14), `bottomEdgeFallsBackToMediaWithoutBacklight`, `holdKeyNoneDoesNotRequireKey`, `scrubVideoIsOffInPhaseOne`. `UserDefaults(suiteName: "trrek.tests")` + `removePersistentDomain`.
- [ ] **Step 2: Çalıştır** — Expected: derleme hatası.
- [ ] **Step 3: TrrekAppCore** — Interfaces bloğu.
- [ ] **Step 4: Çalıştır** — Expected: geçer.
- [ ] **Step 5: Uygulama** — `main.swift`: `NSApplication.shared`, `setActivationPolicy(.accessory)`, `AppDelegate` ata, `NSApp.run()`. `AppDelegate.applicationDidFinishLaunching` → `Coordinator.start()`; `applicationWillTerminate` → `terminate()`. Menü, koordinatör, ikon.
- [ ] **Step 6: Paket ve canlı doğrulama** — Run: `make install && open ~/Applications/trrek.app && sleep 3 && pgrep -x trrek && screencapture -x /tmp/trrek-menubar.png` — Expected: süreç çalışıyor; menü çubuğunda ikon görünür (ekran görüntüsü sağ üst). İlk açılışta macOS Accessibility istemi çıkar (kullanıcı verir). Run: `scripts/perf.sh` — Expected: RSS < 15360 KB, CPU 0.0.
- [ ] **Step 7: Commit ve PR** — `feat(app): add settings model, coordinator and menu bar menu`; dal `feat/app-core`; CHANGELOG satırı `- App: settings store, coordinator, menu bar menu, launch at login`.

---

### Görev 4: Ayar penceresi (SwiftUI, Liquid Glass)

**Files:**
- Create: `Sources/Trrek/UI/SettingsWindowController.swift`, `Sources/Trrek/UI/SettingsModel.swift`, `Sources/Trrek/UI/SettingsView.swift`, `Sources/Trrek/UI/GeneralTab.swift`, `Sources/Trrek/UI/EdgesTab.swift`, `Sources/Trrek/UI/CornersTab.swift`, `Sources/Trrek/UI/AdvancedTab.swift`, `Sources/Trrek/UI/TrackpadDiagram.swift`, `Sources/Trrek/UI/PausedAppsList.swift`
- Modify: `Sources/Trrek/Coordinator.swift` (`openSettings()`), `Sources/Trrek/UI/WindowRegistry.swift`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `Settings`, `Coordinator.apply(_:)`, `Permissions`, `KeyboardBacklight.isAvailable`.
- Produces:
  - `@MainActor @Observable final class SettingsModel { init(settings: Settings, backlightAvailable: Bool, onChange: @escaping (Settings) -> Void); var settings: Settings { didSet { onChange(settings) } }; let backlightAvailable: Bool; var accessibilityGranted: Bool }`
  - `SettingsView(model:)` — `TabView` dört sekme: "General", "Edges", "Corners & Taps", "Advanced"; her sekme `Form` + `.formStyle(.grouped)`; pencere 640×480 sabit; `.glassEffect(.regular, in: .rect(cornerRadius: 12))` yalnızca `TrackpadDiagram` yüzeyinde ve köşe rozetlerinde.
  - `TrackpadDiagram(settings: Settings, backlightAvailable: Bool, interactive: Bool)` — 3:2 oranlı yuvarlatılmış trackpad silueti; dört kenar şeridi renk ve etiketle (sağ mavi "Volume", sol sarı "Brightness", üst/alt seçili eyleme göre etiket, `off` ise gri "Off"); dört köşe rozeti (Off/Mute/Screenshot simgesi); `interactive` ise köşe rozetine tıklama seçenek döngüsü yapar.
  - Sekme içerikleri spec 7.3: General (Haptic Feedback segment, Precision Control, Freeze Cursor, Launch at Login, Reset to Defaults… onaylı); Edges (diyagram, Swap Sides, Top Edge/Bottom Edge `Picker` — `Keyboard Backlight` köprü yoksa devre dışı ve "Not available on this Mac", `Scrub Video` devre dışı "Coming later"; Edge Width segment; Bottom Quarter Only; External Monitor Brightness devre dışı "Coming later"); Corners & Taps (diyagram + dört `Picker`, 3-Finger Tap Middle Click, ipucu metni "Set Look up & data detectors to Force click with one finger in System Settings › Trackpad"); Advanced (Hold-to-Slide Key `Picker` + mod segment, `PausedAppsList` (+ `NSOpenPanel` `/Applications`, − kaldır; satırda `NSWorkspace.shared.icon(forFile:)` ve ad), Accessibility durumu + "Open System Settings", sürüm).
  - `SettingsWindowController` (`@MainActor`): `show(model:)` → `NSWindow` (`[.titled, .closable, .miniaturizable]`, `titlebarAppearsTransparent`, `toolbarStyle = .unified`) + `NSHostingController`; `isReleasedWhenClosed = false` ama kapanınca `WindowRegistry.settingsWindow = nil` (hosting controller serbest).

- [ ] **Step 1: Görünümleri yaz** — Interfaces bloğu; metinler İngilizce; SF Symbol'ler: `speaker.wave.2`, `sun.max`, `keyboard`, `rectangle.on.rectangle`, `play`, `speaker.slash`, `camera.viewfinder`.
- [ ] **Step 2: Koordinatör bağlantısı** — `openSettings()`: model yoksa `SettingsModel(settings: current, ...)` oluştur, `onChange` → `apply`; pencereyi öne getir (`NSApp.activate`).
- [ ] **Step 3: Canlı doğrulama** — Run: `make install && open ~/Applications/trrek.app --args --settings && sleep 2 && screencapture -x /tmp/trrek-settings.png` — Expected: pencere görünür; dört sekme; diyagram cam yüzeyli. Her sekme için ekran görüntüsü (`--settings general|edges|corners|advanced` argümanı sekmeyi seçer). Bir ayarı değiştir, uygulamayı kapat-aç → kalıcı.
- [ ] **Step 4: make check ve commit** — `feat(app): add Liquid Glass settings window`; dal `feat/app-settings-window`; CHANGELOG satırı.

---

### Görev 5: Overlay ve karşılama penceresi

**Files:**
- Create: `Sources/Trrek/UI/OverlayPanel.swift`, `Sources/Trrek/UI/OverlayView.swift`, `Sources/Trrek/UI/WelcomeWindowController.swift`, `Sources/Trrek/UI/WelcomeView.swift`
- Modify: `Sources/Trrek/Coordinator.swift` (overlay'i dispatcher'a ver; ilk çalıştırma; `showWelcome`), `Sources/Trrek/AppDelegate.swift` (`--welcome`, `--demo-overlay`), `CHANGELOG.md`

**Interfaces:**
- Consumes: `LevelOverlayPresenting`, `OverlayKind`, `Permissions`, `TrackpadDiagram`, `Settings.welcomeShown`.
- Produces:
  - `@MainActor final class OverlayPanel: LevelOverlayPresenting` — `nonisolated func show(kind:level:label:)` ana aktöre atlar; panel ilk çağrıda oluşturulur (`NSPanel` `[.borderless, .nonactivatingPanel]`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = true`, `hasShadow = false`), `NSHostingView<OverlayView>`; konum: `NSScreen` imlecin bulunduğu ekran, sağ üst, 16 pt boşluk, 220×56 pt; son `show`'dan 1,0 s sonra gizlenir (`DispatchWorkItem`, öncekini iptal); gizlenince içerik güncellenmez.
  - `OverlayView(kind: OverlayKind, level: Float, label: String?)` — `.glassEffect(.regular, in: .capsule)`; SF Symbol (`keyboard`, `sun.max`, `film`), 16 bölmeli seviye çubuğu (`level * 16` yuvarlanır), sağda `label ?? "\(Int(level*100))%"`.
  - `WelcomeView(model:)` 560×440: başlık "Welcome to trrek", `TrackpadDiagram(interactive: false)`, dört cam kart (`glassEffect`): "Right edge — Volume", "Left edge — Brightness", "Top edge — Switch apps", "Bottom edge — Keyboard backlight" (köprü yoksa "Media"); Accessibility durumu satırı ve "Grant Accessibility Access" butonu (`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`), "Open Settings", "Done".
  - `WelcomeWindowController.show(...)`; kapanınca serbest.
  - `Coordinator`: ilk çalıştırmada (`welcomeShown == false`) Welcome'ı aç ve `welcomeShown = true` kaydet; menü "Show Welcome" → `showWelcome()`.
  - `--demo-overlay`: overlay'i `.keyboardBacklight`, 0.5 ile gösterir (ekran görüntüsü için).

- [ ] **Step 1: Overlay ve Welcome'ı yaz** — Interfaces bloğu.
- [ ] **Step 2: Canlı doğrulama** — Run: `make install && open ~/Applications/trrek.app --args --welcome && sleep 2 && screencapture -x /tmp/trrek-welcome.png`; `open ~/Applications/trrek.app --args --demo-overlay && sleep 1 && screencapture -x /tmp/trrek-overlay.png` — Expected: pencere ve overlay görüntülerde; overlay 1 s sonra kaybolur.
- [ ] **Step 3: make check ve commit** — `feat(app): add level overlay and welcome window`; dal `feat/app-overlay-welcome`; CHANGELOG satırı.

---

### Görev 6: Sürüm hazırlığı — elle test listesi, performans, bakım ve v0.1.0

**Files:**
- Create: `docs/testing.md`
- Modify: `README.md` (kurulum, izin, özellik listesi, performans ölçümü), `CHANGELOG.md` (`## [0.1.0] - <tarih>`), `.github/dependabot.yml` (`groups: github-actions: patterns: ["*"]`), `Makefile` (`install`: `mkdir -p ~/Applications`), `scripts/perf.sh` (çalışan örnek varsa uyar ve çık; boş RSS okumasında açık hata), `scripts/build-app.sh` (`--version`/`--build` biçim doğrulaması)
- Modify: `Sources/TrrekEngine/Version.swift` (`"0.1.0"`)

- [ ] **Step 1: Elle test listesi** — `docs/testing.md` (Türkçe): her kenar (ses, parlaklık, uygulama değiştirme, klavye ışığı, medya), köşeler, orta tık, precision, imleç dondurma, scroll bastırma, yazma kapısı, Hold/Toggle, pause in app, uyku sonrası, cihaz takma, ayar penceresi sekmeleri, karşılama, overlay, Accessibility verilmemiş durum, Reset to Defaults, Launch at Login. Her madde için "Nasıl" ve "Beklenen".
- [ ] **Step 2: Bakım düzeltmeleri** — Makefile, perf.sh, build-app.sh, dependabot grouping.
- [ ] **Step 3: Performans ölçümü** — Run: `make install && scripts/perf.sh` — Expected: `RSS < 15360 KB`, `CPU 0.0`; değerleri README "Performance" bölümüne yaz.
- [ ] **Step 4: Sürüm notları** — CHANGELOG `Unreleased` → `0.1.0`; README özellik listesi ve kurulum (`make install`, sağ tık › Open, Accessibility).
- [ ] **Step 5: Commit ve PR** — `chore(release): prepare 0.1.0`; dal `chore/release-0.1.0`; merge sonrası `git tag v0.1.0 && git push origin v0.1.0` → `release.yml` çalışır; Run: `gh release view v0.1.0` — Expected: `trrek-v0.1.0.zip` ve `.dmg` ekli.

---

## Öz denetim notları

- Spec kapsamı: 6.2 (hat) / 6.3 / 6.4 / 6.5 Tap B / 6.6 → Görev 1; 6.5 Tap A / 6.7 Yol B / 6.10 → Görev 2; 7.1 / 7.2 / 7.4 / 7.7 / 7.8 (uygulama tarafı) → Görev 3; 7.3 → Görev 4; 7.5 / 7.6 → Görev 5; 9.3 / 9.4 / 10.5 / 11 Aşama 1 bitişi → Görev 6. 6.8 ve 6.9 (Aşama 2) bu planda yok.
- Önceki plandan taşınan küçükler: `onFrame @Sendable`, cihaz listesi birikimi, `TrrekProbe` açık bağımlılık, `EventTapGuard` ana thread, HID tap konumu → Görev 1; `make install` mkdir, perf.sh korumaları, build-app.sh doğrulaması, dependabot gruplama → Görev 6.
- Review Focus testleri: 2 → Görev 3; 3 → Görev 1; 4 → Görev 3; 5 → Görev 2; 1 elle test (donanım).
