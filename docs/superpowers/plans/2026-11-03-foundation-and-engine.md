# trrek Temel İskelet, CI/CD, Spike ve Jest Motoru — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derlenen ve CI'da test edilen bir SPM paketi, uygulama paketleme ve sürüm hattı, private API varsayımlarını doğrulayan `TrrekProbe` aracı ve spec'teki tüm jest kurallarını testlerle kanıtlayan `TrrekEngine`.

**Architecture:** Üç katmanlı SPM paketi (Engine → Platform → App). Bu plan Engine'i tamamen, Platform'un sembol yükleme ve ham veri katmanını, paketleme betiklerini ve CI/CD'yi kurar. Uygulama katmanı (menü, ayar penceresi) ve Platform'un kalan köprüleri sonraki planda.

**Tech Stack:** Swift 6 (tools 6.0), Swift Testing, AppKit/CoreGraphics/IOKit, private MultitouchSupport (dlsym), GitHub Actions (`macos-26`), SwiftLint, SwiftFormat, Makefile.

**Spec:** `docs/superpowers/specs/2026-11-03-trrek-design.md`

## Global Constraints

- `swift-tools-version: 6.0`, Swift 6 dil modu, platform `.macOS("26.0")`, yalnızca arm64; Swift 6.3+ dil özellikleri ve macOS 27 API'leri kullanılmaz.
- Harici paket bağımlılığı yok. Private framework'ler bağlanmaz, çalışma zamanında `dlopen`/`dlsym` ile yalnızca `Sources/TrrekPlatform/PrivateSymbols.swift` içinde çözülür.
- Projede başka bir uygulamanın, kütüphanenin ya da projenin adı geçmez; atıf yazılmaz; dış koddan kopyalama yapılmaz.
- Kod, yorumlar, commit mesajları ve UI metinleri İngilizce; belgeler ve PR gövdeleri Türkçe. Uygulama adı her yerde `trrek`; bundle ID `com.burakseyitkara.trrek`.
- Performans bütçesi: boşta %0 CPU, 15 MB altı bellek; Engine kare başına heap ayırma yapmaz; periyodik zamanlayıcı yok.
- Her görev kendi dalında (`feat/`, `ci/`, `chore/`, `test/`), PR ile, `make check` yerelde geçtikten sonra; squash merge.
- Eşik değerleri spec 5.2'deki başlangıç değerleridir ve `Thresholds` içinde tek yerde durur.

## Review Focus

1. Yüzey boyutu 0 ya da negatif gelen cihaz: hiçbir bölge tespit edilmemeli, çökme olmamalı (Görev 4 testi `zeroGeometryYieldsNoZone`).
2. 16'dan fazla dokunma içeren kare: `TouchBuffer.append` `false` döner, fazlası sessizce atılır (Görev 4 testi `bufferRejectsSeventeenthTouch`).
3. Zaman damgası geri giden kare (cihaz yeniden başlatma): süreler negatif olmamalı; `tick(now:)` geçmiş bir `now` ile commit üretmemeli (Görev 5 testi `backwardsTimestampDoesNotCommit`).
4. `lost` süresi dolduktan sonra aynı `id` ile yeni dokunma: eski slide'a devam değil, yeni aday olmalı (Görev 5 testi `reusedIDAfterLostExpiryStartsFresh`).
5. `update(config:)` ya da `reset()` `spent`/`threeFinger` durumlarında çağrıldığında `freezeCursor(false)` yalnızca gerçekten açıkken gönderilmeli (Görev 7 testi `resetEmitsFreezeOffOnlyWhenFrozen`).

---

### Görev 1: Paket iskeleti ve yerel araç zinciri

**Files:**
- Create: `Package.swift`, `Makefile`, `.swiftlint.yml`, `.swiftformat`, `LICENSE`, `README.md`, `CHANGELOG.md`, `scripts/install-hooks.sh`
- Create: `Sources/TrrekEngine/Version.swift`, `Sources/TrrekPlatform/PrivateSymbols.swift`, `Sources/Trrek/main.swift`, `Sources/TrrekProbe/main.swift`, `Tests/TrrekEngineTests/VersionTests.swift`
- Modify: `.gitignore` (ekle: `dist/`, `*.icns`, `*.iconset/`)

**Interfaces:**
- Produces: `public enum TrrekVersion { public static let string: String }` (TrrekEngine); hedef adları `TrrekEngine`, `TrrekPlatform`, `Trrek`, `TrrekProbe`, `TrrekEngineTests`; `make build|test|lint|format|check|hooks|clean`.

- [ ] **Step 1: Yerel araçları kur**

Run: `brew list swiftlint swiftformat >/dev/null 2>&1 || brew install swiftlint swiftformat`
Expected: `swiftlint version` ve `swiftformat --version` çıktı verir.

- [ ] **Step 2: Başarısız testi yaz** — `Tests/TrrekEngineTests/VersionTests.swift`

```swift
import Testing
@testable import TrrekEngine

@Test func versionStringIsSemver() {
    let parts = TrrekVersion.string.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
```

