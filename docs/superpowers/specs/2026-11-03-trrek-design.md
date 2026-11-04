# trrek — Tasarım Spesifikasyonu

Tarih: 2026-11-03 · Durum: onaylandı (otonom yürütme)

## 1. Amaç ve kapsam

**trrek**, macOS'ta trackpad kenarlarını ve köşelerini tek parmaklı kontrollere çeviren, menü çubuğunda yaşayan bir uygulamadır. Kişisel kullanım içindir, ücretsizdir ve bu depoda sıfırdan yazılır.

**Ürün tanımı**
- Sağ kenar, yukarı/aşağı kaydır → ses. Sol kenar → ekran parlaklığı (harici ekranlarda DDC/CI ile, isteğe bağlı).
- Üst kenar, sola/sağa kaydır → uygulama değiştirme (sistemin ⌘-Tab seçicisi sürülür). Alt kenar → klavye arka ışığı; arka ışığı olmayan Mac'te medya.
- Üst ve alt kenar için seçenekler: Switch Apps, Scrub Video, Keyboard Backlight, Media, Off.
- Köşelere çift dokunma → Off, Mute ya da Screenshot (⌘⇧5). Üç parmak dokunma → orta tık (isteğe bağlı).
- Her adımda haptik tık (Off/Light/Medium/Strong), sistemin kendi ses/parlaklık HUD'u, kaydırırken sabit imleç, hassas mod (çeyrek adım), kenar genişliği (Narrow/Standard/Wide), alt çeyrek modu, taraf değiştirme, Hold-to-Slide tuşu (Hold/Toggle), uygulama bazlı duraklatma, avuç reddi, yazarken yok sayma, uyku sonrası kendiliğinden toparlanma, girişte açılma.
- Ayarlar ve karşılama için macOS 26 Liquid Glass tasarım dilinde SwiftUI pencereleri; menü çubuğunda hızlı anahtarlar.

**Hedefler**
- Minimum kaynak tüketimi: boşta %0 CPU, 15 MB altı bellek, kare başına sabit zamanlı iş, heap ayırma yok.
- Donanımsız CI'da test edilebilen jest motoru.
- Xcode gerektirmeyen derleme (Swift Package Manager + betik).
- Baştan sona PR ve CI disipliniyle, otonom yürütülen profesyonel geliştirme süreci.

**Kapsam dışı:** Lisans, deneme, ödeme ve otomatik güncelleme mekanizmaları; web sitesi; notarizasyon; Intel; macOS 26 öncesi.

**Başarı ölçütleri**
1. Bu Mac'te (MacBook Air M4, macOS 27.2) dört kenar, dört köşe ve üç parmak orta tık tanımlandığı gibi çalışır; ses ve parlaklıkta sistem HUD'u görünür; her adımda haptik tık hissedilir.
2. `make perf` boşta 0 CPU ve 15 MB altı bellek raporlar.
3. Engine testleri Bölüm 5'teki her kuralı kapsar ve CI'da geçer.
4. `make install` ile uygulama ~/Applications'a kurulur, girişte açılır; ayar penceresi ve karşılama Liquid Glass görünümündedir.
5. Her değişiklik PR, CI ve inceleme adımlarından geçerek main'e girer; `v0.1.0` etiketi Release olarak DMG üretir.

## 2. Ortam ve kısıtlar

| Konu | Değer |
|---|---|
| Geliştirme makinesi | MacBook Air M4, macOS 27.2, Force Touch trackpad (Multitouch ID <multitouch-id>), klavye arka ışığı var, yalnızca dahili ekran |
| Araçlar | Command Line Tools, Swift 6.4.2, Homebrew; Xcode yok |
| CI runner | `macos-26` imajı: macOS 26.6.1, Xcode 26.6, SwiftLint 0.65, SwiftFormat 0.62 |
| Swift uyumu | `swift-tools-version: 6.0`, dil modu Swift 6; Swift 6.3+ dil özellikleri ve macOS 27 API'leri kullanılmaz |
| Hedef platform | macOS 26.0+, yalnızca arm64 |
| GitHub | Private depo `burakseyitkara1/trrek`, Free plan. Private depoda ruleset/dal koruması sunucu tarafında yok; zorlama yerel araçlarla (Bölüm 10) |
| macOS runner bütçesi | Ayda ~200 macOS dakikası (2000 × 1/10). CI yalnızca PR'larda ve sürüm etiketlerinde çalışır; tur hedefi 4 dk altı |
| Private API | MultitouchSupport, CoreBrightness, IOAVService, MediaRemote. Sandbox kapalı. Her sembol `dlsym` ile çözülür; yoksa özellik kapanır |

## 3. Mimari genel bakış

Üç katman, tek süreç, tek yönlü bağımlılık:

```
Trrek (AppKit + SwiftUI)  →  TrrekPlatform (private API köprüleri)  →  TrrekEngine (saf Swift)
```

- **TrrekEngine** sistem çağrısı yapmaz. `Frame` alır, `GestureCommand` üretir. Yalnızca Foundation'a ve kendi kilidi için `os` modülüne bağlıdır.
- **TrrekPlatform** Engine'in protokollerini gerçek API'lerle uygular: multitouch kaynağı, haptik, tuş ve fare olayı gönderimi, event tap, klavye ışığı, DDC, Now Playing, sistem bildirimleri.
- **Trrek** ikisini bağlar: ayarlar, menü, ayar penceresi, overlay, karşılama, izinler, yaşam döngüsü.

**Thread modeli**
- Multitouch kareleri framework'ün kendi arka plan thread'inde gelir. Platform katmanı kareyi stack üzerinde `Frame`'e çevirir ve Engine'i senkron çağırır.
- Engine'in her public metodu (`process`, `tick`, `update`, host sinyalleri, `reset`, `stateKind`) Engine'in kendi `OSAllocatedUnfairLock`'u altında çalışır; farklı thread'lerden gelen çağrılar bu kilitle sıraya girer. Host'un ayrıca kendi kilidini tutması sorun değildir. Sink kilit tutulurken çağrılır ve Engine'e geri çağrı yapmamalıdır.
- Saat sözleşmesi: Engine'deki tüm zamanlar sistem uptime saniyesidir (`ProcessInfo.processInfo.systemUptime`, `Frame.timestamp` ile aynı saat). CGEvent zaman damgaları 1e9'a bölünerek verilir.
- Engine komutları senkron bir sink'e verir. Sink; CGEvent gönderimi, haptik ve tap aç/kapa işlemlerini aynı thread'de yapar (hepsi thread-safe). Menü ve overlay güncellemeleri `DispatchQueue.main.async` ile ana thread'e gider.
- Event tap callback'leri ana run loop'ta çalışır ve host sinyallerini (`noteKeyDown`, `setHoldKeySatisfied`) çağırır; bu çağrılar Engine'in kendi kilidiyle karelerle sıraya girer.
- Periyodik zamanlayıcı yoktur. İki tek seferlik zamanlayıcı vardır: slide watchdog (slide sürerken, her karede yeniden kurulur) ve overlay gizleme (overlay görünürken).
- Slide sürerken `ProcessInfo.beginActivity(.userInitiated)` tutulur; bitince bırakılır. Boşta App Nap'e izin verilir.
- SwiftUI pencereleri (Settings, Welcome) yalnızca açıkken bellekte bulunur; kapanınca hosting controller ve pencere serbest bırakılır.

## 4. Paket yapısı

