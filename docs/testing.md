# trrek elle test listesi

Donanım ve sistem izni gerektiren davranışlar otomatik testlerle doğrulanamaz; her sürümden önce bu liste uygulanır. Ön koşul: `make install`, uygulama menü çubuğunda, Accessibility izni verilmiş (aksi belirtilmedikçe). Ayarlar varsayılanda başlar.

## 1. İlk çalıştırma

### 1.1 Karşılama penceresi yalnızca ilk açılışta çıkar
- **Nasıl:** `defaults delete com.burakseyitkara.trrek` ile ayarları sil, uygulamayı aç, kapat, tekrar aç.
- **Beklenen:** Karşılama penceresi ilk açılışta görünür ve anahtar pencere olur (yazı alanına odaklanılabilir); ikinci açılışta görünmez.

### 1.2 Menüden açılan pencereler anahtar pencere olur
- **Nasıl:** Menü çubuğu simgesinden Settings'i ve Welcome'ı aç.
- **Beklenen:** Pencere öne gelir, başlık çubuğu aktif görünür, klavye girdisi pencereye gider.

## 2. Kenarlar

Her kenarda tek parmağı kenar şeridine koyup kenar boyunca kaydır.

### 2.1 Sağ kenar: ses
- **Nasıl:** Sağ kenarda yukarı/aşağı kaydır.
- **Beklenen:** Sistem ses seviyesi adım adım değişir; overlay sağ üstte belirir ve son adımdan yaklaşık 1 sn sonra kaybolur.

### 2.2 Sol kenar: parlaklık
- **Nasıl:** Sol kenarda yukarı/aşağı kaydır.
- **Beklenen:** Ekran parlaklığı adım adım değişir, overlay görünür.

### 2.3 Üst kenar: uygulama değiştirme
- **Nasıl:** Üst kenarda sağa kaydır; kaydırma sürerken ⌘-Tab uygulama değiştiricisinin açıldığını ve seçimin ilerlediğini izle; parmağı kaldır.
- **Beklenen:** Uygulama değiştirici açılır, kaydırma seçimi ilerletir, parmak kalkınca seçilen uygulamaya geçilir. Parmak kalkmadan ikinci parmak konursa değiştirici iptal olur ve ⌘ basılı kalmaz.

### 2.4 Alt kenar: klavye ışığı
- **Nasıl:** Alt kenarda sağa/sola kaydır (alt kenar eylemi Keyboard Backlight; desteklenmeyen Mac'te seçenek devre dışı).
- **Beklenen:** Klavye arka ışığı değişir, overlay seviyeyi gösterir.

### 2.5 Medya kenarı: oynat/duraklat
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
- **Nasıl:** Sağ kenarda kaydır; arkada kaydırılabilir bir pencere açık olsun.
- **Beklenen:** Arkadaki pencere kaymaz.

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
- **Beklenen:** İlk basıştan sonra jestler açık, ikinci basışta kapalı. Menüde yalnızca Toggle modunda (ve bir tuş seçiliyken) "Hold-to-Slide: On" / "Hold-to-Slide: Off" satırı görünür.

### 5.5 Pause in app
- **Nasıl:** Advanced › Paused Apps listesine `+` ile bir uygulama ekle; o uygulama öndeyken kenarda kaydır; `−` ile çıkar.
- **Beklenen:** Listedeki uygulama öndeyken jestler çalışmaz, çıkarılınca çalışır. `+`/`−` listeyi doğru günceller.

## 6. Sistem olayları

### 6.1 Uykudan sonra
- **Nasıl:** Mac'i uyut, uyandır, kenarda kaydır.
- **Beklenen:** Jestler yeniden çalışır; yeniden başlatma gerekmez.

### 6.2 Trackpad takma/çıkarma
- **Nasıl:** Harici Magic Trackpad'i bağla, kenarda kaydır, çıkar, tekrar bağla.
- **Beklenen:** Harici cihazda da jestler çalışır; çıkarma sırasında takılma ya da çökme olmaz.

### 6.3 Accessibility izni geri alındı / verildi
- **Nasıl:** Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'ten trrek iznini kaldır; sonra tekrar ver.
- **Beklenen:** Menüde durum satırı "Accessibility access needed" olur, "Grant Accessibility…" öğesi görünür ve jestler devre dışıdır (Advanced sekmesi de "Accessibility access needed" der); izin verilince uygulamayı yeniden başlatmadan jestler geri gelir, durum satırı "trrek is active" olur ve "Grant Accessibility…" kaybolur.

### 6.4 Launch at Login
- **Nasıl:** General'da aç, oturumu kapat/aç; sonra kapat ve tekrar dene.
- **Beklenen:** Açıkken uygulama oturum açılışında başlar, kapalıyken başlamaz; Sistem Ayarları › Giriş Öğeleri ile tutarlıdır.

## 7. Ayarlar penceresi

### 7.1 Sekmeler
- **Nasıl:** General, Edges, Corners & Taps ve Advanced sekmelerini gez; değerleri değiştir.
- **Beklenen:** Değişiklikler anında etki eder, pencere kapanıp açılınca korunur.

### 7.2 Devre dışı seçenekler başlık gösterir ve seçilemez
- **Nasıl:** Edges sekmesinde Top Edge ve Bottom Edge seçicilerini aç.
- **Beklenen:** Seçenek adının yanında neden belirtilir: "Scrub Video — Coming later" her zaman devre dışıdır ve seçilemez. Klavye arka ışığı olmayan Mac'te "Keyboard Backlight — Not available on this Mac" devre dışıdır ve seçili değer Media olarak gösterilir.

### 7.3 Reset to Defaults
- **Nasıl:** Birkaç ayarı değiştir; General sekmesinde Reset to Defaults…'a bas.
- **Beklenen:** Onay uyarısı çıkar; iptal edince değişiklik olmaz, onaylayınca tüm ayarlar varsayılana döner.

## 8. Araçlar

### 8.1 TrrekProbe zaman birimi
- **Nasıl:** Terminale Accessibility izni ver; `swift run TrrekProbe keys 10` çalıştır, birkaç tuşa bas. Satır biçimi: `t=<olay zamanı> uptime=<yazdırma anındaki uptime> keyDown` (modifier için `flagsChanged`).
- **Beklenen:** `t=` ve `uptime=` saniye cinsinden, aynı büyüklükte ve birbirine çok yakındır (fark yazdırma gecikmesi kadar). Büyük bir fark ya da birim uyuşmazlığı varsa zaman damgası sözleşmesinde hata vardır.
- **Ek (kare saati):** `swift run TrrekProbe pipeline 5` başlarken tek dokunuş iste; çıktı `clock: frame timestamp X, system uptime Y (difference Z s), uptime including sleep W (difference V s)` biçimindedir. Fark sabit bir ofset olmalıdır; motor bu ofseti kendisi öğrenir.

## 9. Performans

### 9.1 Boşta bütçe
- **Nasıl:** Çalışan örneği kapat; `make perf`.
- **Beklenen:** CPU en fazla %1 (genelde 0.0), fiziksel ayak izi 15 MB altı.
