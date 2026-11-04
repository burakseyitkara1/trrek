# Karar Kaydı

Geliştirme sırasında kontrolörün verdiği kararlar; her madde ne kararlaştırıldığını, nedenini ve yanlışsa bedelini söyler. Yeni kararlar sona eklenir.

## Süreç

1. **Görev başına dal ve PR, squash merge.** GitHub kendi PR'ını onaylamaya izin vermediği için "onay", bağımsız inceleyicinin özetinin PR yorumu olarak yazılması ve merge'dir. Bedel: yok.
2. **`.superpowers/` git dışında** (`.git/info/exclude`). Araç dosyaları depoya girmez. Bedel: yok.
3. **CI `macos-26-intel` imajında çalışır.** macOS arm64 runner'ları iki denemede de işi almadı; Intel imaj uygulamayı arm64 için çapraz derler, Engine testleri x86_64'te koşar. Bedel: CI arm64 ikilisini çalıştırmaz (motor saf Swift, risk düşük).
4. **Paketleme PR'ı (#4) yerel doğrulamayla merge edildi.** CI hiç koşamadığı için `make check`, `make app`, `plutil -lint`, YAML parse esas alındı; workflow bir sonraki PR'da gerçek runner'da doğrulandı. Bedel: olası bir ci.yml hatası bir PR gecikmeli görünürdü.
5. **Command Line Tools makinelerde `make test` Testing makro eklenti yolunu açıkça verir.** Yeni derleme sistemi eklentiyi dönüşümlü olarak atlıyordu; Xcode'lu makineler etkilenmez. Bedel: yok.
6. **Geçici dal zinciri.** CI main'e girene kadar görev dalları bir önceki görevden türedi ve merge sonrası main'e rebase edildi. Bedel: sırayla rebase.
7. **Model seçimi işe göre.** Rutin görevler orta model, private API / eşzamanlılık / SwiftUI tasarımı güçlü model; bütün incelemeler en güçlü model. Bedel: fazladan düzeltme turu riski.

## Jest motoru

8. **Adım döngüsünde 0,001 mm tolerans.** Normalize koordinatların Float yuvarlaması tam katları kaçırıyordu. Bedel: tam sınırda 1/1000 mm erken adım.
9. **Çift dokunma penceresi ilk dokunmanın kalkışından ikincinin inişine ölçülür.** Spec ifadesi belirsizdi; kalkış→iniş kullanıcı algısına uyar. Bedel: pencere biraz daha uzun hissedilir.
10. **Motor kendi kilidine sahiptir** (`OSAllocatedUnfairLock`, her public çağrı). Host sinyalleri tam durum geçişi yaptığı için bayrak yazımı varsayımı yarışa yol açıyordu. Bedel: çağrı başına nanosaniyeler.
11. **Saat sözleşmesi: motor zamanı = multitouch kare saati.** Kare saati sistem uptime'ı değildir (sabit ofset); `GesturePipeline.engineTime(fromUptime:)` ofseti karelerden öğrenir, ilk kareden önce `nil` döner ve o ana kadarki tuş olayları atılır. Bedel: yazma kapısı ilk kareye kadar etkisiz.
12. **`bottomQuarterOnly` yalnızca dikey kenar slide'larını kısıtlar; köşeler köşe kalır.** Kontrol slide eşiğine ulaşıldığında yapılır ki köşe çift dokunmaları titremeyle iptal olmasın. Bedel: seçenek açıkken üst köşe dokunmaları korunur, üst köşeden dikey slide başlamaz.
13. **`reset()` iptal eder** (`appSwitchCancel`/`scrubCancel`), `update(config:)` commit eder ve adayı düşürür. ⌘ basılı kalmasın. Bedel: yok.
14. **`lastTap` `spent`/`threeFinger` girişinde temizlenir.** Araya giren jest çift dokunma sayılmaz. Bedel: yok.
15. **Kare başına en fazla 64 adım; sınıra takılınca birikim sıfırlanır; sonlu olmayan koordinat slide'ı iptal eder.** Bozuk veri motoru kilitleyemez ve komut yağdıramaz. Bedel: yok.

## Platform