- [ ] **Step 3: Paket tanımını yaz** — `Package.swift`: tools 6.0; `platforms: [.macOS("26.0")]`; hedefler: `TrrekEngine` (target), `TrrekPlatform` (target, dependencies: TrrekEngine, linkerSettings: `.linkedFramework("AppKit")`, `.linkedFramework("IOKit")`, `.linkedFramework("CoreGraphics")`), `Trrek` (executableTarget, dependencies: TrrekPlatform), `TrrekProbe` (executableTarget, dependencies: TrrekPlatform), `TrrekEngineTests` (testTarget, dependencies: TrrekEngine). Tüm hedeflerde `swiftSettings: [.swiftLanguageMode(.v6)]`.

- [ ] **Step 4: Stub dosyaları yaz** — `Version.swift`: `public enum TrrekVersion { public static let string = "0.0.0" }`. `PrivateSymbols.swift`: `enum PrivateSymbols {}` (boş). `Trrek/main.swift`: `import AppKit` + `print("trrek \(TrrekVersion.string)")` (geçici). `TrrekProbe/main.swift`: `print("trrek-probe: no commands yet")`.

- [ ] **Step 5: Testi çalıştır**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 1 test passed`

- [ ] **Step 6: Lint ve format yapılandırması** — `.swiftformat`: `--swiftversion 6.0`, `--indent 4`, `--maxwidth 120`, `--exclude .build,dist`. `.swiftlint.yml`: `excluded: [.build, dist]`, `line_length: {warning: 120, error: 160}`, `disabled_rules: [todo]`, `opt_in_rules: [empty_count, closure_spacing]`, `identifier_name: {min_length: 2, excluded: [x, y, id, dx, dy, t, e]}`.

- [ ] **Step 7: Makefile** — hedefler: `build` (`swift build -c release --arch arm64`), `test` (`swift test`), `format` (`swiftformat .`), `lint` (`swiftformat --lint . && swiftlint lint --strict`), `check` (`test lint`), `hooks` (`scripts/install-hooks.sh`), `clean` (`rm -rf .build dist`). `.PHONY` tümü.

- [ ] **Step 8: Hook betiği** — `scripts/install-hooks.sh`: `.git/hooks/pre-push` (stdin'deki ref satırlarından biri `refs/heads/main`'e gidiyorsa `echo "direct push to main is blocked; open a PR"` ve `exit 1`) ve `.git/hooks/pre-commit` (`make lint`) yazar, `chmod +x`. Çalıştır: `make hooks`.

- [ ] **Step 9: Proje dosyaları** — `LICENSE` MIT (Copyright 2026 Burak Seyit Kara). `README.md`: ad, bir cümle, gereksinimler (macOS 26+, Apple Silicon), `make` hedefleri, "Development" bölümü. `CHANGELOG.md`: kısa bir açıklama başlığı ve `## [Unreleased]` altında `- Project scaffold: SPM package, Makefile, lint/format config, git hooks`.

- [ ] **Step 10: Tam kontrol**

Run: `make check`
Expected: testler geçer, `swiftformat --lint` ve `swiftlint` sıfır uyarı.

- [ ] **Step 11: Commit ve PR**

```bash
git add -A && git commit -m "chore: scaffold SPM package, Makefile, lint config and git hooks"
```
Dal `chore/scaffold`, PR başlığı aynı; CI henüz yok, merge inceleme sonrası.

---

### Görev 2: Paketleme betikleri ve CI/CD

**Files:**
- Create: `Resources/Info.plist.in`, `scripts/build-app.sh`, `scripts/render-icon.swift`, `scripts/make-icon.sh`, `scripts/perf.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/dependabot.yml`, `.github/PULL_REQUEST_TEMPLATE.md`
- Modify: `Makefile` (ekle: `app`, `install`, `icon`, `perf`), `CHANGELOG.md`

**Interfaces:**
- Consumes: Görev 1 hedef adları.
- Produces: `scripts/build-app.sh [--version X.Y.Z] [--build N]` → `dist/trrek.app`; `make app`, `make install`; CI workflow adı `ci`, iş adı `build-test`.

- [ ] **Step 1: Info.plist şablonu** — anahtarlar: `CFBundleIdentifier=com.burakseyitkara.trrek`, `CFBundleName=trrek`, `CFBundleDisplayName=trrek`, `CFBundleExecutable=trrek`, `CFBundlePackageType=APPL`, `CFBundleShortVersionString=${VERSION}`, `CFBundleVersion=${BUILD}`, `CFBundleIconFile=AppIcon`, `LSMinimumSystemVersion=26.0`, `LSUIElement=true`, `NSHumanReadableCopyright=Copyright © 2026 Burak Seyit Kara`, `NSPrincipalClass=NSApplication`.

- [ ] **Step 2: İkon üretimi** — `scripts/render-icon.swift` (`swift scripts/render-icon.swift <out.png>`): CoreGraphics ile 1024×1024, yuvarlatılmış kare koyu arka plan, ortada açık gri yuvarlatılmış trackpad silueti, sağ kenarında dikey parlak mavi şerit. `scripts/make-icon.sh <out.icns>`: PNG → `sips` ile 16…1024 boyutlar `trrek.iconset/` → `iconutil -c icns`.

- [ ] **Step 3: build-app.sh** — argümanlar `--version` (varsayılan `0.0.0`), `--build` (varsayılan `1`); `swift build -c release --arch arm64 --product Trrek`; `dist/trrek.app/Contents/{MacOS,Resources}`; ikili `trrek` adıyla; `Info.plist.in` → `sed`; `make-icon.sh` çıktısı Resources'a; `Sources/Trrek/Resources/*` varsa kopyala; `codesign --force --sign - --deep dist/trrek.app`; sonunda `codesign -dv` çıktısı.

