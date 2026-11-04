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
