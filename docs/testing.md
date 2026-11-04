# trrek elle test listesi

Donanım ve sistem izni gerektiren davranışlar otomatik testlerle doğrulanamaz; her sürümden önce bu liste uygulanır. Ön koşul: `make install`, uygulama menü çubuğunda, Accessibility izni verilmiş (aksi belirtilmedikçe). Ayarlar varsayılanda başlar.

## 1. İlk çalıştırma

### 1.1 Karşılama penceresi yalnızca ilk açılışta çıkar
- **Nasıl:** `defaults delete com.burakseyitkara.trrek` ile ayarları sil, uygulamayı aç, kapat, tekrar aç.
- **Beklenen:** Karşılama penceresi ilk açılışta görünür ve anahtar pencere olur (başlık çubuğu aktif görünür, Return "Done"ı tetikler); izin verilmişken ikinci açılışta görünmez.

### 1.2 Menüden açılan pencereler anahtar pencere olur
- **Nasıl:** Menü çubuğu simgesinden Settings'i ve Welcome'ı aç.
- **Beklenen:** Pencere öne gelir, başlık çubuğu aktif görünür, klavye girdisi pencereye gider.

### 1.3 İzinsiz sonraki açılış
- **Nasıl:** Accessibility iznini kaldır (ya da `make install` ile yeniden kur), trrek'i aç.
- **Beklenen:** Karşılama penceresi yeniden açılır ve "trrek needs Accessibility access to change volume, brightness and the other controls." der; menü çubuğu simgesinin sağ üst köşesinde nokta vardır. İzin verilince nokta kaybolur.

### 1.3a Karşılama animasyonu
- **Nasıl:** Ayarları silip trrek'i aç (karşılama penceresi); sonra Sistem Ayarları › Erişilebilirlik › Ekran › Hareketi Azalt'ı aç ve tekrarla.
- **Beklenen:** Hareket Azaltma kapalıyken kartlar sırayla belirir; açıkken hepsi animasyonsuz, hemen görünür.

### 1.4 Uygulamayı yeniden açmak ayarları açar
- **Nasıl:** trrek çalışırken Uygulamalar klasöründen (`~/Applications/trrek.app`) ya da `open ~/Applications/trrek.app` ile tekrar aç.
- **Beklenen:** Ayarlar penceresi açılır (ya da öne gelir).

## 2. Kenarlar

Her kenarda tek parmağı kenar şeridine koyup kenar boyunca kaydır.

### 2.1 Sağ kenar: ses
- **Nasıl:** Sağ kenarda yukarı/aşağı kaydır.
- **Beklenen:** Sistem ses seviyesi adım adım değişir ve sistemin kendi ses göstergesi görünür; trrek'in overlay'i görünmez.

### 2.2 Sol kenar: parlaklık
- **Nasıl:** Sol kenarda yukarı/aşağı kaydır.
- **Beklenen:** Ekran parlaklığı adım adım değişir ve sistemin kendi parlaklık göstergesi görünür; trrek'in overlay'i görünmez.

### 2.2a Harici monitör parlaklığı (DDC/CI destekli monitör)
- **Nasıl:** DDC/CI destekleyen bir monitör bağla (monitörün kendi menüsünde DDC/CI açık olmalı). Edges sekmesinde External Monitor Brightness'ı aç. İmleci harici ekrana götür ve parlaklık kenarında yukarı/aşağı kaydır; sonra imleci dahili ekrana götürüp tekrarla. `swift run TrrekProbe ddc list` çıktısını not et (ekran, eşlenen servis, `brightness: <mevcut>/<maks>`).
- **Beklenen:** İmleç harici ekrandayken o monitörün parlaklığı adım adım değişir (⌥⇧ ile ince adım); harici ekranın sağ üstünde trrek overlay'i yeni yüzdeyi gösterir; kaydırma takılmaz, diğer kenarlar gecikmeden çalışır. Monitörün kendi düğmeleriyle parlaklık değiştirilip birkaç saniye sonra tekrar kaydırılınca yeni değerden devam eder. İmleç dahili ekrandayken dahili ekranın parlaklığı sistem göstergesiyle değişir. Ayar kapalıyken harici ekranda da medya tuşu yolu kullanılır. Birden çok harici monitörde her biri yalnızca imleç üzerindeyken değişir.