16. **Klavye arka ışığı için Yol B (CoreBrightness + kendi overlay) birincil.** Medya tuşu yolunun HUD'u izin olmadan doğrulanamadı. Bedel: sistem HUD'u yerine kendi overlay'imiz.
17. **İmleç dondurma tap'i HID konumunda** (`.cghidEventTap`). Oturum düzeyinde yutulan hareket imleci durdurmayabilir. Bedel: yok.
18. **Watchdog slide başında bir kez kurulur ve kalan süre için kendini yeniden kurar** (her karede yeniden kurmak ayırma yapıyordu); süre yalnızca slide'ı yürüten cihazın saatinden hesaplanır. Bedel: aktif slide sırasında ~180 ms'de bir boş uyanma.
19. **Haptik dalga formları Light/Medium/Strong → 4/5/6**, Strong'da ikinci darbe. His kullanıcı ayarına bırakıldı. Bedel: yok.
20. **`GesturePipeline.withEngine`** kilit altında erişim yardımcısı olarak kalır; motor artık kendi kilidine sahip olduğundan zorunlu değildir. Bedel: yok.

## Sürüm

21. **`TrrekVersion.string` sürüm PR'larında elle güncellenir; paket sürümü etiketten gelir.** Bedel: yalnızca "About"ta görünen bir uyumsuzluk.

## Son inceleme