```
trrek/
├── Package.swift
├── Makefile · CLAUDE.md · README.md · CHANGELOG.md · LICENSE (MIT)
├── .swiftlint.yml · .swiftformat
├── Sources/
│   ├── TrrekEngine/
│   │   ├── Types.swift          # Touch, Frame, TouchBuffer, DeviceGeometry, Edge, Corner, Zone
│   │   ├── Config.swift         # EngineConfig, Thresholds, EdgeAction, CornerAction
│   │   ├── Commands.swift       # GestureCommand, HapticEvent, CommandSink
│   │   ├── Geometry.swift       # bölge tespiti, mm dönüşümleri
│   │   └── GestureEngine.swift  # durum makinesi
│   ├── TrrekPlatform/
│   │   ├── PrivateSymbols.swift # tüm dlopen/dlsym tanımları, tek dosya
│   │   ├── Multitouch/MultitouchSource.swift
│   │   ├── Haptics/ActuatorHaptics.swift
│   │   ├── Input/MediaKeyPoster.swift · KeyPoster.swift · MousePoster.swift · EventTapGuard.swift · EventStamp.swift
│   │   ├── Keyboard/KeyboardBacklight.swift
│   │   ├── Display/ExternalBrightness.swift · DisplayLocator.swift      (Aşama 2)
│   │   ├── Media/NowPlayingBridge.swift + Resources/nowplaying-helper   (Aşama 2)
│   │   └── System/FrontmostObserver.swift · WakeObserver.swift · Permissions.swift · LaunchAtLogin.swift
│   ├── Trrek/
│   │   ├── main.swift · AppDelegate.swift · Coordinator.swift
│   │   ├── Settings.swift · SettingsStore.swift
│   │   ├── Menu/StatusMenu.swift
│   │   ├── UI/SettingsWindow.swift · SettingsView.swift · EdgesTab.swift · CornersTab.swift · GeneralTab.swift · AdvancedTab.swift
│   │   ├── UI/TrackpadDiagram.swift · WelcomeWindow.swift · WelcomeView.swift · OverlayPanel.swift · OverlayView.swift
│   │   └── Resources/MenuIcon.pdf
│   └── TrrekProbe/main.swift    # geliştirme aracı, .app'e girmez
├── Tests/TrrekEngineTests/
├── Resources/AppIcon.icns · Info.plist.in · icon-1024.png
├── scripts/build-app.sh · make-icon.sh · install-hooks.sh · perf.sh
├── docs/superpowers/specs/ · docs/superpowers/plans/ · docs/testing.md
└── .github/workflows/ci.yml · release.yml · dependabot.yml · PULL_REQUEST_TEMPLATE.md
```

`Package.swift`: platform `.macOS("26.0")`; hedefler `TrrekEngine` (library), `TrrekPlatform` (library, bağımlılık Engine), `Trrek` (executable, bağımlılık Platform), `TrrekProbe` (executable, bağımlılık Platform), `TrrekEngineTests` (test, Swift Testing). Harici paket bağımlılığı yok. Private framework'ler bağlanmaz, çalışma zamanında `dlopen` edilir.

## 5. TrrekEngine

### 5.1 Veri tipleri

```swift
public struct Touch { id: Int32; x: Float; y: Float; majorAxisMM: Float }   // x,y normalize 0...1, orijin sol alt
public struct TouchBuffer { count: Int; storage: (Touch × 16) }               // sabit kapasite, heap yok
public struct DeviceGeometry { widthMM: Float; heightMM: Float; isBuiltIn: Bool }
public struct Frame { deviceID: UInt64; timestamp: TimeInterval; geometry: DeviceGeometry; touches: TouchBuffer }
public enum Edge { left, right, top, bottom }
public enum Corner { topLeft, topRight, bottomLeft, bottomRight }
public enum Zone { edge(Edge), corner(Corner), none }
```

Platform, yalnızca temas halindeki dokunmaları `Frame`'e koyar. Bir id'nin kareden kaybolması kalkma demektir. 16'dan fazla dokunma kırpılır.

### 5.2 Yapılandırma

```swift
public enum EdgeAction { volume, brightness, switchApps, scrubVideo, keyboardBacklight, media, off }
public enum CornerAction { off, mute, screenshot }
public struct Thresholds {           // başlangıç değerleri; Aşama 0 spike'ında ayarlanır
  edgeWidthMM: Float = 10            // Narrow 7 · Standard 10 · Wide 14
  slideStartMM: Float = 3            // kenar ekseni boyunca
  abortPerpendicularMM: Float = 4    // slide başlamadan kenara dik bu kadar hareket → Spent
  stepMM: Float = 3.75               // volume, brightness, keyboardBacklight (16 adım ≈ 60 mm)
  appSwitchStepMM: Float = 12
  scrubStepMM: Float = 6             // adım = 5 saniye
  mediaSkipStepMM: Float = 20
  tapMaxDuration: TimeInterval = 0.25
  tapMaxMoveMM: Float = 2
  doubleTapWindow: TimeInterval = 0.35
  lostTimeout: TimeInterval = 0.18
  threeFingerSettle: TimeInterval = 0.10
  threeFingerMaxDuration: TimeInterval = 0.30
  palmMajorAxisMM: Float = 20
  typingGate: TimeInterval = 0.40
}
public struct EngineConfig {
  left, right, top, bottom: EdgeAction      // varsayılan: brightness, volume, switchApps, keyboardBacklight
  topLeft, topRight, bottomLeft, bottomRight: CornerAction   // varsayılan: off
  bottomQuarterOnly: Bool = false
  precision: Bool = false
  freezeCursor: Bool = true
  middleClickEnabled: Bool = false
  holdKeyRequired: Bool = false
  thresholds: Thresholds
}
```