### 2.2b Harici monitör parlaklığı (DDC/CI desteklemeyen monitör)
- **Nasıl:** DDC/CI desteklemeyen (ya da DDC/CI'ı menüsünden kapatılmış) kablolu bir monitör bağla, External Monitor Brightness açık; imleç o ekrandayken parlaklık kenarında kaydır. `swift run TrrekProbe ddc list` çıktısını not et. Sonra `log stream --predicate 'subsystem == "com.burakseyitkara.trrek"'` açıkken birkaç slide daha yap.
- **Beklenen:** Overlay seviye çubuğu olmadan, kesilmeden "No DDC" gösterir; trrek donmaz, çökmez, dahili ekranın parlaklığı değişmez. Probe o ekran için bir hata (`no valid reply` ya da `I2C write failed …`) yazdırır. "external brightness step failed" günlük satırı her adımda değil, hata durumuna girişte bir kez görünür.

### 2.2c Harici ekran, DDC servisi yok (kablosuz/sanal ekran)
- **Nasıl:** Kablosuz yansıtma ya da sanal bir ekran ekle (DDC servisi olmayan ekran), External Monitor Brightness açık; imleç o ekrandayken parlaklık kenarında kaydır. `swift run TrrekProbe ddc list` çıktısını not et.
- **Beklenen:** Probe o ekran için `service: none` yazdırır. "No DDC" görünmez; parlaklık kenarı medya tuşu yolunu kullanır (sistem göstergesi, ekrana göre dahili parlaklık değişebilir).

### 2.2d Overlay imlecin ekranına gider
- **Nasıl:** İki ekranlı düzende (en az biri harici) üst kenarı Keyboard Backlight yap; imleç bir ekrandayken kaydır, overlay görünürken imleci diğer ekrana götürüp tekrar kaydır.
- **Beklenen:** Overlay her seferinde imlecin bulunduğu ekranın sağ üstünde görünür; görünürken bir sonraki değerle diğer ekrana taşınır.

### 2.3 Üst kenar: uygulama değiştirme
- **Nasıl:** Üst kenarda sağa kaydır; kaydırma sürerken ⌘-Tab uygulama değiştiricisinin açıldığını ve seçimin ilerlediğini izle; parmağı kaldır.
- **Beklenen:** Uygulama değiştirici açılır, kaydırma seçimi ilerletir, parmak kalkınca seçilen uygulamaya geçilir. Parmak kalkmadan ikinci parmak konursa değiştirici iptal olur ve ⌘ basılı kalmaz.

### 2.4 Alt kenar: klavye ışığı
- **Nasıl:** Alt kenarda sağa/sola kaydır (alt kenar eylemi Keyboard Backlight; desteklenmeyen Mac'te seçenek devre dışı).
- **Beklenen:** Klavye arka ışığı değişir; trrek'in overlay'i imlecin bulunduğu ekranın sağ üstünde seviye çubuğu ve yüzdeyi ("100%" kesilmeden) gösterir ve son adımdan yaklaşık 1 sn sonra kaybolur. Aralığın sonundaki davranış 2.5'te.

### 2.5 Aralığın sonunda tek sınır haptiği (bütün seviye kenarları)
- **Nasıl:** Haptik Medium. Sağ kenarda sesi en üste çıkar ve parmağı kaldırmadan aynı yönde birkaç cm daha kaydır; sonra yön değiştir; parmağı kaldırıp yeni bir slide'la tekrar en üste it. Aynısını sesi en alta indirerek (sessize almadan), sol kenarda dahili ekran parlaklığıyla (en üst ve en alt), klavye ışığı kenarıyla ve DDC/CI destekli harici monitörde (External Monitor Brightness açık, imleç harici ekranda) yap. Ayrıca ses sessize alınmışken (Mute) en altta kaydır.
- **Beklenen:** Sınıra varan adım normal adım haptiği verir; sınırın ötesine itilen ilk adım tek bir sınır haptiği verir, sonrakiler hiç haptik vermez ve tuş göndermez (seviye "artıyor" hissi yok; overlay olan kenarlarda overlay sınır değerini göstermeye devam eder). Yön değişince adım haptikleri hemen geri gelir. Yeni slide'da sınıra itmek yine tek sınır haptiği verir. Harici monitörde sınır haptiği sınıra varan adımın sonucuyla birlikte gelir. Ses sessizdeyken seviye bilinmediği için eski davranış sürer (her adımda tuş ve haptik).

### 2.6 Üst/alt kenar: video sarma
- **Nasıl:** Edges sekmesinde Top Edge'i Scrub Video yap. Tarayıcıda bir video aç ve oynat; üst kenarda sağa kaydır, sonra sola kaydır.
- **Beklenen:** Her yaklaşık 6 mm'de video ileri (→) ya da geri (←) sarar; overlay simge ve "+15 s" / "−10 s" gibi net süreyi gösterir (çubuk yok; "+100 s" gibi uzun etiketler kesilmez). Parmak kalkınca ek tuş gitmez ve sayaç sıfırlanır. Accessibility izni yokken eylem kapalıdır.

### 2.7 Video sarma, Hold-to-Slide tuşu basılıyken
- **Nasıl:** Advanced'de Hold-to-Slide Key'i Shift (Hold) yap; videoda Shift basılıyken üst kenarda kaydır. Sonra Control ile tekrarla.
- **Beklenen:** Video düz ok tuşu davranışıyla sarar (adım başına aynı süre); metin seçimi ya da Space değişimi olmaz.

### 2.8 Video sarma, trrek penceresi öndeyken
- **Nasıl:** Top Edge Scrub Video; trrek'in ayar penceresini öne getir (Edges sekmesinde bir seçici odaktayken) ve üst kenarda kaydır.
- **Beklenen:** Hiç ok tuşu gitmez (seçici değeri ya da liste seçimi değişmez), overlay görünmez. Başka bir uygulama öne gelince sarma yeniden çalışır.

### 2.9 Medya kenarı: oynat/duraklat
- **Nasıl:** Bir kenarın eylemini Media yap; o kenarda çift dokun.
- **Beklenen:** Çalan medya oynar/duraklar.

## 3. Köşeler

### 3.1 Köşe çift dokunma
- **Nasıl:** Ayarlarda bir köşeye Mute, diğerine Screenshot ata; her köşede çift dokun.
- **Beklenen:** Mute ses kapatır/açar; Screenshot ekran görüntüsü arayüzünü açar. Köşeye tek dokunma bir şey yapmaz.

### 3.2 Köşe rozeti tıklaması eylemi döndürür
- **Nasıl:** Corners & Taps sekmesinde bir köşenin rozetine tıkla.
- **Beklenen:** Eylem her tıklamada Off → Mute → Screenshot → Off sırasıyla döner; rozetin simgesi eylemi gösterir.

### 3.3 Bottom Quarter Only yan kenarları alt çeyreğe sınırlar
- **Nasıl:** Edges sekmesinde Bottom Quarter Only'yi aç; sağ kenarın üst yarısında kaydırmayı dene, sonra alt çeyreğinde dene; üst köşeye çift dokun.
- **Beklenen:** Yan kenarlar yalnızca alt çeyrekte yanıt verir; köşe çift dokunmaları yine de çalışır.

## 4. Diğer jestler

### 4.1 Üç parmak dokunma: orta tık
- **Nasıl:** Etkinleştir; bir bağlantı üzerinde üç parmakla dokun.
- **Beklenen:** Orta tık gönderilir (bağlantı yeni sekmede açılır).

### 4.2 Precision Control ince adımlar (⌥⇧)
- **Nasıl:** Menüden ya da General sekmesinden Precision Control'ü aç; sağ kenarda kaydır, sonra kapat ve tekrar kaydır.
- **Beklenen:** Açıkken her adım seviyeyi çeyrek adım değiştirir (sistem, ses/parlaklık tuşunu ⌥⇧ ile gönderilmiş gibi işler); kapalıyken normal adımlar.

### 4.3 İmleç slide sırasında donar
- **Nasıl:** Kenarda kaydırırken parmağın imleci de oynattığını gözle.
- **Beklenen:** Slide süresince imleç yerinde kalır; parmak kalkınca hareket geri gelir.

### 4.4 Scroll bastırma
- **Nasıl:** Freeze Cursor açıkken sağ kenarda kaydır; arkada kaydırılabilir bir pencere açık olsun. Sonra Freeze Cursor'ı kapatıp tekrarla.
- **Beklenen:** Freeze Cursor açıkken arkadaki pencere kaymaz; kapalıyken scroll bastırılmaz.

## 5. Kapılar

### 5.1 Yazma kapısı
- **Nasıl:** Yazarken (son tuştan sonra kısa süre içinde) kenara dokun.
- **Beklenen:** Yeni jest başlamaz; yazmayı bıraktıktan kısa süre sonra jestler çalışır.

### 5.2 Palm reddi
- **Nasıl:** Kenara avuç içi ile temas et.
- **Beklenen:** Jest başlamaz.

### 5.3 Hold modu
- **Nasıl:** Advanced sekmesinde Hold-to-Slide Key olarak bir tuş (ör. Option) ve Mode olarak Hold seç; tuşa basmadan, sonra basılıyken kenarda kaydır.
- **Beklenen:** Tuş basılı değilken jest yok; basılıyken çalışır. Hold modunda menüde Hold-to-Slide satırı yoktur.

### 5.4 Toggle modu
- **Nasıl:** Mode'u Toggle yap; menüyü aç, tuşa bir kez bas, kaydır; tekrar bas.
- **Beklenen:** İlk basıştan sonra jestler açık, ikinci basışta kapalı. Menüde yalnızca Toggle modunda (ve bir tuş seçiliyken) "Hold-to-Slide: On" / "Hold-to-Slide: Off" satırı görünür. Tuş basılıyken tıklamak (ör. ⌘-tık) ya da başka bir modifier eklemek durumu değiştirmez.

### 5.5 Pause in app
- **Nasıl:** Advanced › Paused Apps listesine `+` ile bir uygulama ekle; o uygulama öndeyken kenarda kaydır; `−` ile çıkar.
- **Beklenen:** Listedeki uygulama öndeyken jestler çalışmaz, çıkarılınca çalışır. `+`/`−` listeyi doğru günceller. `+` uygulama seçicisini ayrı bir pencere olarak değil, ayarlar penceresine bağlı bir sayfa (sheet) olarak açar; seçicide `trrek.app` seçilirse listeye eklenmez.

### 5.5a trrek penceresi öndeyken duraklatma korunur
- **Nasıl:** Paused Apps listesine bir uygulama ekle ve onu öne getir; menüden Settings'i (ya da Show Welcome'ı, About trrek'i) aç ve pencere öndeyken kenarda kaydır; menünün durum satırına bak. Sonra listede olmayan bir uygulamayı öne getirip aynısını yap.
- **Beklenen:** Duraklatılmış uygulamanın üstünde trrek penceresi öndeyken jestler çalışmamaya devam eder ve durum satırı "Paused in <uygulama>" der; listede olmayan uygulamanın üstünde jestler çalışır. Pencere öndeyken uygulama listeden `−` ile çıkarılınca jestler hemen çalışır.

## 6. Sistem olayları

### 6.1 Uykudan sonra
- **Nasıl:** Mac'i uyut, uyandır, kenarda kaydır.
- **Beklenen:** Jestler yeniden çalışır; yeniden başlatma gerekmez. Toggle modunda açık olan Hold-to-Slide uykudan sonra da açık kalır.

### 6.2 Trackpad takma/çıkarma
- **Nasıl:** Harici bir trackpad bağla, kenarda kaydır, çıkar, tekrar bağla.
- **Beklenen:** Harici cihazda da jestler çalışır; çıkarma sırasında takılma ya da çökme olmaz.

### 6.2a Harici trackpad'de haptik
- **Nasıl:** Dahili trackpad'li bir Mac'e harici bir trackpad bağla (Haptic Medium). Harici trackpad'in sağ kenarında kaydır, sonra dahili trackpad'de kaydır; köşe çift dokunmalarını ve sınır haptiğini (2.5) her iki yüzeyde dene. Sonra harici trackpad'i çıkarıp takarak ya da Mac'i uyutup uyandırarak tekrarla.
- **Beklenen:** Haptik her seferinde parmağın kaydığı trackpad'de hissedilir; harici trackpad'de kaydırırken dahili trackpad titreşmez ve tersi. Çıkarma/takma ve uykudan sonra da her yüzey kendi haptiğini verir.

### 6.3 Accessibility izni geri alındı / verildi
- **Nasıl:** Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'ten trrek iznini kaldır; sonra tekrar ver.
- **Beklenen:** Menüde durum satırı "Accessibility access needed" olur, "Grant Accessibility…" öğesi ve simgede nokta görünür. Yalnızca klavye ışığı kenarı çalışır; diğer kenarlar, köşeler, orta tık ve imleç dondurma çalışmaz ve Edges/Corners diyagramı bunları "Off" gösterir (Advanced ve General sekmeleri izin gerektiğini söyler). İzin verilince uygulamayı yeniden başlatmadan jestler geri gelir, durum satırı "trrek is active" olur, "Grant Accessibility…" ve nokta kaybolur.

### 6.4 Launch at Login
- **Nasıl:** General'da aç, oturumu kapat/aç; sonra kapat ve tekrar dene. Ayrıca ayarlar penceresi kapalıyken Sistem Ayarları › Giriş Öğeleri'nden trrek'i kapat, sonra ayarları aç.
- **Beklenen:** Açıkken uygulama oturum açılışında başlar, kapalıyken başlamaz; Sistem Ayarları › Giriş Öğeleri ile tutarlıdır. Pencere açıldığında Launch at Login anahtarı sistemdeki durumu gösterir.

### 6.5 Trackpad bulunamadı → takınca kendiliğinden başlar
- **Nasıl:** Trackpad'i olmayan bir Mac'te (ya da harici trackpad çıkarılmışken) trrek'i aç; menüde durum satırına bak; sonra harici bir trackpad bağla.
- **Beklenen:** Önce "Trackpad not found" görünür; trackpad bağlanınca uygulamayı yeniden başlatmadan jestler çalışır ve durum satırı "trrek is active" olur.

### 6.6 Uygulama değiştirme sırasında çıkış
- **Nasıl:** Terminalde `sleep 3; osascript -e 'quit app "trrek"'` çalıştır; hemen üst kenarda Switch Apps slide'ı başlat ve parmağı trackpad'de tut.
- **Beklenen:** trrek kapanınca uygulama değiştirici kapanır; ⌘ basılı kalmaz (sonraki tuş vuruşları ⌘ kısayolu olarak işlenmez).

### 6.6a Sinyalle çıkış (SIGTERM/SIGINT)
- **Nasıl:** Terminalde `sleep 3; pkill -TERM -x trrek` çalıştır; hemen üst kenarda Switch Apps slide'ı başlat ve parmağı trackpad'de tut. Aynısını `pkill -INT -x trrek` ile tekrarla.
- **Beklenen:** trrek kapanır, uygulama değiştirici kapanır, ⌘ basılı kalmaz. `/usr/bin/log show --last 1m --predicate 'subsystem == "com.burakseyitkara.trrek"'` çıktısında "signal 15; quitting" (INT için 2) satırı görünür. Komutu tam yoluyla yaz: zsh'in kendi `log` komutu sistem aracını gölgeler. trrek açıldıktan sonra birkaç saniye bekle; sinyal işleyicisi kurulmadan gelen SIGTERM uygulamayı kayıt yazmadan kapatır.

### 6.7 Dokunmatik yüzeyli fare bağlı
- **Nasıl:** Dokunmatik yüzeyli bir fare bağla; `swift run TrrekProbe devices` çıktısına bak; farenin yüzeyinde kenar boyunca kaydır ve köşelere çift dokun; sonra trackpad'de kaydır.
- **Beklenen:** Fare `kind=other` olarak listelenir ve dokunuşları hiçbir şey yapmaz; trackpad jestleri etkilenmez. Yalnızca fare bağlıyken (trackpad yokken) durum satırı "Trackpad not found" der.

## 7. Ayarlar penceresi

### 7.1 Sekmeler
- **Nasıl:** General, Edges, Corners & Taps ve Advanced sekmelerini gez; değerleri değiştir.
- **Beklenen:** Değişiklikler anında etki eder, pencere kapanıp açılınca korunur.

### 7.2 Seçeneklerin notları ve devre dışı olanlar
- **Nasıl:** Edges sekmesinde Top Edge ve Bottom Edge seçicilerini aç.
- **Beklenen:** Seçenek adının yanında not belirtilir: "Scrub Video — Uses ← and → in the front app" seçilebilir. Klavye arka ışığı olmayan Mac'te "Keyboard Backlight — Not available on this Mac" devre dışıdır ve seçili değer Media olarak gösterilir.

### 7.2a Accessibility gerektiren kenar notu
- **Nasıl:** Accessibility iznini kaldır; Edges sekmesinde Top Edge'i Switch Apps ya da Scrub Video yap.
- **Beklenen:** Seçicinin başlığı altında "Needs Accessibility access" notu görünür; Keyboard Backlight seçiliyken görünmez. İzin verilince not kaybolur.

### 7.2b External Monitor Brightness kullanılamıyor
- **Nasıl:** DDC sembolleri olmayan bir sistemde (ya da günlükte "external brightness available: false" görülen bir derlemede) Edges sekmesini aç.
- **Beklenen:** External Monitor Brightness anahtarı kapalı ve devre dışıdır, altında "Not available on this Mac" yazar.

### 7.3 Reset to Defaults
- **Nasıl:** Birkaç ayarı değiştir; General sekmesinde Reset to Defaults…'a bas.
- **Beklenen:** Onay uyarısı çıkar; iptal edince değişiklik olmaz, onaylayınca tüm ayarlar varsayılana döner.

### 7.4 Ayarları dışa aktarma
- **Nasıl:** General sekmesinde Export Settings…'e bas; trrek arka plandayken de dene.
- **Beklenen:** Kaydetme paneli ayarlar penceresine sheet olarak bağlanır, önerilen ad "trrek Settings.trrek"tir. Kaydedilen dosya girintili JSON'dur; `format`, `formatVersion`, `appVersion` ve `settings` anahtarları vardır, `launchAtLogin` ve `welcomeShown` yoktur.

### 7.5 Ayarları içe aktarma
- **Nasıl:** Dışa aktardıktan sonra birkaç ayarı değiştir; Import Settings…'e bas ve dosyayı seç. Bir kez Cancel, bir kez Replace de.
- **Beklenen:** Açma paneli sheet olarak gelir ve yalnızca `.trrek` dosyaları seçilebilir. "Replace your current settings with the ones in “…”?" onayı çıkar; Cancel hiçbir şeyi değiştirmez, Replace dışa aktarılan ayarları geri getirir ve kenarlar hemen yeni ayarlarla çalışır. Launch at Login değişmez.

### 7.6 Geçersiz dosyayı içe aktarma
- **Nasıl:** Boş bir dosyayı, rastgele metni, 1 MB'tan büyük bir dosyayı, `"format"` değeri farklı bir JSON'u ve `"formatVersion": 2` yazılmış bir dosyayı `.trrek` uzantısıyla kaydedip sırayla içe aktar.
- **Beklenen:** Uygulama çökmez; "“…” could not be imported." uyarısı nedenini söyler (bozuk/başka dosya ya da daha yeni sürüm) ve ayarlar değişmez.

### 7.7 Finder'dan çift tıklama
- **Nasıl:** trrek çalışırken ve kapalıyken Finder'da bir `.trrek` dosyasına çift tıkla; ayarlar penceresi Edges sekmesindeyken de dene.
- **Beklenen:** Dosyanın türü "trrek Settings" görünür; trrek açılır ya da öne gelir, ayarlar penceresi General sekmesinde açılır ve aynı onay çıkar. Kapalıyken açılışta karşılama penceresi gerekiyorsa o da çıkar, onay ayarlar penceresindedir. Onay açıkken ikinci bir `.trrek` dosyasına çift tıklamak onayı değiştirmez (yok sayılır); Replace ilk dosyayı uygular.

## 8. Araçlar

### 8.1 TrrekProbe tuş zamanı
- **Nasıl:** Terminale Accessibility izni ver; `swift run TrrekProbe keys 10` çalıştır, birkaç tuşa bas ve tıkla. Satır biçimi: `arrival=<varış zamanı> event=<olayın kendi zaman damgası> keyDown` (modifier için `flagsChanged`, fare tuşu için `mouseDown`).
- **Beklenen:** `arrival=` saniye cinsinden sistem uptime'ıdır (tap callback'i içinde okunur) ve trrek'in kullandığı tek değerdir. `event=` yalnızca merak için yazdırılır; saati belgelenmediği için trrek ona dayanmaz. `arrival=` değerleri artan sırada ve `uptime` ile aynı büyüklükte olmalıdır.
- **Ek (kare saati):** `swift run TrrekProbe pipeline 5` başlarken tek dokunuş iste; çıktı `clock: frame timestamp X, system uptime Y (difference Z s), uptime including sleep W (difference V s)` biçimindedir. Fark sabit bir ofset olmalıdır; motor bu ofseti kendisi öğrenir.

### 8.2 TrrekProbe klavye ışığı ölçümü
- **Nasıl:** `swift build && .build/debug/TrrekProbe backlight bench` (klavye ışığı olan Mac'te).
- **Beklenen:** İki satır yazdırır: istemciden okuma + yazma (`raw read+write`) ve önbellekten adım (`step from cache`), her biri 50 döngünün min/avg/max değeriyle. Önbellekten adımın ortalaması 0,1 ms'nin altındadır. Son satır `failures=0 restored=<başlangıç> ok` olur ve klavye ışığı başlangıç seviyesine döner.

## 9. Performans

### 9.1 Boşta bütçe
- **Nasıl:** Çalışan örneği kapat; `make perf`.
- **Beklenen:** CPU en fazla %1 (genelde 0.0), fiziksel ayak izi 15 MB altı.