- [ ] **Step 4: Makefile ekleri** — `app` (`scripts/build-app.sh --version $(VERSION) --build $(BUILD)`, varsayılan `VERSION=0.0.0 BUILD=1`), `install` (`app` sonra `rm -rf ~/Applications/trrek.app && cp -R dist/trrek.app ~/Applications/ && lsregister -f ~/Applications/trrek.app`), `icon`, `perf` (`scripts/perf.sh`).

- [ ] **Step 5: perf.sh** — `~/Applications/trrek.app` ya da `dist/trrek.app`'i açar, 30 s bekler, `ps -o %cpu=,rss= -p <pid>` ve `footprint <pid>` yazdırır, RSS 15360 KB üstündeyse `exit 1`.

- [ ] **Step 6: Yerel doğrulama**

Run: `make app && ls dist/trrek.app/Contents/MacOS && codesign -dv dist/trrek.app 2>&1 | head -3`
Expected: `trrek` ikilisi var; `Signature=adhoc`.

- [ ] **Step 7: ci.yml** — spec 10.3'e göre: `name: ci`; `on: pull_request: paths-ignore: ['docs/**', '**/*.md']`, `workflow_dispatch`; `concurrency` iptal; job `build-test`, `runs-on: macos-26`, `timeout-minutes: 20`; adımlar: `actions/checkout@v4`, `actions/cache@v4` (`path: .build`, `key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift','Package.resolved') }}`, `restore-keys: ${{ runner.os }}-swift-`), `swift build -c release --arch arm64`, `swift test`, `swiftformat --lint .`, `swiftlint lint --strict`, `scripts/build-app.sh --version 0.0.0 --build ${{ github.run_number }}`, `ditto -c -k --keepParent dist/trrek.app trrek-ci.zip`, `actions/upload-artifact@v4` (`name: trrek-app`, `retention-days: 7`).

- [ ] **Step 8: release.yml** — `on: push: tags: ['v*.*.*']`; `permissions: contents: write`; aynı derleme/test; `TAG=${GITHUB_REF_NAME}`; `scripts/build-app.sh --version ${TAG#v} --build ${{ github.run_number }}`; `ditto -c -k --keepParent dist/trrek.app trrek-${TAG}.zip`; `hdiutil create -volname trrek -srcfolder dist/trrek.app -ov -format UDZO trrek-${TAG}.dmg`; `gh release create "$TAG" --generate-notes trrek-${TAG}.zip trrek-${TAG}.dmg` (`GH_TOKEN: ${{ github.token }}`).

- [ ] **Step 9: dependabot ve PR şablonu** — `dependabot.yml`: `package-ecosystem: github-actions`, `directory: /`, `schedule.interval: weekly`. `PULL_REQUEST_TEMPLATE.md` (Türkçe): `## Özet`, `## Değişiklik türü` (Özellik/Düzeltme/CI/Belge/Test kutuları), `## Test notları`, `## Kontrol listesi` (`make check` geçti, `docs/testing.md` ilgili maddeler, perf etkisi yok, CHANGELOG güncellendi).

- [ ] **Step 10: Commit ve PR**

```bash
git add -A && git commit -m "ci: add app packaging scripts, CI and release workflows"
```
Dal `ci/packaging-and-workflows`. PR açıldıktan sonra `gh pr checks --watch` ile `build-test` yeşil olmalı; artifact `trrek-app` listelenmeli.

---

### Görev 3: Platform temeli ve TrrekProbe spike aracı

**Files:**
- Create: `Sources/CMultitouch/include/cmultitouch.h`, `Sources/CMultitouch/cmultitouch.c`
- Create: `Sources/TrrekPlatform/PrivateSymbols.swift` (yeniden yaz), `Sources/TrrekPlatform/Multitouch/MultitouchDevices.swift`, `Sources/TrrekPlatform/Multitouch/RawFrameStream.swift`, `Sources/TrrekPlatform/Haptics/ActuatorHaptics.swift`, `Sources/TrrekPlatform/Input/EventStamp.swift`, `Sources/TrrekPlatform/Input/MediaKeyPoster.swift`, `Sources/TrrekPlatform/Input/KeyPoster.swift`, `Sources/TrrekPlatform/Input/EventTapGuard.swift`, `Sources/TrrekPlatform/System/Permissions.swift`
- Create: `Sources/TrrekProbe/main.swift` (yeniden yaz), `Sources/TrrekProbe/Commands.swift`
- Modify: `Package.swift` (hedef `CMultitouch`, `TrrekPlatform` bağımlılığına ekle), `CHANGELOG.md`

**Interfaces:**
- Consumes: Görev 1 hedefleri.
- Produces (sonraki planda kullanılır):
  - C: `typedef struct { int32_t frame; double timestamp; int32_t identifier; int32_t state; int32_t fingerID; int32_t handID; float nx, ny, nvx, nvy; float total; float pressure; float angle; float majorAxis; float minorAxis; float ax, ay, avx, avy; int32_t reserved0, reserved1; float density; } MTTouch;` (`_Static_assert(sizeof(MTTouch) == 96, "MTTouch must be 96 bytes")`), `typedef void *MTDeviceRef;`, `typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch *, int32_t, double, int32_t);`
  - `enum PrivateSymbols` — `static let multitouch: MultitouchSymbols?`, `static let actuator: ActuatorSymbols?`; her struct ilgili `@convention(c)` fonksiyon işaretçilerini tutar.
  - `struct MultitouchDeviceInfo { let ref: MTDeviceRef; let isBuiltIn: Bool; let widthMM: Float; let heightMM: Float; let multitouchID: UInt64? }`
  - `enum MultitouchDevices { static func enumerate() -> [MultitouchDeviceInfo] }` (yüzey boyutunu `MTDeviceGetSensorSurfaceDimensions` ile alır, 1/100 mm → mm; `multitouchID` IORegistry `AppleMultitouchDevice` girdilerinin `Multitouch ID` ve `MT Built-In` özelliklerinden eşlenir)
  - `final class RawFrameStream { init(devices: [MultitouchDeviceInfo]); var onFrame: ((MTDeviceRef, UnsafeBufferPointer<MTTouch>, Double) -> Void)?; func start() throws; func stop() }` — callback framework thread'inde; `onFrame` `start()` öncesi atanır.
  - `final class ActuatorHaptics { init?(multitouchID: UInt64); @discardableResult func actuate(waveform: Int32) -> Bool }`
  - `enum EventStamp { static let userData: Int64 = 0x7472726B; static let source: CGEventSource; static func isOurs(_ event: CGEvent) -> Bool }`
  - `enum MediaKey: Int32 { soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7, play = 16, next = 17, previous = 18, illuminationUp = 21, illuminationDown = 22 }`; `enum MediaKeyPoster { static func post(_ key: MediaKey, fine: Bool) }`
  - `enum KeyPoster { static func press(keyCode: CGKeyCode, flags: CGEventFlags); static func modifierDown(_ keyCode: CGKeyCode, flags: CGEventFlags); static func modifierUp(_ keyCode: CGKeyCode) }`
  - `final class EventTapGuard { init(); var isAvailable: Bool; func setFreeze(_ on: Bool) }` (bu görevde yalnızca Tap B: mouseMoved/dragged/scrollWheel yutma)
  - `enum Permissions { static var isTrusted: Bool; static func prompt() }`

- [ ] **Step 1: C başlık hedefi** — `cmultitouch.h` yukarıdaki tipler + `_Static_assert`; `cmultitouch.c` tek bir boş fonksiyon (`void cmultitouch_anchor(void) {}`). `Package.swift`'e `.target(name: "CMultitouch")` ve `TrrekPlatform` bağımlılığı.

- [ ] **Step 2: Derleme doğrulaması**

Run: `swift build 2>&1 | tail -3`
Expected: hata yok (`_Static_assert` düzeni doğrular).

- [ ] **Step 3: PrivateSymbols** — `dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)`; `MultitouchSymbols` alanları: `createList: @convention(c) () -> Unmanaged<CFArray>?`, `isBuiltIn: (MTDeviceRef) -> Bool`, `surfaceDimensions: (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32`, `registerFrameCallback: (MTDeviceRef, MTFrameCallback) -> Void`, `unregisterFrameCallback`, `start: (MTDeviceRef, Int32) -> Int32`, `stop: (MTDeviceRef) -> Int32`, `release: (MTDeviceRef) -> Void`. `ActuatorSymbols`: `createFromDeviceID: (UInt64) -> Unmanaged<CFTypeRef>?`, `open: (CFTypeRef) -> Int32`, `actuate: (CFTypeRef, Int32, UInt32, Float, Float) -> Int32`, `close: (CFTypeRef) -> Int32`. Her sembol `dlsym` ile; biri eksikse struct `nil`. Sembol adları: `MTDeviceCreateList`, `MTDeviceIsBuiltIn`, `MTDeviceGetSensorSurfaceDimensions`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceRelease`, `MTActuatorCreateFromDeviceID`, `MTActuatorOpen`, `MTActuatorActuate`, `MTActuatorClose`.

- [ ] **Step 4: MultitouchDevices ve RawFrameStream** — Interfaces bloğundaki imzalar. Callback: dosya düzeyinde `private let frameCallback: MTFrameCallback = { dev, touches, count, ts, _ in RawFrameStream.current?.dispatch(dev, touches, count, ts) }`; `RawFrameStream.current` `nonisolated(unsafe) static weak var`. Birden fazla cihaz desteklenir.

- [ ] **Step 5: Haptik, olay gönderimi, tap, izin** — Interfaces bloğundaki imzalar; `MediaKeyPoster.post` spec 6.4'teki `NSEvent.otherEvent` + `data1 = (key << 16) | (0x0A << 8)` / `0x0B`; `fine` → `[.option, .shift]`; `KeyPoster` `CGEvent(keyboardEventSource: EventStamp.source, virtualKey:, keyDown:)`; `EventTapGuard` Tap B `.cgSessionEventTap/.headInsertEventTap/.defaultTap`, callback `EventStamp.isOurs` değilse ve freeze açıksa `nil` döner (yutar), `tapDisabledByTimeout` → yeniden etkinleştir; `Permissions.isTrusted = AXIsProcessTrusted()`, `prompt()` → `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)`.

- [ ] **Step 6: TrrekProbe komutları** — `trrek-probe <command>`: `devices` (her cihaz: built-in, W×H mm, multitouch ID); `frames [saniye]` (her karede: zaman, dokunma sayısı, her dokunma `id state nx ny major minor`; süre dolunca çıkar); `layout-check` (ilk 50 karede `nx,ny ∈ [0,1]`, `majorAxis ∈ (0,100)`, `state ∈ 0...7` ise `OK`, değilse `MISMATCH` ve `exit 1`; 10 s içinde dokunma yoksa `NO FRAMES`); `haptic <id> [tekrar]`; `key <soundUp|soundDown|brightnessUp|brightnessDown|mute|play|next|previous|illuminationUp|illuminationDown> [--fine]`; `switcher` (⌘ down, 500 ms, Tab, 500 ms, Tab, 500 ms, ⌘ up); `freeze <saniye>` (`EventTapGuard.setFreeze(true)`, bekle, kapat); `mem` (`task_info` ile kendi RSS'i MB). Yardım metni argümansız.

- [ ] **Step 7: Yerel doğrulama**

Run: `swift build && .build/debug/TrrekProbe devices && .build/debug/TrrekProbe layout-check`
Expected: en az bir cihaz, `built-in=true`, makul mm boyutları (örn. 120×80 civarı); `layout-check` → `OK` (parmak trackpad'e konulmalı).

- [ ] **Step 8: make check ve commit**

```bash
make check && git add -A && git commit -m "feat(platform): add private symbol loader, raw multitouch stream and probe tool"
```
Dal `feat/platform-probe`. PR; CI yeşil; inceleme; merge.

---

### Görev 3b: Spike sonuçları (ana oturum yürütür)

**Files:**
- Create: `docs/superpowers/specs/2026-11-03-spike-results.md`
- Modify: spec 5.2 eşikleri ve 6.3/6.7 kararları (gerekirse)

- [ ] **Step 1:** `TrrekProbe devices`, `layout-check`, `frames 5` çıktılarını kaydet (yüzey birimi, kalkma anında sıfır dokunmalı kare gelip gelmediği).
- [ ] **Step 2:** `haptic 1..6` sırayla; Light/Medium/Strong eşlemesini kaydet.
- [ ] **Step 3:** `key soundUp`, `key brightnessUp`, `key illuminationUp`, `key soundUp --fine`; her birinden hemen sonra `screencapture -x` ile ekran görüntüsü alıp HUD'un görünüp görünmediğini kaydet (6.7 Yol A/B kararı, 11. madde 4–5).
- [ ] **Step 4:** `switcher` (seçici açılıyor mu), `freeze 3` (imleç duruyor mu), `mem` (RSS).
- [ ] **Step 5:** Sonuç belgesini yaz; eşik ya da karar değişiyorsa spec'i aynı PR'da güncelle. Dal `docs/spike-results`.

---

### Görev 4: Engine tipleri, yapılandırma ve geometri

**Files:**
- Create: `Sources/TrrekEngine/Types.swift`, `Sources/TrrekEngine/Config.swift`, `Sources/TrrekEngine/Commands.swift`, `Sources/TrrekEngine/Geometry.swift`
- Create: `Tests/TrrekEngineTests/Support/FrameBuilder.swift`, `Tests/TrrekEngineTests/Support/RecordingSink.swift`, `Tests/TrrekEngineTests/GeometryTests.swift`, `Tests/TrrekEngineTests/TouchBufferTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Produces (spec 5.1, 5.2, 5.7'deki tipler, hepsi `public`, `Sendable`, `Equatable`):
  - `struct Touch { var id: Int32; var x: Float; var y: Float; var majorAxisMM: Float; init(id:x:y:majorAxisMM:) }`
  - `struct TouchBuffer { static let capacity = 16; private(set) var count: Int; init(); @discardableResult mutating func append(_: Touch) -> Bool; subscript(_ i: Int) -> Touch; func contains(id: Int32) -> Bool; func touch(id: Int32) -> Touch? }` — depolama `InlineArray<16, Touch>`.
  - `struct DeviceGeometry { var widthMM: Float; var heightMM: Float; var isBuiltIn: Bool; var isValid: Bool { widthMM > 0 && heightMM > 0 } }`
  - `struct Frame { var deviceID: UInt64; var timestamp: TimeInterval; var geometry: DeviceGeometry; var touches: TouchBuffer }`
  - `enum Edge: CaseIterable { left, right, top, bottom }`, `enum Corner: CaseIterable { topLeft, topRight, bottomLeft, bottomRight }`, `enum Zone { edge(Edge), corner(Corner), none }`
  - `enum EdgeAction: String, CaseIterable, Codable`, `enum CornerAction: String, CaseIterable, Codable` (spec 5.2)
  - `struct Thresholds { … spec 5.2 alanları ve varsayılanları; init() }`
  - `struct EngineConfig { left, right, top, bottom: EdgeAction; topLeft, topRight, bottomLeft, bottomRight: CornerAction; bottomQuarterOnly, precision, freezeCursor, middleClickEnabled, holdKeyRequired: Bool; thresholds: Thresholds; init(); func action(for: Edge) -> EdgeAction; func action(for: Corner) -> CornerAction }`
  - `enum HapticEvent { start, step, tap, limit }`, `enum GestureCommand` (spec 5.7), `protocol CommandSink: AnyObject { func handle(_ command: GestureCommand, device: UInt64) }`
  - `enum Geometry { static func zone(of: Touch, in: DeviceGeometry, config: EngineConfig) -> Zone; static func deltaMM(edge: Edge, from: Touch, to: Touch, in: DeviceGeometry) -> (along: Float, perpendicular: Float); static func stepMM(for: EdgeAction, thresholds: Thresholds) -> Float; static func edges(of: Corner) -> (vertical: Edge, horizontal: Edge) }`
  - Test yardımcıları: `struct FrameBuilder { var geometry = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true); var deviceID: UInt64 = 1; func frame(t: TimeInterval, _ touches: [(id: Int32, xMM: Float, yMM: Float)], major: Float = 8) -> Frame }` (mm → normalize); `final class RecordingSink: CommandSink { var commands: [GestureCommand]; func count(_: GestureCommand) -> Int; func contains(_: GestureCommand) -> Bool }`.

- [ ] **Step 1: Başarısız testler** — `GeometryTests.swift`:

```swift
@Test func rightStripDetectedWithStandardWidth() {
    let g = DeviceGeometry(widthMM: 120, heightMM: 80, isBuiltIn: true)
    let cfg = EngineConfig()
    #expect(Geometry.zone(of: Touch(id: 1, x: 115/120, y: 40/80, majorAxisMM: 8), in: g, config: cfg) == .edge(.right))
    #expect(Geometry.zone(of: Touch(id: 1, x: 100/120, y: 40/80, majorAxisMM: 8), in: g, config: cfg) == .none)
}
@Test func cornerIsIntersectionOfStrips() { /* x=115, y=5 → .corner(.bottomRight) */ }
@Test func offEdgeIsNotAZone() { /* cfg.top = .off; x=60, y=78 → .none */ }
@Test func bottomQuarterOnlyLimitsVerticalEdges() { /* bottomQuarterOnly; x=115,y=40 → .none; y=15 → .edge(.right) */ }
@Test func edgeWidthNarrowAndWide() { /* edgeWidthMM 7: x=112 → .none; 14: x=112 → .edge(.right) */ }
@Test func zeroGeometryYieldsNoZone() { /* widthMM 0 → .none */ }
@Test func deltaAlongVerticalEdgeIsPositiveUpward() { /* right edge, y 15→35 mm → along == 20, perpendicular == 0 */ }
@Test func stepDistancesFollowThresholds() { /* volume 3.75, switchApps 12, scrubVideo 6, media 20 */ }
```
`TouchBufferTests.swift`: `bufferRejectsSeventeenthTouch` (16 append → true, 17. → false, count 16), `bufferLookupByID`.

- [ ] **Step 2: Testleri çalıştır** — Run: `swift test 2>&1 | tail -3` — Expected: derleme hatası (tipler yok).

- [ ] **Step 3: Tipleri, yapılandırmayı, komutları ve geometriyi yaz** — Interfaces bloğundaki imzalar; `zone(of:)`: geometri geçersizse `.none`; önce kenar şeritleri hesaplanır (`off` eylemli kenar şerit sayılmaz), iki şerit kesişiyorsa `.corner`, biri ise `.edge`, `bottomQuarterOnly` ve dikey kenar için `y ≥ 0.25` ise `.none`.

- [ ] **Step 4: Testleri çalıştır** — Run: `swift test 2>&1 | tail -3` — Expected: tüm testler geçer.

- [ ] **Step 5: CHANGELOG** — `- Engine: core types, configuration, command model and edge/corner geometry`.

- [ ] **Step 6: Commit ve PR** — `make check && git commit -am "feat(engine): add types, config, commands and geometry"`; dal `feat/engine-types`.

---

### Görev 5: Kaydırma durum makinesi

**Files:**
- Create: `Sources/TrrekEngine/GestureEngine.swift`, `Sources/TrrekEngine/EngineState.swift`
- Create: `Tests/TrrekEngineTests/SlideTests.swift`, `Tests/TrrekEngineTests/Support/Drive.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Görev 4 tipleri.
- Produces: `public final class GestureEngine { init(config: EngineConfig, sink: CommandSink); func update(config: EngineConfig); func process(_ frame: Frame); func tick(now: TimeInterval); func noteKeyDown(at: TimeInterval); func setHoldKeySatisfied(_: Bool); func setPaused(_: Bool); func reset(); var stateKind: StateKind }`, `public enum StateKind { idle, candidate, sliding, lost, spent, threeFinger }`. İç durum `enum EngineState` (spec 5.4 verileriyle). Bu görevde `noteKeyDown`, `setHoldKeySatisfied`, `setPaused` gövdeleri yalnızca alan atar (Görev 7 tamamlar); tap/üç parmak geçişleri Görev 6'da.
- Test yardımcısı: `extension GestureEngine { @discardableResult func drive(_ fb: FrameBuilder, id: Int32, from: (Float, Float), to: (Float, Float), stepMM: Float = 1, dt: TimeInterval = 0.008, startT: TimeInterval) -> TimeInterval }` — `from`'dan `to`'ya `stepMM` adımlarla kareler üretir, son zamanı döner.

- [ ] **Step 1: Başarısız testler** — `SlideTests.swift`:

```swift
@Test func sixteenStepsForSixtyMillimetres() {
    let sink = RecordingSink(); let e = GestureEngine(config: EngineConfig(), sink: sink); let fb = FrameBuilder()
    e.drive(fb, id: 1, from: (115, 15), to: (115, 75), startT: 0)
    #expect(sink.count(.stepVolume(1, fine: false)) == 16)
    #expect(sink.count(.haptic(.step)) == 16)
    #expect(sink.count(.haptic(.start)) == 1)
}
@Test func belowSlideStartNoCommands() { /* 115,15 → 115,17.5; hiçbir step yok; stateKind == .candidate */ }
@Test func downwardSlideEmitsNegativeSteps() { /* 115,75 → 115,15 → 16 × stepVolume(-1) */ }
@Test func precisionSetsFineFlag() { /* cfg.precision = true → stepVolume(1, fine: true) */ }
@Test func perpendicularMoveAbortsCandidate() { /* 115,40 → 110,40 (5 mm dik) → .spent; sonra 110,40 → 110,70 hiçbir komut */ }
@Test func secondFingerCancelsSlide() { /* slide ortasında id 2 eklenir → stateKind .spent, freezeCursor(false), sonra her iki parmak kalkınca .idle */ }
@Test func lostFingerReturnsWithinTimeoutContinues() { /* 20 mm slide; boş kare t; aynı id t+0.17 → devam, ek adımlar sayılır; freezeCursor(false) henüz yok */ }
@Test func lostFingerExpiresCommits() { /* boş kare t; boş kare t+0.181 → .idle ve freezeCursor(false) bir kez */ }
@Test func watchdogTickCommits() { /* slide; tick(now: last + 0.181) → .idle, freezeCursor(false) */ }
@Test func backwardsTimestampDoesNotCommit() { /* slide; tick(now: last - 1) → hâlâ .sliding, komut yok */ }
@Test func reusedIDAfterLostExpiryStartsFresh() { /* lost dolduktan sonra aynı id 115,15'te → .candidate, step yok */ }
@Test func switchAppsStepsAndCommit() { /* top edge: 30,78 → 54,78 → 2 × appSwitchStep(1); kalkıp 181 ms → appSwitchCommit */ }
@Test func switchAppsSecondFingerCancels() { /* appSwitchCancel */ }
@Test func scrubStepsAndCommit() { /* cfg.top = .scrubVideo; 12 mm → 2 × scrubStep(1); commit */ }
@Test func updateConfigDuringSlideCommits() { /* sliding; update(config:) → .idle, freezeCursor(false); switchApps ise appSwitchCommit */ }
@Test func frameFromOtherDeviceIgnoredWhileSliding() { /* deviceID 2 kareleri durumu değiştirmez */ }
@Test func freezeCursorEmittedOncePerSlide() { /* freezeCursor(true) 1, (false) 1 */ }
@Test func freezeCursorDisabledInConfigEmitsNothing() { /* cfg.freezeCursor = false → freezeCursor komutu yok */ }
@Test func cornerCandidateBindsToVerticalEdgeOnVerticalMove() { /* 115,5 → 115,40 → stepVolume adımları */ }
```

- [ ] **Step 2: Çalıştır** — Expected: derleme hatası (`GestureEngine` yok).

- [ ] **Step 3: Durum makinesini yaz** — spec 5.4 geçişleri (1–4 ve `spent` → tüm parmaklar kalkınca `idle`); `sliding` girişinde `accumulatedMM` başlangıç mesafesini içerir; adım döngüsü `while abs(acc) >= step`; `bitir(commit/cancel)` spec'teki komutlar; `lost` hem kareyle hem `tick` ile dolar; `tick(now:)` `now < lastFrameTime` ise hiçbir şey yapmaz; `update(config:)` sliding'de commit sonra config'i değiştirir; `reset()` idle'a döner. Heap ayırma yok (enum durumları değer tipi).

- [ ] **Step 4: Çalıştır** — Run: `swift test 2>&1 | tail -3` — Expected: hepsi geçer.

- [ ] **Step 5: Commit ve PR** — `make check && git commit -am "feat(engine): add slide state machine with lost-finger recovery and watchdog"`; dal `feat/engine-slide`; CHANGELOG satırı.

---

### Görev 6: Dokunmalar: köşe çift dokunma, medya çift dokunma, üç parmak orta tık

**Files:**
- Modify: `Sources/TrrekEngine/GestureEngine.swift`, `Sources/TrrekEngine/EngineState.swift`
- Create: `Tests/TrrekEngineTests/TapTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Görev 5 `GestureEngine`.
- Produces: spec 5.4 `candidate` tap dalı, `spent`/`idle` → `threeFinger` geçişleri; `EngineState` içinde `lastTap: (corner: Corner?, edge: Edge?, at: TimeInterval)?`.

- [ ] **Step 1: Başarısız testler** — `TapTests.swift`:

```swift
@Test func plainEdgeTapEmitsNothing() { /* 115,40 iner, 0.1 s sonra kalkar → komut yok, .idle */ }
@Test func cornerDoubleTapWithinWindowMutes() { /* cfg.bottomRight = .mute; iki tap 0.3 s ara → mute 1, haptic(.tap) 1 */ }
@Test func cornerDoubleTapOutsideWindowDoesNothing() { /* 0.36 s ara → mute 0 */ }
@Test func cornerDoubleTapOffDoesNothing() { /* varsayılan off → komut yok */ }
@Test func screenshotCornerEmitsScreenshot() { /* cfg.topLeft = .screenshot */ }
@Test func mediaEdgeDoubleTapPlaysPauses() { /* cfg.bottom = .media; 60,5 iki tap → mediaPlayPause 1 */ }
@Test func mediaEdgeSlideSkipsTrack() { /* 20 mm sağa → mediaNext 1; sola → mediaPrevious */ }
@Test func threeFingerTapEmitsMiddleClick() { /* middleClickEnabled; üç parmak aynı karede 0.05 s; kalkınca middleClick 1, haptic(.tap) 1 */ }
@Test func threeFingerStaggeredLandingStillCounts() { /* id1 t=0, id2 t=0.03, id3 t=0.06 (hepsi bölge dışı); kalkınca middleClick */ }
@Test func threeFingerDisabledDoesNothing() { }
@Test func threeFingerMovementCancels() { /* bir parmak 3 mm hareket → middleClick 0 */ }
@Test func threeFingerTooLongCancels() { /* 0.35 s basılı → 0 */ }
@Test func fourthFingerCancels() { }
```

- [ ] **Step 2: Çalıştır** — Expected: ilgili testler başarısız.

- [ ] **Step 3: Geçişleri yaz** — spec 5.4 `candidate` kalkma dalı (süre `max(0, t − t0)`), `lastTap` ile çift dokunma, `idle`/`candidate`/`spent` → `threeFinger` (ilk iniş zamanı `spent` verisinde), `threeFinger` çıkışları.

- [ ] **Step 4: Çalıştır** — Expected: hepsi geçer; Görev 5 testleri hâlâ geçer.

- [ ] **Step 5: Commit ve PR** — `feat(engine): add corner and media double-taps and three-finger middle click`; dal `feat/engine-taps`.

---

### Görev 7: Kapılar ve yapılandırma güncellemeleri

**Files:**
- Modify: `Sources/TrrekEngine/GestureEngine.swift`
- Create: `Tests/TrrekEngineTests/GateTests.swift`
- Modify: `CHANGELOG.md`, `README.md` (Engine bölümü: kurallar özeti)

**Interfaces:**
- Consumes: Görev 6 `GestureEngine`.
- Produces: `noteKeyDown(at:)`, `setHoldKeySatisfied(_:)`, `setPaused(_:)` tam davranış (spec 5.6); avuç filtresi `process` girişinde.

- [ ] **Step 1: Başarısız testler** — `GateTests.swift`:

```swift
@Test func palmTouchIsFiltered() { /* major 21 → zone yok, step yok; major 19 → slide çalışır */ }
@Test func palmAlongsideFingerDoesNotCancelSlide() { /* id1 parmak slide + id2 major 30 → slide sürer */ }
@Test func typingGateBlocksNewGesture() { /* noteKeyDown(at: 0); kareler 0.1'de → step yok; 0.5'te başlayan slide çalışır */ }
@Test func typingDoesNotStopActiveSlide() { /* slide ortasında noteKeyDown → adımlar sürer */ }
@Test func holdKeyRequiredBlocksWithoutKey() { /* holdKeyRequired, satisfied false → step yok; true → çalışır */ }
@Test func releasingHoldKeyCommitsSlide() { /* sliding; setHoldKeySatisfied(false) → .idle, freezeCursor(false) */ }
@Test func pausedIgnoresFrames() { /* setPaused(true) → step yok */ }
@Test func pausingEndsActiveSlide() { /* sliding; setPaused(true) → .idle, freezeCursor(false), switchApps ise commit */ }
@Test func swappedSidesChangeCommandType() { /* cfg.right = .brightness → stepBrightness */ }
@Test func resetEmitsFreezeOffOnlyWhenFrozen() { /* idle'da reset → komut yok; sliding'de reset → freezeCursor(false) 1 */ }
```

- [ ] **Step 2: Çalıştır** — Expected: ilgili testler başarısız.

- [ ] **Step 3: Kapıları yaz** — spec 5.6 sırası; avuç filtresi `TouchBuffer`'dan yeni bir buffer'a kopyalayarak (stack, heap yok).

- [ ] **Step 4: Çalıştır** — Run: `swift test 2>&1 | tail -3` — Expected: toplam ≥ 55 test geçer.

- [ ] **Step 5: README Engine bölümü** — kuralların bir paragraf özeti ve `swift test` komutu.

- [ ] **Step 6: Commit ve PR** — `feat(engine): add palm, typing, hold-key and pause gates`; dal `feat/engine-gates`. Merge sonrası `make check` main'de yeşil; CHANGELOG'da Engine satırları tam.

---

## Öz denetim notları

- Spec kapsamı: Bölüm 4 (paket) → Görev 1; 7.8 ve 10.x → Görev 2; 6.1, 6.2 (ham kısım), 6.3, 6.4, 6.5 (Tap B), 6.6 (KeyPoster), 6.10 (Permissions) → Görev 3; 11 Aşama 0 → Görev 3b; 5.1–5.3, 5.7 → Görev 4; 5.4 (1–4), 5.5, 5.8 → Görev 5; 5.4 (tap, 5, 6) → Görev 6; 5.6 → Görev 7. Spec 9.1'deki 26 testin tamamı Görev 4–7 test listelerinde; Review Focus'un 5 testi Görev 4, 5 ve 7'de.
- Sonraki plan: Platform'un kalan köprüleri (6.5 Tap A, 6.7, 6.10 kalanı), `Coordinator`, menü, ayar penceresi, karşılama, overlay, `docs/testing.md`, perf ölçümü ve `v0.1.0`.