22. **Bellek `phys_footprint` olarak ölçülür, RSS olarak değil.** RSS paylaşılan sistem çerçevesi sayfalarını da sayar ve uygulamanın kendi maliyetini abartır; 15 MB bütçesi ayak izine uygulanır (spec 9.4 notu). Bedel: eski RSS rakamlarıyla doğrudan karşılaştırılamaz.
23. **Kararlı yerel imza kimliği ("trrek Local Signing").** Ad-hoc imza her derlemede kod özetini değiştirir ve Accessibility iznini düşürür; yerel kimlik izni korur. Kimlikle imzalama başarısız olursa (anahtar zinciri istemi reddedildi gibi) derleme uyarıyla ad-hoc'a düşer. Bedel: ilk imzada bir kerelik anahtar zinciri istemi ("Always Allow").
24. **`v0.1.0` etiketi yalnızca son inceleme ve elle kontrol listesi tamamlandıktan sonra atılır.** Etiket sürüm iş akışını tetikler; geri almak pahalıdır. Bedel: sürüm biraz gecikir.
25. **Tuş olayı zamanı = varış zamanı.** `InputMonitor`, tap callback'i içinde okunan `ProcessInfo.processInfo.systemUptime` değerini iletir; `CGEvent.timestamp`'in saati belgelenmediği için ona dayanılmaz (`TrrekProbe keys` ikisini de yazdırır). Bedel: zaman damgası callback gecikmesi kadar geç (milisaniye altı), yazma kapısı için önemsiz.
26. **Yalnızca trackpad'ler jest üretir.** Tür, `AppleMultitouchDevice` kaydındaki genel HID özelliklerinden belirlenir: `HIDPointerAccelerationType` = `HIDTrackpadAcceleration` ya da `DeviceUsagePairs` içinde Digitizer/Touch Pad (0x0D/0x05) kullanımı varsa trackpad; özelliklerden biri var ama sinyal yoksa trackpad değil (ör. dokunmatik yüzeyli fare); ikisi de yoksa cihaz kullanılır ve log yazılır. "Family ID" kullanılmadı: değerler donanım kuşağına göre değişir ve yayımlanmış bir listesi yoktur (buradaki yerleşik trackpad 110 bildirir); bir beyaz liste yeni donanımda trackpad'i kapatırdı. Cihazlar kayıt girdileriyle multitouch kimliği üzerinden eşleştirilir. Bedel: sınıflandırıcı fare için elde doğrulanamadı; temsilî sözlüklerle test edildi.
27. **İzinsiz durumda sentetik olay gönderen her eylem kapalıdır.** Klavye ışığı (doğrudan ayarlanır) dışındaki bütün kenarlar, bütün köşeler, orta tık ve imleç dondurma `.off`; diyagram etkin eylemleri gösterir. İzinsiz gönderilen olaylar teslim edilmediği için açık görünen ama çalışmayan kontroller yanıltıcıydı. Bedel: izin verilene kadar trrek neredeyse hiçbir şey yapmaz; karşılama penceresi bunu her açılışta anlatır.
28. **İnceleyici iddiaları kaynağa karşı doğrulanır; yanlışsa gerekçesiyle reddedilir.** Bir bulgu ancak kodda ya da ölçümde doğrulanınca düzeltilir. Bedel: inceleme turu biraz uzar.
29. **İmleç dondurma, fare ile imleç bağlantısını keserek yapılır.** Slide başlarken konum kaydedilir ve `CGAssociateMouseAndMouseCursorPosition(false)` çağrılır; bırakınca bağlantı geri kurulur. Tap yine kaydırmayı yutar ve olur da imleç kayarsa kaydedilen konuma geri koyar. Yalnızca olayları yutmak imleci durdurmuyordu (elle testte görüldü). Bedel: yok.
30. **Sabit imza kimliğine geçişte Accessibility kaydı bir kez sıfırlanır.** Eski ad-hoc kayıt yeni imzaya uymaz; README bunu anlatır. Bedel: kullanıcı geçişte izni bir kez yeniden verir.
31. **Sürümler Developer ID ile imzalanır, notarize edilir ve sürüm Mac'inden yayınlanır.** `scripts/release.sh` hardened runtime ve zaman damgasıyla imzalar, uygulamayı ve DMG'yi notarize edip zımbalar, etiketi atar ve GitHub release'i oluşturur. Sertifika ve notarizasyon bilgisi GitHub'a yüklenmez; etiketle tetiklenen iş akışı yalnızca derleme ve testi doğrular. Bedel: yayın yalnızca o Mac'ten yapılabilir.
32. **Yerel derlemeler de önce Developer ID kimliğiyle imzalanır.** Yerel ve yayınlanan derleme aynı imza gereksinimini taşıdığından tek bir Accessibility izni ikisinde de geçerlidir. Bedel: kimlik değişiminde izin bir kez sıfırlanır.
33. **Video sarma (Scrub Video) öndeki uygulamaya ←/→ ok tuşu göndererek yapılır.** Spec'teki ilk tasarım, Apple'ın Now Playing erişim kısıtını sistem yorumlayıcısı üzerinden yüklenen bir yardımcıyla aşmayı öngörüyordu; bu, hardened runtime/notarizasyonla çatışır ve ek süreç gerektirir. Ok tuşları public, izin zaten var ve tarayıcılarda ve çoğu oynatıcıda çalışır. Bedel: adım boyunu uygulama belirler (çoğunda 5 s), sarma yalnızca öndeki uygulamada çalışır; overlay etiketi adım başına 5 s varsayar.
34. **Harici monitör parlaklığı DDC/CI ile "best effort" olarak eklendi.** Paketler VESA DDC/CI tanımından kurulur (kaynak 0x51, uzunluk baytında 0x80, sağlama toplamı hedef adres 0x6E'den başlayan XOR; yanıt sağlama toplamı 0x50'den başlar) ve saf testlerle doğrulanır. Servisler IORegistry'deki harici `DCPAVServiceProxy` girdilerinden alınır, EDID üretici/ürün/seri ile ekranlara eşlenir, eşleşmeyenler sırayla eşlenir. I2C aktarımları bekleme (`usleep`) gerektirdiğinden dağıtıcı DDC işini kendi seri `DispatchQueue`'suna verir ve hemen döner; overlay o kuyruktan güncellenir. Maksimum değer bir kez, mevcut değer slide başında (1,5 sn'den uzun aradan sonra) okunur. Kuyruk meşgulken gelen adımlar ekran ve hassasiyet başına tek bekleyen adımda birleştirilir (hızlı slide gecikmez, yön değişince eski yönde sürmez). Başarısız aktarımdan sonra o ekranın adımları sonraki slide'a kadar bus'a dokunmadan "No DDC" ile döner; sonraki slide başında servisler yeniden taranır (en fazla 5 sn'de bir). Ekran yeniden yapılandırma bildirimi (takma, çıkarma, uyanma) de yeniden taramayı tetikler; zamanlayıcı yoktur. Bu Mac'te harici ekran olmadığı için donanımda doğrulanamadı; `TrrekProbe ddc list` ve elle test listesindeki maddeler (2.2a, 2.2b) harici monitör bulununca uygulanır. Bedel: monitörlerin DDC/CI uygulamaları farklıdır; desteklemeyen ya da yanıtı standarda uymayan monitörde overlay "No DDC" gösterir; servis–ekran eşlemesi kayıt sırasına dayanan bir sezgidir.
