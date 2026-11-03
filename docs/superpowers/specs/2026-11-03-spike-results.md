# Aşama 0 Spike Sonuçları (TrrekProbe)

Tarih: 2026-11-03 · Makine: MacBook Air M4, macOS 27.2 · Araç: `TrrekProbe` (debug derlemesi)

| # | Soru (spec 11) | Sonuç | Karar |
|---|---|---|---|
| 1 | `MTTouch` düzeni ve yüzey birimi | 96 bayt derlemede doğrulandı (`_Static_assert`). 90 s canlı akışta: `nx` 0.41–0.84, `ny` 0.00–0.91, parmak ucu `major` 8–11.6 mm, `minor` 5–8.7 mm; `state` değerleri 1,2,3,4,5,6,7 beklendiği gibi. Yüzey `12194×7408` → 1/100 mm → 121.94×74.08 mm. | Düzen ve birim doğru; `MultitouchDevices` 100'e böler. |
| 2 | Kalkışta sıfır dokunmalı kare | Her kalkışta `state=5` (break) → `6` → `7` (major/minor 0) ve ardından `n=0` karesi geliyor; sonra cihaz uyuyor (90 s'de 9 boşluk; kare aralığı 8 ms = 125 Hz). | Platform yalnızca state 3/4'ü `Frame`'e koyar; parmak state 5'te kaybolur → `lost`. Watchdog yedek olarak kalır. Hover (state 1/2) ikinci parmak sayılmaz. |
| 3 | Haptik dalga formları | `actuate 4/5/6` → `ok` (dönüş 0). His, kullanıcı tarafından ayarlardan seçilir. | Light→4, Medium→5, Strong→6 (başlangıç); ayar penceresinden değiştirilebilir. |
| 4 | Medya tuşu olayları HUD gösteriyor mu | **Doğrulanamadı.** Probe süreci Accessibility'ye güvenilir değil (`accessibility trusted: false`); macOS güvenilmeyen süreçten gelen sentetik olayları düşürüyor, ekran görüntülerinde HUD yok. | Ses/parlaklık için medya tuşu yolu tasarımda kalır (izin zaten gerekli). Klavye ışığı için **Yol B (CoreBrightness + kendi overlay)** birincil; Yol A izin alınınca denenecek. |
| 5 | ⌥⇧ ile çeyrek adım | Aynı nedenle doğrulanamadı. | Uygulama kurulup izin verilince `docs/testing.md` ile elle kontrol. |
| 6 | İmleç dondurma | Doğrulanamadı (izin). İnceleme notu: session düzeyinde yutulan `mouseMoved` imleci durdurmayabilir. | Tap B `.cghidEventTap` konumuna alındı (olay WindowServer'a ulaşmadan yutulur). Elle kontrol listesine eklendi. |
| 7 | ⌘ basılı + Tab ile seçici | Doğrulanamadı (izin). | Elle kontrol listesine eklendi. |
| 8 | Boşta bellek | `TrrekProbe mem` → phys_footprint 1.6 MB (CLI, AppKit yok). | AppKit menü çubuğu uygulaması `make perf` ile ölçülecek; bütçe 15 MB. |

## Eşik güncellemeleri

Ölçülen parmak ucu büyük ekseni 8–11.6 mm; `palmMajorAxisMM = 20` makul bir avuç eşiği olarak kalır. Diğer eşikler değişmedi.

## Açık kalanlar

- 4–7 numaralı maddeler, uygulama paketi (`trrek.app`) kurulup Accessibility izni verildiğinde ilk elle test turunda kapanır.