Swap Sides, uygulama katmanında `left`/`right` eylemlerini değiştirerek uygulanır; Engine ayrı bir bayrak tutmaz. (Aşama 3'te Swap Sides kalktı ve eylem listeleri genişledi; bkz. 5.9.)

### 5.3 Geometri

- mm dönüşümü: `dxMM = Δx · widthMM`, `dyMM = Δy · heightMM`.
- Kenar şeritleri: `left: x·W < w`, `right: (1−x)·W < w`, `bottom: y·H < w`, `top: (1−y)·H < w` (w = edgeWidthMM).
- Köşe: iki şeridin kesişimi; her zaman `corner` bölgesidir. Köşede başlayan parmak hareket eksenine göre komşu kenara bağlanır (5.4); köşe eylemi Off ise çift dokunma hiçbir şey yapmaz.
- `bottomQuarterOnly` açıkken sol/sağ şeritleri yalnızca `y < 0.25` iken kenar bölgesi üretir. Seçenek yalnızca dikey kenar slide'larını kısıtlar, köşe algılamayı değil: `y ≥ 0.25`'te dikey şerit yatay şeritle yine köşe oluşturur. Böyle bir köşe adayı dikey kenara bağlanırsa (`y0 ≥ 0.25`) slide başlamaz, aday `spent`'e gider; yatay kenara bağlanma etkilenmez.
- Eylemi `off` olan kenarlar düz kenar bölgesi sayılmaz. Şeritler geometriyle belirlenir; iki şeridin kesişimi, kenarlarından biri ya da ikisi `off` olsa da köşe kalır (çift dokunması çalışır, `off` kenara doğru slide başlamaz; karar 48).
- Kenar ekseni ve yön: left/right → y ekseni, yukarı = +1. top/bottom → x ekseni, sağa = +1.

### 5.4 Durum makinesi

Tek durum, tüm cihazlar için ortak. `Idle` dışında bir durumdayken başka cihazdan gelen kareler yok sayılır.

| Durum | Veri |
|---|---|
| `idle` | — |
| `candidate` | zone, touchID, x0, y0, t0 |
| `sliding` | edge, action, touchID, origin (mm), accumulatedMM, stepsEmitted, lastFrameTime |
| `lost` | sliding verisi, since |
| `spent` | firstDownTime, başlangıç konumları |
| `threeFinger` | ids[3], tDown, maxMoveMM |

Geçişler (kare başına; kapılar Bölüm 5.6'daki sırayla önce uygulanır):

1. **idle**
   - 1 dokunma, bölge ≠ none → `candidate`.
   - 3 dokunma, hepsi `threeFingerSettle` içinde inmiş, `middleClickEnabled` → `threeFinger`.
   - 1 dokunma, bölge = none ya da 2 dokunma → `spent` (ilk iniş zamanı ve başlangıç konumları saklanır).
2. **candidate**
   - dokunma sayısı ≠ 1 → `spent` (3'e çıkarsa `spent`'teki üç parmak kuralı aynı karede uygulanır).
   - kenar ekseni boyunca |Δ| ≥ `slideStartMM` → `sliding`; emit `freezeCursor(true)` (config.freezeCursor ise) ve `haptic(.start)`. Zone köşe ise kenar hareket eksenine göre seçilir: yatay hareket → o köşenin top/bottom kenarı, dikey hareket → left/right kenarı; seçilen kenarın eylemi `off` ise `spent`.
   - dik eksende |Δ| ≥ `abortPerpendicularMM` → `spent`.
   - kalkma, süre ≤ `tapMaxDuration` ve hareket ≤ `tapMaxMoveMM` → tap: köşe ise çift dokunma sayacı (aynı köşe, `doubleTapWindow` içinde ikinci tap → `mute`/`screenshot` + `haptic(.tap)`); kenar eylemi `media` ise çift dokunma → `mediaPlayPause`. → `idle`.
   - kalkma, diğer → `idle`.
3. **sliding**
   - dokunma sayısı ≥ 2 → bitir(cancel) → `spent`.
   - her karede `accumulatedMM += Δ(kenar ekseni)`; `|accumulatedMM| ≥ stepMM(action)` olduğu sürece bir adım komutu + `haptic(.step)` emit, `accumulatedMM` azalt. Adım komutları: `stepVolume(±1, fine)`, `stepBrightness(±1, fine)`, `stepKeyboardBacklight(±1, fine)`, `appSwitchStep(±1)`, `scrubStep(±1)`, `mediaNext`/`mediaPrevious`. `fine = config.precision`.
   - `accumulatedMM` sonlu değilse (sonsuz ya da NaN koordinat) slide bitir(cancel) ile biter → `spent`; adım üretilmez. Bir karede en fazla 64 adım (`maxStepsPerFrame`) üretilir; sınıra ulaşılırsa kalan mesafe atılır (`accumulatedMM = 0`), böylece bozuk koordinat sonraki karelerde adım üretmeye devam etmez.
   - dokunma id'si kareden kayboldu (kalkma ya da anlık düşme; ikisi ayırt edilemez) → `lost`. Spike ile doğrulandı: cihaz kalkışta state 5→6→7 ve ardından sıfır dokunmalı bir kare gönderir; platform yalnızca state 3/4'ü geçirdiği için parmak state 5'te kaybolur.
   - kare gelmedi (watchdog `tick(now)` ile `now − lastFrameTime ≥ lostTimeout`) → bitir(commit) → `idle`.
4. **lost**
   - aynı id geri geldi, `lostTimeout` içinde → `sliding`.
   - `lostTimeout` doldu (kare ya da `tick` ile) → bitir(commit) → `idle`.
5. **spent** — dokunma sayısı 3'e çıkmış, ilk inişten bu yana ≤ `threeFingerSettle` geçmiş, hiçbiri `tapMaxMoveMM`'den fazla hareket etmemiş ve `middleClickEnabled` → `threeFinger`. Tüm dokunmalar kalkınca → `idle`.
6. **threeFinger**
   - herhangi bir dokunma `tapMaxMoveMM`'den fazla hareket etti ya da süre > `threeFingerMaxDuration` → `spent`.
   - dördüncü dokunma → `spent`.
   - üçü de kalktı → emit `middleClick` + `haptic(.tap)` → `idle`.

**bitir(commit/cancel):** `switchApps` → `appSwitchCommit` (cancel'da `appSwitchCancel`); `scrubVideo` → `scrubCommit` (cancel'da `scrubCancel`); diğerleri komut üretmez. `frozen` ise `freezeCursor(false)`.

### 5.5 Eylem eşlemesi

| EdgeAction | Adım mesafesi | +1 komutu | −1 komutu | Bırakınca |
|---|---|---|---|---|
| volume | stepMM | stepVolume(+1) | stepVolume(−1) | — |
| brightness | stepMM | stepBrightness(+1) | stepBrightness(−1) | — |
| keyboardBacklight | stepMM | stepKeyboardBacklight(+1) | stepKeyboardBacklight(−1) | — |
| switchApps | appSwitchStepMM | appSwitchStep(+1) | appSwitchStep(−1) | appSwitchCommit |
| scrubVideo | scrubStepMM | scrubStep(+1) (+5 s) | scrubStep(−1) | scrubCommit |
| media | mediaSkipStepMM | mediaNext | mediaPrevious | — (çift dokunma → mediaPlayPause) |

### 5.6 Kapılar (her karede, sırayla)

1. **Avuç filtresi:** `majorAxisMM > palmMajorAxisMM` olan dokunmalar kareden çıkarılır; geriye kalanlar işlenir.
2. **Yazma kapısı:** `now − lastKeyDown < typingGate` ise `idle` ve `candidate` durumlarında yeni jest başlamaz (mevcut `sliding` sürer).
3. **Hold-to-Slide:** `holdKeyRequired && !holdKeySatisfied` ise yeni jest başlamaz; `sliding` sırasında tuş bırakılırsa bitir(commit).
4. **Duraklatma:** `paused` ise `idle` dışındaki durum `idle`'a döner ve kareler yok sayılır.

### 5.7 Komutlar

```swift
public enum HapticEvent { start, step, tap, limit }
public enum GestureCommand {
  case stepVolume(Int, fine: Bool), stepBrightness(Int, fine: Bool), stepKeyboardBacklight(Int, fine: Bool)
  case appSwitchStep(Int), appSwitchCommit, appSwitchCancel
  case scrubStep(Int), scrubCommit, scrubCancel
  case mediaPlayPause, mediaNext, mediaPrevious
  case mute, screenshot, middleClick
  case haptic(HapticEvent), freezeCursor(Bool)
}
public protocol CommandSink: AnyObject { func handle(_ command: GestureCommand, device: UInt64) }
```

`limit` haptik olayı yalnızca seviyesi bilinen eylemlerde (keyboardBacklight Yol B'de, DDC'de) platform tarafından üretilir; Engine üretmez.

### 5.8 Host arabirimi

```swift
public final class GestureEngine {
  init(config: EngineConfig, sink: CommandSink)
  func update(config: EngineConfig)        // anında geçerli; sliding/lost → bitir(commit), candidate → spent
  func process(_ frame: Frame)              // Engine kendi kilidini alır
  func tick(now: TimeInterval)             // watchdog
  func noteKeyDown(at: TimeInterval)
  func setHoldKeySatisfied(_: Bool)
  func setPaused(_: Bool)
  func reset()                              // sliding/lost → bitir(cancel); idle'a dön
}
```

`reset()` iptal anlamı taşır: `switchApps` → `appSwitchCancel`, `scrubVideo` → `scrubCancel`, ardından imleç dondurulmuşsa `freezeCursor(false)`, sonra `idle`; bekleyen çift dokunma kaydı silinir. `update(config:)` ise commit anlamını korur; o sırada `candidate` olan parmak `spent`'e düşer ve kalkana kadar jest üretmez. Çift dokunma kaydı Engine `spent` ya da `threeFinger` durumuna her girişte silinir.

### 5.9 Kenar ve köşe eylemleri, hassasiyet (Aşama 3)

Dört kenar aynı listeyi sunar: `volume`, `brightness`, `keyboardBacklight`, `switchApps`, `switchTabs`, `switchDesktops`, `scrubVideo`, `media`, `zoom`, `undoRedo`, `off`. `Settings` sol ve sağ kenar için `leftEdge` (varsayılan `brightness`) ve `rightEdge` (varsayılan `volume`) tutar; Swap Sides kalktı. Eski `swapSides: true`, `leftEdge`/`rightEdge` yoksa sol=`volume`, sağ=`brightness` olarak okunur ve bir daha yazılmaz (karar 44). Klavye ışığı köprüsü yokken `keyboardBacklight` her kenarda `media`'ya düşer.

| EdgeAction | Adım mesafesi | +1 komutu (gönderilen) | −1 komutu (gönderilen) | Bırakınca |
|---|---|---|---|---|
| switchTabs | tabSwitchStepMM = 12 | tabSwitchStep(+1) (⌃⇥) | tabSwitchStep(−1) (⌃⇧⇥) | — |
| switchDesktops | desktopSwitchStepMM = 20 | desktopSwitchStep(+1) (⌃→) | desktopSwitchStep(−1) (⌃←) | — |
| zoom | zoomStepMM = 8 | zoomStep(+1) (⌘=) | zoomStep(−1) (⌘−) | — |
| undoRedo | undoRedoStepMM = 10 | undoRedoStep(+1) (⇧⌘Z) | undoRedoStep(−1) (⌘Z) | — |

+1 yönü 5.3'teki eksen kuralıdır: yatay kenarda sağa, dikey kenarda yukarı. trrek'in kendi penceresi öndeyken `switchTabs`, `zoom` ve `undoRedo` adımları (scrub gibi) gönderilmez; `switchDesktops` sistem genelidir ve çalışır. `switchApps` ve `keyboardBacklight` hangi kenara atanırsa atansın aynı davranır (⌘ basılı tutma, commit/cancel; overlay ve sınır haptiği dağıtıcıdadır).

`CornerAction`: `off`, `mute`, `screenshot`, `playPause` (`mediaPlayPause`), `missionControl`, `appWindows`, `showDesktop`, `spotlight` (⌘Space), `lockScreen` (⌃⌘Q), `screenshotArea` (⇧⌘4). Mission Control, uygulama pencereleri ve masaüstünü göster, sistemin Mission Control uygulamasını `MissionControlOpening` portu üzerinden argümansız, `2` ve `1` argümanıyla açar; uygulama bulunamazsa hata günlüğe yazılır (karar 46).

**Hassasiyet:** `Settings.slideSensitivity` (`veryLow` 1,6 · `low` 1,25 · `standard` 1,0 · `high` 0,8 · `veryHigh` 0,6). `ConfigMapper` bütün adım mesafelerini bu çarpanla ölçekler; diğer eşikler değişmez (karar 47). Ayar General sekmesinde "Slide Sensitivity" seçicisidir. Accessibility izni yokken yeni eylemlerin hepsi kapalıdır (karar 27).

## 6. TrrekPlatform

### 6.1 Sembol yükleme politikası

`PrivateSymbols.swift` tüm `dlopen`/`dlsym` çağrılarını içerir. Her sembol `lazy static` ve opsiyoneldir. Bir köprü, ihtiyaç duyduğu tüm semboller çözülmüşse `isAvailable = true` döner. Çözülemeyen sembol loglanır, özellik kapanır, çökme olmaz. Doğrudan `extern` bağlama arm64e işaretçi doğrulaması nedeniyle kullanılmaz.

### 6.2 MultitouchSource

- Framework: `/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport`.
- Semboller: `MTDeviceCreateList`, `MTDeviceIsBuiltIn`, `MTDeviceGetSensorSurfaceDimensions`, `MTRegisterContactFrameCallback`, `MTUnregisterContactFrameCallback`, `MTDeviceStart`, `MTDeviceStop`, `MTDeviceRelease`.
- Başlatma: liste alınır, her cihaz için yüzey boyutu okunur (birim 1/100 mm; spike'ta doğrulandı: dahili trackpad 12194×7408 → 121.94×74.08 mm), callback kaydedilir, `MTDeviceStart(dev, 0)`.
- Callback imzası: `(MTDeviceRef, UnsafePointer<MTTouch>, Int32 count, Double timestamp, Int32 frame)`. `MTTouch` 96 baytlık C yapısıdır: `frame:Int32, timestamp:Double, identifier:Int32, state:Int32, fingerID:Int32, handID:Int32, normalizedPosition{x,y}:Float, normalizedVelocity{x,y}:Float, total:Float, pressure:Float, angle:Float, majorAxis:Float, minorAxis:Float, absolutePosition{x,y}:Float, absoluteVelocity{x,y}:Float, reserved:Int32×2, density:Float`. State değerleri: 3 = temas başladı, 4 = temas sürüyor; diğerleri temas değil. Düzen `TrrekProbe layout-check` ile doğrulanır.
- İlk karede makullük denetimi: `normalizedPosition` 0...1 içinde ve `majorAxis` 0...100 mm içinde değilse kaynak durdurulur ve `layoutMismatch` hatası yayınlanır.
- Kare dönüşümü: yalnızca state ∈ {3, 4} dokunmalar `TouchBuffer`'a yazılır; `majorAxisMM = majorAxis`. `deviceID` olarak `MTDeviceRef` işaretçisinin tamsayı değeri kullanılır.
- Yeniden başlatma: `WakeObserver` uyanma bildiriminde ve IOKit `IOServiceAddMatchingNotification("AppleMultitouchDevice")` ile cihaz ekleme/çıkarmada `stop()` + `start()`.
- Watchdog: slide sürerken her karede `DispatchSourceTimer` (tek seferlik, `lostTimeout`) yeniden kurulur; dolunca `engine.tick(now:)`.

### 6.3 ActuatorHaptics

- Semboller: `MTActuatorCreateFromDeviceID(UInt64)`, `MTActuatorOpen`, `MTActuatorActuate(actuator, Int32 waveform, UInt32 0, Float 0, Float 0)`, `MTActuatorClose`.
- Cihaz kimliği: IORegistry `AppleMultitouchDevice` girdilerinden `Multitouch ID`; `MT Built-In == true` olan dahili, diğerleri harici. Slide hangi cihazdan geldiyse (`MTDeviceIsBuiltIn`) o aktüatör kullanılır; eşleşme yoksa ilk aktüatör.
- Güç eşlemesi (başlangıç; spike'ta ayarlanır): Light → 4, Medium → 5, Strong → 6; Strong'da `start`/`tap` olayları iki darbe (60 ms ara). Off → hiçbir şey.
- Yedek: aktüatör yoksa `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)`.

### 6.4 MediaKeyPoster

- Olay: `NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (0x0A << 8), data2: -1)` ardından aynı olayın `0x0B` (key up) sürümü; `event.cgEvent?.post(tap: .cghidEventTap)`.
- Tuş kodları: SOUND_UP 0, SOUND_DOWN 1, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3, MUTE 7, PLAY 16, NEXT 17, PREVIOUS 18, ILLUMINATION_UP 21, ILLUMINATION_DOWN 22.
- `fine == true` → `modifierFlags = [.option, .shift]` (çeyrek adım).
- `EventStamp`: tüm olaylar `CGEventSource(stateID: .privateState)` ile ve `userData = 0x7472726B` ("trrk") damgasıyla gönderilir; tap'ler bu damgayı görünce olayı yok sayar (kendi olaylarımız yazma kapısını tetiklemez).

### 6.5 EventTapGuard

- **Tap A** (hep açık): `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .listenOnly, [keyDown, flagsChanged])`. keyDown → `engine.noteKeyDown`. flagsChanged → Hold-to-Slide değerlendirmesi (6.10).
- **Tap B** (yalnızca slide sırasında): `.cghidEventTap` konumunda (olay WindowServer'a ulaşmadan yutulur, imleç yerinde kalır), `.defaultTap`, `[mouseMoved, leftMouseDragged, rightMouseDragged, otherMouseDragged, scrollWheel]`. Açıkken scrollWheel her zaman yutulur; mouseMoved/dragged yalnızca `freezeCursor` açıksa yutulur. `freezeCursor(true)` komutu `CGEvent.tapEnable(tap, true)` çağırır, `freezeCursor(false)` kapatır. Tap kapalıyken sıfır maliyet.
- `tapDisabledByTimeout`/`tapDisabledByUserInput` gelirse tap yeniden etkinleştirilir.
- Accessibility yoksa tap'ler kurulmaz; `isAvailable = false`.

### 6.6 KeyPoster ve MousePoster

- **Switch Apps protokolü:** ilk `appSwitchStep` → ⌘ keyDown (`flagsChanged`, keycode 55, flags `.maskCommand`), ardından Tab (keycode 48) down/up `.maskCommand` ile; `−1` için `.maskCommand | .maskShift`. Sonraki adımlar yalnızca Tab. `appSwitchCommit` → ⌘ keyUp. `appSwitchCancel` → Escape (53) down/up, sonra ⌘ keyUp.
- **Screenshot:** keycode 23 ('5') down/up, flags `.maskCommand | .maskShift`.
- **Orta tık:** `CGEvent(mouseEventSource:, mouseType: .otherMouseDown, mouseCursorPosition: NSEvent.mouseLocation (CG koordinatına çevrilmiş), mouseButton: .center)`, ardından `.otherMouseUp`. Her ikisi de `.cghidEventTap`'e.
- Tüm olaylar 6.4'teki damgalı kaynakla gönderilir.

### 6.7 KeyboardBacklight

Aşama 0 spike sonucu: medya tuşu yolu Accessibility izni olmadan doğrulanamadı; **Yol B birincil**, Yol A izin alındıktan sonra deneme olarak kalır.
- **Yol A (ileride):** ILLUMINATION_UP/DOWN medya tuşu olayları; macOS kendi HUD'unu gösteriyorsa bu yola geçilebilir, köprü `nativeHUD = true` döner.
- **Yol B (birincil):** CoreBrightness `KeyboardBrightnessClient` sınıfı (`copyKeyboardBacklightIDs`, `brightnessForKeyboard:`, `setBrightness:fadeSpeed:commit:forKeyboard:`), adım 1/16, `fine` ise 1/64; seviye overlay'de gösterilir; 0 ve 1'de `haptic(.limit)`.
- Köprü `isAvailable == false` ise ayarlarda Keyboard Backlight seçeneği gri olur ve bottom edge varsayılanı Media'ya düşer.

### 6.8 ExternalBrightness ve DisplayLocator (Aşama 2)

- `DisplayLocator`: imleç konumu kaynaksız oluşturulan bir olayın konumundan (`CGEvent(source: nil).location`, global ekran koordinatları) alınır ve `CGGetDisplaysWithPoint` ile `CGDirectDisplayID`'ye çevrilir; `CGDisplayIsBuiltin` ise dahili.
- Dahili → `stepBrightness` medya tuşu yoluyla. Harici ve ayar açık → DDC. Son taramada DDC servisi bulunamayan harici ekran (kablosuz/sanal ekran gibi) harici sayılmaz ve medya tuşu yolunu kullanır (karar 35).
- DDC/CI: `IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C` sembolleri; 7-bit adres 0x37, veri adresi 0x51, VCP kodu 0x10 (parlaklık); DDC sağlama toplamı standardına göre paket kurulur. IORegistry'deki harici `DCPAVServiceProxy` girdileri ekranlara önce EDID üretici/model/seri numarasıyla (sonra seri numarası eksikse üretici/modelle) eşlenir; eşleşmeyen ekranlar kalan servisleri sırayla alır. Tarama oluşturulurken ve her ekran yeniden yapılandırmasından sonra arka planda yapılır. Slide başında mevcut/maks değer okunur, her adımda `maks/16` (fine: `maks/64`) yazılır, overlay yüzdeyi gösterir.
- Sembollerden biri yoksa köprü oluşturulmaz; Edges sekmesindeki ayar "Not available on this Mac" notuyla devre dışı kalır.
- Bu Mac'te doğrulanamaz; "best effort" olarak işaretlenir. Servisi olan ekranda aktarım hatası olursa overlay "No DDC" gösterir (çubuk yok); hata her hata durumuna girişte bir kez günlüğe yazılır.

### 6.9 Scrub Video (ok tuşları)

- Video sarma, öndeki uygulamaya ←/→ ok tuşu göndererek yapılır (karar 33): `scrubStep(+1)` → sağ ok (keyCode 124), `scrubStep(−1)` → sol ok (123), bayraksız. Tarayıcılar ve çoğu oynatıcı bu tuşlarla sarar; ek süreç ya da özel API gerekmez.
- Adım boyunu uygulama belirler; overlay etiketi adım başına 5 s varsayar. `CommandDispatcher` slide başına net adım sayısını tutar ve overlay'de `"+15 s"` / `"−10 s"` / `"0 s"` gösterir (simge + etiket, seviye çubuğu yok).
- `scrubCommit` ve `scrubCancel` yalnızca sayacı sıfırlar; tuş göndermez (adımlar zaten uygulanmıştır).
- Öndeki uygulama trrek'in kendisiyse (ayar ya da karşılama penceresi) adımlar tuş göndermez ve sayılmaz (karar 35).
- Sentetik olay gönderdiği için Accessibility izni yokken kapalıdır (karar 27).

### 6.10 Sistem köprüleri

- **FrontmostObserver:** `NSWorkspace.didActivateApplicationNotification` → bundle id; `Settings.pausedBundleIDs` içindeyse `engine.setPaused(true)`.
- **WakeObserver:** `NSWorkspace.didWakeNotification` → `MultitouchSource.restart()`.
- **Permissions:** `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`; `DistributedNotificationCenter` `com.apple.accessibility.api` bildirimiyle durum yenilenir, tap'ler o anda kurulur. Zamanlayıcı yok.
- **LaunchAtLogin:** `SMAppService.mainApp.register()` / `unregister()`; durum `status`tan okunur.
- **Hold-to-Slide:** Tap A flagsChanged → seçili modifier basılı mı? *Hold* modunda `setHoldKeySatisfied(isDown)`. *Toggle* modunda modifier tek başına basılıp 300 ms içinde bırakılırsa (arada başka tuş yok) durum ters çevrilir; durum menü çubuğu ikonunda küçük bir nokta ile gösterilir.

## 7. Trrek (uygulama)

### 7.1 Yaşam döngüsü

1. `SettingsStore.load()` (bozuk veri → varsayılanlar + log).
2. `Permissions.check()`; izin yoksa Welcome açılır ve menüde "Grant Accessibility…" kalemi görünür.
3. `Coordinator` Engine, Platform köprüleri ve `Settings`'i bağlar; `EngineConfig` üretir.
4. `MultitouchSource.start()`; başarısızsa menüde "Trackpad not found" ve uyanma/cihaz bildirimlerinde yeniden deneme.
5. `EventTapGuard.install()` (izin varsa).
6. `StatusMenu` kurulur. İlk çalıştırmada (`welcomeShown == false`) Welcome ve Launch at Login kaydı.
7. Çıkışta: ⌘ basılı kalmasın diye `appSwitchCancel` eşdeğeri temizlik, tap'ler kapatılır, multitouch durdurulur.

`Info.plist`: `LSUIElement = true`, `LSMinimumSystemVersion = 26.0`, `CFBundleIdentifier = com.burakseyitkara.trrek`, `NSHumanReadableCopyright`, `CFBundleShortVersionString` ve `CFBundleVersion` derleme betiğinden.

### 7.2 Menü çubuğu menüsü

Menü hızlı erişim içindir; tüm yapılandırma ayar penceresindedir.

```
trrek is active            (durum satırı, devre dışı; "Paused in <App>", "Accessibility access needed", "Trackpad not found")
─────────────
Precision Control          ✓ anahtar
Freeze Cursor              ✓ anahtar
Hold-to-Slide: On/Off      (yalnızca Toggle modunda; durum)
Pause in <Front App>       (öndeki uygulama trrek ise gizli; duraklatılmışsa "Resume in <App>")
─────────────
Settings…                  ⌘,
Show Welcome
Grant Accessibility…       (yalnızca izin yokken)
─────────────
About trrek
Quit trrek                 ⌘Q
```

Menü `menuNeedsUpdate` ile açılırken tazelenir. İkon: `MenuIcon.pdf` şablon görüntüsü (trackpad silueti, sağ kenarı vurgulu); Toggle modunda aktifken köşede nokta.

### 7.3 Ayar penceresi (SwiftUI, Liquid Glass)

- Açılış: menüden "Settings…" ya da ⌘,. `NSWindow` + `NSHostingController<SettingsView>`; `titlebarAppearsTransparent`, araç çubuğu stili `.unified`; pencere kapanınca serbest bırakılır, bir sonraki açılışta yeniden kurulur.
- Yerleşim: `TabView` ile dört sekme; her sekme `Form` + `.formStyle(.grouped)`. macOS 26'da araç çubuğu ve sekmeler sistemin Liquid Glass görünümünü alır; özel öğeler `.glassEffect(.regular, in: .rect(cornerRadius: 12))` ile camlaştırılır. Sabit boyut 640×480 pt.
- **General:** Haptic Feedback (segment: Off/Light/Medium/Strong), Slide Sensitivity (Aşama 3), Precision Control, Freeze Cursor, Launch at Login, Language (Aşama 3; 7.4b), Export Settings…/Import Settings… (Aşama 3), Reset to Defaults… butonu.
- **Edges:** Üstte etkileşimli `TrackpadDiagram` (cam yüzeyli trackpad silueti; dört kenar renkli şeritlerle seçili eylemleriyle etiketli; Aşama 3'te Edges sekmesinde 150 pt yüksekliğinde). Altında: Left Edge, Right Edge (Aşama 3'te Swap Sides'ın yerine), Top Edge, Bottom Edge (Picker), Edge Width (segment), Bottom Quarter Only, External Monitor Brightness (köprü yoksa devre dışı ve açıklama).
- **Corners & Taps:** Dört köşe için Picker (Off/Mute/Screenshot; Aşama 3'te 5.9'daki eylemler eklendi) diyagram üzerinde köşe rozetleriyle; 3-Finger Tap Middle Click anahtarı ve "Look up & data detectors" ayarına dair ipucu metni.
- **Advanced:** Hold-to-Slide Key (Picker: None/Shift/Control/Option/Command) ve mod (Hold/Toggle); Paused Apps listesi (satır başına uygulama ikonu + ad, "−" ile kaldır, "+" ile `NSOpenPanel`'dan uygulama seç); Accessibility durumu ve "Open System Settings" butonu; sürüm bilgisi.
- Veri akışı: `SettingsView` `@Observable` bir `SettingsModel`'i gözler; her değişiklik `SettingsStore`'a yazılır ve `Coordinator` yeni `EngineConfig` uygular. Pencere açık değilken model bellekte değildir.

### 7.4 Ayarlar

```swift
struct Settings: Codable, Equatable {
  var schemaVersion = 1
  var hapticStrength: HapticStrength = .medium
  var edgeWidth: EdgeWidth = .standard
  var precision = false, freezeCursor = true, bottomQuarterOnly = false
  var slideSensitivity: SlideSensitivity = .standard   // Aşama 3
  var externalMonitorBrightness = false
  var leftEdge: EdgeAction = .brightness              // Aşama 3; eski swapSides yalnızca okunur
  var rightEdge: EdgeAction = .volume
  var topEdge: EdgeAction = .switchApps
  var bottomEdge: EdgeAction = .keyboardBacklight     // köprü yoksa ilk çalıştırmada .media
  var corners: [Corner: CornerAction] = tümü .off
  var middleClick = false
  var holdKey: HoldKey = .none, holdKeyMode: HoldKeyMode = .hold
  var pausedBundleIDs: [String] = []
  var launchAtLogin = true
  var welcomeShown = false
  var language: AppLanguage = .system                 // Aşama 3: system, english, turkish
}
```

`UserDefaults.standard` içinde `settings` anahtarında JSON. `schemaVersion` ileride göç için. Reset to Defaults: onay; `launchAtLogin`, `welcomeShown` ve `language` korunur.

#### 7.4a Dışa ve içe aktarma (Aşama 3)

`TrrekAppCore.SettingsDocument` ayarları `.trrek` dosyasına yazar ve okur: girintili, anahtarları sıralı JSON, `{"appVersion", "format": "trrek-settings", "formatVersion": 1, "settings": {…}}`. `launchAtLogin`, `welcomeShown` ve (Aşama 3, 7.4b) `language` bu Mac'e aittir; dışa aktarılmaz, içe aktarmada mevcut değerleri korunur. `settings` forgiving decoder ile okunur. 1 MB'tan büyük, JSON olmayan, `format` farklı ya da `formatVersion` < 1 olan dosya `notSettingsFile`, `formatVersion` > 1 ya da `settings.schemaVersion` bu derlemeden yeni olan dosya `newerFormat` hatasıdır; ikisinde de ayarlar değişmez ve uyarı çıkar. General sekmesindeki Export/Import düğmeleri panelleri ayarlar penceresine sheet olarak açar; içe aktarma onaydan sonra `SettingsModel` → `onChange` → `Coordinator.apply` yolundan geçer. `Info.plist` `com.burakseyitkara.trrek.settings` türünü dışa aktarır (`public.json`'a uyar, uzantı `trrek`) ve onu Viewer rolüyle açar; Finder'dan açılan dosya `application(_:open:)` ile ayarlar penceresini General sekmesinde açıp aynı onayı gösterir (karar 43).

#### 7.4b Dil ve yerelleştirme (Aşama 3)

Arayüz metinleri İngilizce yazılır; çeviriler `Sources/Trrek/Resources/{en,tr}.lproj/Localizable.strings` dosyalarındadır ve anahtar İngilizce kaynak metindir. `build-app.sh` bu klasörü paketin `Contents/Resources` klasörüne kopyalar; SwiftPM hedefi klasörü dışarıda bırakır (`exclude`). `Info.plist`: `CFBundleDevelopmentRegion` `en`, `CFBundleLocalizations` `[en, tr]`; `InfoPlist.strings` `.trrek` türünün adını çevirir. SwiftUI'da literal metinler (`Text("…")`, `Button("…")` …) kendiliğinden, `TrrekAppCore` ve AppKit metinleri `String(localized:bundle: .main)` ile çevrilir. Overlay'in "No DDC" etiketi gösterilirken anahtar olarak aranır, scrub etiketinin birimi ("+15 s") `"%@ s"` biçimiyle çevrilir (Türkçe "sn"). `Settings.language` (`system`, `english`, `turkish`) General sekmesindeki Language seçicisidir; bu Mac'in kullanıcısına aittir, dışa aktarılmaz, içe aktarma ve Reset onu korur. Değişince uygulamanın kendi defaults alanındaki `AppleLanguages` yazılır (`system` için silinir); seçimin çözüldüğü yerelleştirme (`system` için global `AppleLanguages`'a göre) açılıştakinden farklıysa "Relaunch trrek to use the new language." satırı Relaunch düğmesiyle çıkar; düğme trrek'in çıkmasını bekleyip aynı paketi yeniden açan kısa bir kabuk başlatır ve uygulamadan çıkar. Açılışta ayar ile tercih farklıysa tercih ayara göre yazılır (karar 49, 50).

### 7.5 OverlayPanel

- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = true`, `hasShadow = false`.
- İçerik: `NSHostingView<OverlayView>`; SwiftUI görünümü `.glassEffect(.regular, in: .capsule)` ile SF Symbol ikon + 16 bölmeli seviye çubuğu + yüzde; etiketli değerlerde (scrub süresi, "No DDC") çubuk yoktur ve etiket doğal genişliğini alır (karar 35).
- Konum: imlecin bulunduğu ekranın sağ üstü, 16 pt kenar boşluğu, 240×56 pt (yüzdeli satır ve en geniş etiketler sığsın diye 220'den genişletildi).
- Kullanım: keyboardBacklight Yol B, DDC, Scrub Video. İlk ihtiyaçta oluşturulur; son güncellemeden 1,0 s sonra gizlenir (tek seferlik `DispatchWorkItem`).

### 7.6 Karşılama penceresi (SwiftUI, Liquid Glass)

`NSWindow` + `NSHostingController<WelcomeView>`, 560×440 pt, araç çubuğu yok, arka plan sistem materyali. İçerik: başlık, `TrackpadDiagram` (aynı bileşen, salt okunur), dört kenarı anlatan cam kartlar (ikon + bir satır), Accessibility durumu ve "Grant Accessibility Access" butonu (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), "Open Settings" ve "Done". Aşama 2'de kartlar sırayla belirir (hafif animasyon).

### 7.7 Günlük

`os.Logger(subsystem: "com.burakseyitkara.trrek", category:)`; kategoriler `engine`, `platform`, `app`. Kare başına log yok. Sembol çözümleme sonuçları, cihaz başlatma, izin durumu ve hatalar `info`/`error` seviyesinde.

### 7.8 Paketleme

- `scripts/build-app.sh [--version X.Y.Z] [--build N]`: `swift build -c release --arch arm64`, `dist/trrek.app` ağacı, ikili, `Info.plist.in` değişken değişimi, `AppIcon.icns`, kaynaklar, `codesign --force --sign - --deep`.
- `scripts/make-icon.sh`: `Resources/icon-1024.png` → `sips` ile boyutlar → `iconutil` → `AppIcon.icns`. 1024 px kaynak görsel `scripts/render-icon.swift` ile CoreGraphics'ten üretilir (cam yüzeyli trackpad silueti, sağ kenarı parlak).
- `make install`: `dist/trrek.app` → `~/Applications/trrek.app`, `lsregister` ile kayıt.
- `TrrekProbe` paketlenmez.

## 8. Hata yönetimi

| Durum | Davranış |
|---|---|
| Private sembol yok | Köprü `isAvailable=false`; ilgili ayar devre dışı; log `error` |
| MTTouch düzeni makul değil | Bir cihazın temas içeren ilk karesinde normalize konum -0,05…1,05 dışında ya da sonlu değilse, veya majorAxis 0…100 dışındaysa kaynak hemen kareleri bırakır, ana iş parçacığında durur; menü durum satırı "Trackpad data unavailable"; log. Sonraki kareler kontrol edilmez. Uyanma ve cihaz bildirimlerinde yeniden dener |
| Trackpad olmayan multitouch cihaz (ör. dokunmatik yüzeyli fare) | Akışa alınmaz, jest üretmez ve "trrek is active" için sayılmaz. Tür, I/O Registry'deki genel HID özelliklerinden (`HIDPointerAccelerationType`, `DeviceUsagePairs`) belirlenir; ikisi de yoksa cihaz kullanılır (fail open) ve log yazılır |
| Trackpad listesi boş | Durum satırı "Trackpad not found" (yalnızca trackpad olmayan cihazlar bağlıyken de); uyanma ve cihaz bildirimlerinde yeniden dener |
| Accessibility yok | Tap'ler kurulmaz; motor çalışır. İzinsiz sentetik olaylar teslim edilmediği için klavye ışığı dışındaki bütün kenar eylemleri, bütün köşeler, orta tık ve imleç dondurma kapalıdır; yazma kapısı ve hold tuşu da çalışmaz. Diyagram etkin (kapatılmış) eylemleri gösterir, karşılama kartları izin gerektiğini söyler. Menüde "Grant Accessibility…", menü simgesinde nokta; sonraki açılışlarda karşılama penceresi yeniden açılır |
| Tap sistem tarafından kapatıldı | Callback içinde yeniden etkinleştirilir |
| DDC/Now Playing başarısız | Overlay "No DDC" / "No media"; log |
| Ayar verisi bozuk | Varsayılanlar; log `error` |
| Uygulama çıkışı slide sırasında | ⌘ bırakılır, tap'ler kapatılır |

## 9. Test stratejisi

### 9.1 Engine birim testleri (Swift Testing, CI'da)

Sentetik `Frame` üreten bir yardımcı (`FrameBuilder`) ile; her kural bir test:

| # | Test | Kural |
|---|---|---|
| 1 | Kenar şeridi dışından başlayan hareket komut üretmez | 5.3 |
| 2 | 3 mm altı hareket slide başlatmaz | slideStartMM |
| 3 | 60 mm yukarı → 16 `stepVolume(+1)`, 16 `haptic(.step)` | stepMM |
| 4 | Aşağı → −1 | yön |
| 5 | precision → `fine: true` | 5.5 |
| 6 | Dik 4 mm hareket → spent, sonraki kareler yok sayılır | abortPerpendicularMM |
| 7 | İkinci parmak slide'ı iptal eder, kalkana kadar spent | 5.4 |
| 8 | Parmak kaybolup 170 ms içinde dönerse slide sürer; 181 ms sonra commit ve freezeCursor(false) | lostTimeout |
| 9 | Watchdog `tick` → commit | 5.4 |
| 10 | Tap: 250 ms, 2 mm → komut yok | tap |
| 11 | Köşe çift dokunma 350 ms içinde → mute/screenshot; 351 ms → yok | doubleTapWindow |
| 12 | Media kenarı çift dokunma → mediaPlayPause; 20 mm slide → mediaNext | 5.5 |
| 13 | Üç parmak tap → middleClick; açık değilse yok; hareket varsa yok; parmaklar ayrı karelerde inse de çalışır | threeFinger |
| 14 | majorAxis 21 mm → aday olmaz; 19 mm → olur | palm |
| 15 | keyDown'dan 400 ms içinde jest başlamaz; süren slide devam eder | typingGate |
| 16 | holdKeyRequired && !satisfied → jest yok; sliding'de bırakma → commit | 5.6 |
| 17 | paused → her şey yok sayılır, aktif slide biter | 5.6 |
| 18 | bottomQuarterOnly → y=0.5'ten sol kenar aday olmaz, y=0.2 olur | 5.3 |
| 19 | Narrow/Wide şerit genişliği sınırı | edgeWidthMM |
| 20 | left/right eylemleri değişince (swap) komut türü değişir | 5.2 |
| 21 | switchApps: 24 mm → 2 `appSwitchStep(+1)`; kalkınca commit; ikinci parmak → cancel | 5.5 |
| 22 | scrubVideo: 12 mm → 2 `scrubStep(+1)`; kalkınca scrubCommit | 5.5 |
| 23 | `update(config:)` sliding sırasında → commit ve freezeCursor(false) | 5.8 |
| 24 | Başka cihazdan gelen kare sliding'i etkilemez | 5.4 |
| 25 | Her slide'da freezeCursor(true) bir kez, sonunda (false) bir kez | 5.4 |
| 26 | Köşe adayı dikey hareketle sağ/sol kenarda slide başlatır | 5.4 |

### 9.2 TrrekProbe (yerel)

Alt komutlar: `devices` (liste, yüzey boyutu, built-in), `frames` (ham kare akışı, Ctrl-C ile çıkış), `layout-check`, `haptic <id>` (dalga formu), `key <name>` (medya tuşu olayı: volume-up, brightness-up, illumination-up, play…), `switcher` (⌘ basılı + Tab × 2 + bırak), `freeze <saniye>` (Tap B'yi açıp imleci dondurur), `mem` (kendi RSS'ini yazdırır). Aşama 0'da ve her macOS güncellemesinden sonra çalıştırılır.

### 9.3 Elle kontrol listesi

`docs/testing.md`: her kenar ve köşe, orta tık, precision, imleç dondurma, yazma kapısı, Hold/Toggle, pause in app, uyku sonrası, ayar penceresi ve karşılama görünümü, harici trackpad takma (varsa), dokunmatik yüzeyli fare (varsa). PR şablonunda işaretlenir.

### 9.4 Kaynak ölçümü

`scripts/perf.sh`: uygulamayı başlatır, 30 s bekler, `footprint` ve `ps -o %cpu,rss` çıktısını yazdırır; eşik: RSS < 15 MB, CPU 0.0. Sonuç README'ye işlenir.

Not: Bellek RSS yerine fiziksel ayak izi (`phys_footprint`, `vmmap --summary`) olarak ölçülür; RSS paylaşılan sistem çerçevesi sayfalarını da saydığı için uygulamanın kendi maliyetini göstermez (karar 22). Eşik 15 MB ayak izi ve %1 CPU'dur. Ölçüm `--skip-first-run` ile başlatılır ki karşılama penceresi ölçümü bozmasın.

## 10. Git, CI/CD ve geliştirme süreci

### 10.1 Dal modeli

- `main` her zaman derlenir ve yeşildir. Doğrudan commit yok; değişiklik `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, `test/` dallarından PR ile gelir. Squash merge, dal silinir.
- Commit mesajları İngilizce conventional commits; PR gövdeleri Türkçe.
- **Zorlama:** `scripts/install-hooks.sh` iki yerel hook kurar: `pre-push` (`main`'e doğrudan push'u reddeder) ve `pre-commit` (`swiftformat --lint` + `swiftlint`). Merge yalnızca `gh pr merge --squash --delete-branch` ile ve CI yeşilken yapılır. Depo public yapılırsa ya da plan yükseltilirse aynı kurallar ruleset olarak eklenir (gerekli kontrol: `ci / build-test`).

### 10.2 PR yaşam döngüsü (otonom)

1. Dal aç, görevi TDD ile uygula, `make check` yerelde geçsin.
2. Push, `gh pr create` (şablona göre: özet, değişiklik türü, test notları, elle kontrol listesi).
3. CI'yı bekle; kırmızıysa düzelt.
4. Bağımsız inceleme: değişikliği görmemiş bir inceleyici (ayrı bağlam) diff'i spec ve CLAUDE.md'ye göre okur; bulgular düzeltilir, inceleme özeti PR'a yorum olarak yazılır ("Review: …", bulgular ve sonuç).
5. `main` ilerlediyse `gh pr update-branch`, CI tekrar yeşil olsun.
6. `gh pr merge --squash --delete-branch`; CHANGELOG satırı aynı PR içinde gelmiş olmalı.
7. Kilometre taşlarında etiket: `v0.1.0` (Aşama 1 sonu), `v0.2.0` (Aşama 2 sonu).

### 10.3 ci.yml

```yaml
on:
  pull_request: { paths-ignore: ['docs/**', '**/*.md'] }
  workflow_dispatch:
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  build-test:
    runs-on: macos-26
    timeout-minutes: 20
    steps: checkout → actions/cache (.build; key: ${{ runner.os }}-swift-${{ hashFiles('Package.swift','Package.resolved') }})
           → swift build -c release --arch arm64 → swift test → swiftformat --lint . → swiftlint lint --strict
           → scripts/build-app.sh --version 0.0.0 --build ${{ github.run_number }} → zip dist/trrek.app → upload-artifact (7 gün)
```

Push-to-main tetikleyicisi yoktur (squash merge içeriği PR başıyla aynıdır; dakika bütçesi korunur).

### 10.4 release.yml

`push: tags: ['v*.*.*']` → aynı derleme ve test → `scripts/build-app.sh --version ${TAG#v} --build ${{ github.run_number }}` → `ditto -c -k --keepParent dist/trrek.app trrek-${TAG}.zip` ve `hdiutil create` ile DMG → `gh release create "$TAG" --generate-notes trrek-*.zip trrek-*.dmg` (`permissions: contents: write`).

### 10.5 Diğer

- `dependabot.yml`: `github-actions`, haftalık.
- `PULL_REQUEST_TEMPLATE.md`: özet, değişiklik türü, test notları, kontrol listesi (build, test, lint, `docs/testing.md`, perf etkisi, CHANGELOG).
- `Makefile`: `build`, `test`, `lint`, `format`, `app`, `install`, `check` (= CI adımları), `perf`, `probe`, `hooks`.
- `CHANGELOG.md`: sürüm ve tarih başlıkları; her PR "Unreleased" altına satır ekler.

## 11. Aşamalar

**Aşama 0 — Spike (TrrekProbe):** Sonuçlar: [spike-results](2026-11-03-spike-results.md). Şu kararlar netleşmeden Aşama 1'in platform işleri başlamaz (Engine işleri bağımsızdır):
1. `MTTouch` düzeni ve yüzey boyutu birimi.
2. Kalkma anında sıfır dokunmalı kare geliyor mu (watchdog yine de kalır).
3. Haptik dalga formu kimlikleri ve Light/Medium/Strong hissi.
4. BRIGHTNESS ve ILLUMINATION medya tuşu olayları macOS 27.2'de HUD gösteriyor mu (6.7 yol seçimi).
5. ⌥⇧ ile çeyrek adım çalışıyor mu.
6. Tap B ile imleç dondurmanın gecikmesi ve etkisi.
7. ⌘ basılı tutup Tab göndermenin seçiciyi açtığı.
8. Boş bir LSUIElement uygulamasının boşta belleği (bütçe doğrulaması).

**Aşama 1 — Çekirdek:** Engine + 26 test; Platform 6.1–6.7, 6.10; uygulama 7.1–7.8 (Scrub Video ve External Monitor Brightness ayarlarda devre dışı); CI/CD 10.x; README, CHANGELOG, lisans. Bitiş: başarı ölçütleri 1–5, etiket `v0.1.0`.

**Aşama 2 — Tamamlayıcılar:** 6.8 DDC, 6.9 Scrub Video, karşılama animasyonu, overlay ve diyagram cilası, harici trackpad ile elle doğrulama (cihaz bulunursa). Etiket `v0.2.0`.

## 12. Riskler

| Risk | Etki | Önlem |
|---|---|---|
| macOS güncellemesi private sembolleri değiştirir | Özellik kaybı | dlsym + `isAvailable`, `TrrekProbe layout-check`, çökme yok |
| Medya tuşu olayı HUD göstermez | Sistem HUD'u hedefi | Spike 4; gerekirse CoreBrightness/CoreDisplay + kendi overlay |
| Haptik dalga formları farklı hissettirir | His | Spike 3; ayarlardan güç seçimi |
| Private depoda dal koruması yok | Disiplin | Yerel hook'lar; public/plan seçeneği açık |
| macOS runner dakikası | CI kesintisi | PR-only tetikleme, paths-ignore, cache, concurrency; aşılırsa self-hosted runner |
| DDC doğrulanamaz | Aşama 2 eksik kalabilir | Best effort; harici ekran bulununca doğrulanır |
| SwiftUI pencereleri bellek bütçesini zorlar | Perf hedefi | Pencereler kapanınca serbest; `make perf` pencereler kapalıyken ölçer |
