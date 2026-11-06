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
- **Ek:** Top Edge'i sırayla Switch Tabs, Zoom ve Undo & Redo yapıp ayar penceresi öndeyken kaydır: klavye odağı kontroller arasında dolaşmaz, hiçbir ayar geri alınmaz. Switch Desktops ise pencere öndeyken de masaüstünü değiştirir.

### 2.9 Medya kenarı: oynat/duraklat
- **Nasıl:** Bir kenarın eylemini Media yap; o kenarda çift dokun. Sol ya da sağ kenarda da dene.
- **Beklenen:** Çalan medya oynar/duraklar.

### 2.10 Sol ve sağ kenar seçicileri
- **Nasıl:** Edges sekmesinde Left Edge ve Right Edge seçicilerini aç; sonra Left Edge'i Switch Apps, Right Edge'i Keyboard Backlight yap. Sol kenarda yukarı kaydır, sonra aşağı, parmağı kaldır; bir kez de parmak kalkmadan ikinci parmağı koy. Sağ kenarda klavye ışığını en üste çıkar ve itmeye devam et.
- **Beklenen:** İki seçici de dört kenardaki aynı listeyi (Volume, Brightness, Keyboard Backlight, Switch Apps, Switch Tabs, Switch Desktops, Scrub Video, Media, Zoom, Undo & Redo, Off) gösterir; Swap Sides anahtarı yoktur. Diyagram dört kenarın eylemini gösterir. Sol kenarda yukarı = sonraki uygulama, aşağı = önceki; kalkınca seçilen uygulamaya geçilir, ikinci parmak değiştiriciyi iptal eder, ⌘ basılı kalmaz. Sağ kenarda overlay klavye ışığı seviyesini gösterir ve sınırda tek sınır haptiği gelir (2.5 gibi).

### 2.11 Switch Tabs
- **Nasıl:** Top Edge'i Switch Tabs yap; birkaç sekmeli bir tarayıcı penceresinde üst kenarda sağa, sonra sola kaydır. Sonra Right Edge'i Switch Tabs yapıp yukarı/aşağı kaydır.
- **Beklenen:** Yaklaşık her 12 mm'de bir sekme: yatay kenarda sağa ve dikey kenarda yukarı sonraki sekme, ters yönde önceki sekme. Parmak kalkınca ek bir şey olmaz.

### 2.12 Switch Desktops
- **Nasıl:** Mission Control'de en az iki masaüstü oluştur; Sistem Ayarları › Klavye › Klavye Kısayolları › Mission Control'de "Bir alan sola taşı" ve "Bir alan sağa taşı" açık olsun. Bottom Edge'i Switch Desktops yap; alt kenarda sağa, sonra sola kaydır. Sonra Left Edge'i Switch Desktops yapıp yukarı/aşağı kaydır.
- **Beklenen:** Yaklaşık her 20 mm'de bir masaüstü: sağa/yukarı sağdaki masaüstü, sola/aşağı soldaki masaüstü.

### 2.13 Zoom
- **Nasıl:** Top Edge'i Zoom yap; tarayıcıda bir sayfa açıkken üst kenarda sağa, sonra sola kaydır.
- **Beklenen:** Yaklaşık her 8 mm'de sayfa bir kademe yakınlaşır (sağa/yukarı) ya da uzaklaşır (sola/aşağı).

### 2.14 Undo & Redo
- **Nasıl:** Bir metin düzenleyicide birkaç ayrı değişiklik yap. Top Edge'i Undo & Redo yap; üst kenarda sola kaydır, sonra sağa kaydır.
- **Beklenen:** Yaklaşık her 10 mm'de sola/aşağı bir geri alma (⌘Z), sağa/yukarı bir yineleme (⇧⌘Z).

### 2.15 Eski ayarların taşınması (Swap Sides)
- **Nasıl:** trrek'i kapat (`osascript -e 'quit app "trrek"'`); `defaults write com.burakseyitkara.trrek settings -data "$(printf '{"schemaVersion":1,"swapSides":true}' | xxd -p | tr -d '\n')"` çalıştır; trrek'i aç ve Edges sekmesine bak; sağ ve sol kenarda kaydır.
- **Beklenen:** Left Edge Volume, Right Edge Brightness gösterir; sol kenar sesi, sağ kenar parlaklığı değiştirir. Bir ayar değiştirildikten sonra `defaults read com.burakseyitkara.trrek settings` çıktısının çözülmüş JSON'unda `swapSides` yoktur, `leftEdge` ve `rightEdge` vardır.

## 3. Köşeler

### 3.1 Köşe çift dokunma
- **Nasıl:** Ayarlarda bir köşeye Mute, diğerine Screenshot ata; her köşede çift dokun.
- **Beklenen:** Mute ses kapatır/açar; Screenshot ekran görüntüsü arayüzünü açar. Köşeye tek dokunma bir şey yapmaz.

### 3.1a Yeni köşe eylemleri
- **Nasıl:** Köşelere sırayla Play/Pause, Mission Control, App Windows, Show Desktop, Spotlight, Lock Screen ve Screenshot Area ata ve her birinde çift dokun. Mission Control ile ilgili üçünü Sistem Ayarları › Klavye › Klavye Kısayolları › Mission Control'deki kısayollar kapalıyken de dene.
- **Beklenen:** Play/Pause çalan medyayı oynatır/duraklatır. Mission Control bütün pencereleri, App Windows öndeki uygulamanın pencerelerini gösterir, Show Desktop masaüstünü açar (her biri kısayollar kapalıyken de çalışır; tekrar çift dokunmak ya da Esc görünümü kapatır). Spotlight arama alanını açar. Lock Screen ekranı kilitler. Screenshot Area alan seçme imlecini açar. Hata olursa trrek çökmez; `/usr/bin/log show --last 5m --predicate 'subsystem == "com.burakseyitkara.trrek"'` çıktısında "mission control" satırı görünür.

### 3.1b Kenarı Off olan köşe
- **Nasıl:** Edges sekmesinde Left Edge'i Off yap; Corners & Taps'ta Top Left'e Mission Control ata ve sol üst köşede çift dokun. Aynı köşeden aşağı (sol kenar boyunca) ve sağa (üst kenar boyunca) kaydır. Sonra Top Edge'i de Off yapıp çift dokunmayı tekrarla.
- **Beklenen:** Çift dokunma her iki durumda da Mission Control'ü açar. Aşağı kaydırma hiçbir şey yapmaz (imleç donmaz, haptik yok); sağa kaydırma üst kenarın eylemini (Switch Apps) çalıştırır. Sol kenarın ortasında kaydırma hiçbir şey yapmaz.

### 3.2 Köşe rozeti tıklaması eylemi döndürür
- **Nasıl:** Corners & Taps sekmesinde bir köşenin rozetine tıkla.
- **Beklenen:** Eylem her tıklamada seçicideki sırayla ilerler (Off → Mute → Screenshot → Play/Pause → Mission Control → App Windows → Show Desktop → Spotlight → Lock Screen → Screenshot Area → Off); rozetin simgesi eylemi gösterir.

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

### 4.2a Slide Sensitivity
- **Nasıl:** General sekmesinde Slide Sensitivity'yi sırayla Very Low, Standard ve Very High yap; her birinde sağ kenarda (Volume) aynı mesafeyi (ör. alttan ortaya) kaydır ve adım sayısını say. Very High'da sesi en üste çıkarıp itmeye devam et; Switch Apps kenarında da dene.
- **Beklenen:** Very Low'da en az adım, Very High'da en çok adım (Standard'a göre yaklaşık 0,6 ve 1,6 kat mesafe başına adım farkı). Slide'ın başlaması için gereken mesafe değişmez. Very High'da da sınırda tek sınır haptiği gelir, sonra sessizlik (2.5). Seçim pencere kapanıp açılınca korunur.

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
- **Nasıl:** Edges sekmesinde Left, Right, Top ve Bottom Edge seçicilerini aç.
- **Beklenen:** Dört seçici de aynı listeyi gösterir. Seçenek adının yanında not belirtilir: "Scrub Video — Uses ← and → in the front app", "Switch Tabs — Uses ⌃⇥ and ⌃⇧⇥ in the front app", "Switch Desktops — Uses ⌃← and ⌃→", "Zoom — Uses ⌘= and ⌘− in the front app", "Undo & Redo — Uses ⌘Z and ⇧⌘Z in the front app"; hepsi seçilebilir. Klavye arka ışığı olmayan Mac'te "Keyboard Backlight — Not available on this Mac" her seçicide devre dışıdır ve seçili değer Media olarak gösterilir.

### 7.2a Accessibility gerektiren kenar notu
- **Nasıl:** Accessibility iznini kaldır; Edges sekmesinde Top Edge'i Switch Apps ya da Scrub Video, Left Edge'i Switch Tabs, Zoom ya da Undo & Redo yap.
- **Beklenen:** Seçicinin başlığı altında "Needs Accessibility access" notu görünür; Keyboard Backlight seçiliyken görünmez. İzin verilince not kaybolur.

### 7.2b External Monitor Brightness kullanılamıyor
- **Nasıl:** DDC sembolleri olmayan bir sistemde (ya da günlükte "external brightness available: false" görülen bir derlemede) Edges sekmesini aç.
- **Beklenen:** External Monitor Brightness anahtarı kapalı ve devre dışıdır, altında "Not available on this Mac" yazar.

### 7.3 Reset to Defaults
- **Nasıl:** Birkaç ayarı değiştir; General sekmesinde Reset to Defaults…'a bas.
- **Beklenen:** Onay uyarısı çıkar; iptal edince değişiklik olmaz, onaylayınca tüm ayarlar varsayılana döner. Launch at Login ve Language değişmez.

### 7.4 Ayarları dışa aktarma
- **Nasıl:** General sekmesinde Export Settings…'e bas; trrek arka plandayken de dene.
- **Beklenen:** Kaydetme paneli ayarlar penceresine sheet olarak bağlanır, önerilen ad "trrek Settings.trrek"tir (Türkçe arayüzde "trrek Ayarları.trrek"). Kaydedilen dosya girintili JSON'dur; `format`, `formatVersion`, `appVersion` ve `settings` anahtarları vardır, `launchAtLogin` ve `welcomeShown` yoktur.

### 7.5 Ayarları içe aktarma
- **Nasıl:** Dışa aktardıktan sonra birkaç ayarı değiştir; Import Settings…'e bas ve dosyayı seç. Bir kez Cancel, bir kez Replace de.
- **Beklenen:** Açma paneli sheet olarak gelir ve yalnızca `.trrek` dosyaları seçilebilir. "Replace your current settings with the ones in “…”?" onayı çıkar; Cancel hiçbir şeyi değiştirmez, Replace dışa aktarılan ayarları geri getirir ve kenarlar hemen yeni ayarlarla çalışır. Launch at Login ve Language değişmez.

### 7.6 Geçersiz dosyayı içe aktarma
- **Nasıl:** Boş bir dosyayı, rastgele metni, 1 MB'tan büyük bir dosyayı, `"format"` değeri farklı bir JSON'u ve `"formatVersion": 2` yazılmış bir dosyayı `.trrek` uzantısıyla kaydedip sırayla içe aktar.
- **Beklenen:** Uygulama çökmez; "“…” could not be imported." uyarısı nedenini söyler (bozuk/başka dosya ya da daha yeni sürüm) ve ayarlar değişmez.

### 7.7 Finder'dan çift tıklama
- **Nasıl:** trrek çalışırken ve kapalıyken Finder'da bir `.trrek` dosyasına çift tıkla; ayarlar penceresi Edges sekmesindeyken de dene.
- **Beklenen:** Dosyanın türü "trrek Settings" görünür; trrek açılır ya da öne gelir, ayarlar penceresi General sekmesinde açılır ve aynı onay çıkar. Kapalıyken açılışta karşılama penceresi gerekiyorsa o da çıkar, onay ayarlar penceresindedir. Onay açıkken ikinci bir `.trrek` dosyasına çift tıklamak onayı değiştirmez (yok sayılır); Replace ilk dosyayı uygular.

### 7.8 Türkçe arayüz
- **Nasıl:** General sekmesinde Language'ı Türkçe yap. "Relaunch trrek to use the new language." satırındaki Relaunch'a bas.
- **Beklenen:** trrek kapanıp birkaç saniye içinde yeniden açılır (menü çubuğunda tek simge kalır, ikinci bir örnek açılmaz). Şunların hepsi Türkçedir, İngilizce metin kalmaz: menü (durum satırı, "Hassas Denetim", "İmleci Dondur", bir uygulama öndeyken "… İçin Duraklat"/"… İçin Sürdür", "Ayarlar…", "Karşılamayı Göster", izin yokken "Erişilebilirlik İzni Ver…", "trrek Hakkında", "trrek’ten Çık"); ayarlar penceresinin başlığı ("trrek Ayarları") ve dört sekmesi (Genel, Kenarlar, Köşe ve Dokunma, Gelişmiş; dördü de sekme çubuğunda görünür, `>>` taşma menüsü çıkmaz) bütün seçici, seçenek, not ve alt yazılarıyla; diyagramdaki kenar adları; Reset onayı; Export/Import panellerinin başlık ve düğmeleri; içe aktarma onayı ve geçersiz dosya uyarısı (7.6); Paused Apps listesi ve "+" paneli; karşılama penceresi (başlık, kenar kartları, izin satırı, düğmeler); klavye ışığı overlay'inde yüzde "%50" biçiminde, harici ekranda hata "DDC yok"; About penceresi. Tuş simgeleri (⌘ ⌃ ⇧ ⇥ ← →) aynı kalır; Basılı Tutarak Kaydırma Tuşu seçicisinde Kontrol ve Komut, Shift ve Option görünür; scrub overlay'i "+15 sn" gösterir. Köşe ve Dokunma sekmesindeki ipucu, İzleme Dörtgeni ayarlarındaki "Araştırma ve veri algılayıcıları" ve "Tek Parmakla Kuvvetli Tıklayın" adlarıyla aynıdır. Finder'da `.trrek` dosyasının türü "trrek Ayarları" görünür. Hiçbir metin kesilmez ya da taşmaz (özellikle karşılama kartları ve segmentli seçiciler).

### 7.9 Dili sisteme döndürme
- **Nasıl:** Türkçe arayüzde Dil'i Sistem yap ve Yeniden Başlat'a bas. Sonra Language'ı English yap, bu kez yeniden başlatmadan Sistem'e geri al.
- **Beklenen:** Yeniden açılınca arayüz sistem dilini izler (sistem dili Türkçe değilse İngilizce). `defaults read com.burakseyitkara.trrek AppleLanguages` anahtarın olmadığını söyler. Seçim açılıştaki dile geri dönünce yeniden başlatma satırı kaybolur. Sistem dili Türkçeyken Sistem seçiliyken Türkçe'yi seçmek yeniden başlatma satırı çıkarmaz (görünen dil değişmez).

### 7.10 İçe aktarma dili değiştirmez
- **Nasıl:** Language English iken ayarları dışa aktar, Language'ı Türkçe yapıp yeniden başlat, sonra dosyayı içe aktar.
- **Beklenen:** Onay "Oturum Açıldığında Başlat ve dil ayarları değişmez." der; içe aktarmadan sonra seçici Türkçe kalır, yeniden başlatma satırı çıkmaz. Dışa aktarılan dosyada `language` anahtarı yoktur.

### 7.11 Dil ve Bölge › Uygulamalar'dan dil seçimi
- **Nasıl:** trrek'te Language Sistem iken Sistem Ayarları › Genel › Dil ve Bölge › Uygulamalar'da "+" ile trrek'i ekle ve sistem dilinden farklı bir dil (Türkçe ya da English) seç; sistemin önerdiği yeniden başlatmayı kabul et. Sonra trrek'i bir kez daha kapatıp aç. En sonda Uygulamalar listesinden trrek'i kaldır (ya da trrek'te Language'ı Sistem yap).
- **Beklenen:** trrek seçilen dilde açılır; General sekmesinde Language o dili gösterir, yeniden başlatma satırı çıkmaz. `defaults read com.burakseyitkara.trrek AppleLanguages` seçilen dili (ör. `tr` ya da `tr-TR`) gösterir; ikinci açılışta da dil değişmez ve değer üzerine yazılmaz. trrek'te Language'ı Sistem yapıp yeniden başlatınca anahtar silinir ve Uygulamalar listesindeki seçim de "Sistem Dili"ne döner.

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

## 10. Güncellemeler

Ön koşul: `make install`. Denetim durumu trrek'in defaults alanında tutulur (`lastUpdateCheck`, `notifiedVersion`, `availableUpdate`); `--assume-version` ile başlatılan trrek ise kendi ayrı alanını (`com.burakseyitkara.trrek.assumed-version`) kullanır, böylece elle deneme gerçek takvimi ve bildirimi etkilemez. O denemeyi baştan almak için `defaults delete com.burakseyitkara.trrek.assumed-version`. Günlük: `/usr/bin/log stream --predicate 'subsystem == "com.burakseyitkara.trrek" AND category == "app"'`.

### 10.1 Otomatik denetim ve bildirim
- **Nasıl:** trrek'ten çık, `defaults delete com.burakseyitkara.trrek.assumed-version` çalıştır, `~/Applications/trrek.app/Contents/MacOS/trrek --assume-version 0.2.0` ile başlat ve 15 sn bekle. İlk seferde çıkan bildirim izni isteğine izin ver.
- **Beklenen:** Günlükte "update check assumes version 0.2.0" ve yaklaşık 10 sn sonra "update check: X.Y.Z is available" görünür. "trrek X.Y.Z kullanılabilir / İndirmek için tıklayın." (İngilizce: "trrek X.Y.Z is available / Click to download.") bildirimi bir kez gelir. Menünün en üstünde kalın, indirme simgeli "Update Available: trrek X.Y.Z…" öğesi vardır. trrek'i aynı argümanla yeniden başlatınca (24 saat dolmadan) yeni istek ve yeni bildirim olmaz, menü öğesi kalır. Bildirim izni verilmezse bildirim gelmez, menü öğesi yine görünür. Not: kabuktan başlatılan trrek'in Accessibility izni kabuğun iznine bağlıdır; jestler çalışmayabilir ve karşılama penceresi açılabilir.

### 10.2 Bildirime tıklayarak indirme
- **Nasıl:** 10.1'deki bildirime tıkla (trrek kapalıyken Bildirim Merkezi'ndeki bildirime tıklamayı da dene).
- **Beklenen:** Menüde devre dışı "Downloading trrek X.Y.Z…" görünür; indirme bitince `~/Downloads/trrek-vX.Y.Z.dmg` oluşur (aynı adlı eski dosya değiştirilir) ve `xattr -p com.apple.quarantine` dosyada bir değer gösterir. Ardından kurulum 10.9'daki gibi sürer; trrek kendini değiştiremiyorsa (ör. `~/Applications` dışında, yazılamayan bir klasörde) 10.11'deki gibi disk görüntüsü açılır ve içindeki uygulamayı ilk açışta macOS internetten indirilmiş uygulama onayını sorar. trrek kapalıyken tıklama trrek'i başlatır ve indirmeyi başlatır; bu yalnızca çalışan sürümden gerçekten yeni bir sürümde denenebilir. `--assume-version` ile bulunan sürüm normal açılışta bilinmez; o durumda tıklama elle denetim yapar ve "trrek is up to date" uyarısını gösterir (tıklama hiçbir zaman sessiz kalmaz).

### 10.3 Menüden indirme
- **Nasıl:** 10.1'den sonra menüde "Update Available: trrek X.Y.Z…" öğesini seç.
- **Beklenen:** 10.2'deki gibi indirilir ve kurulum uyarısı gelir. İndirme sırasında öğe "Downloading trrek X.Y.Z…", doğrulama sırasında "Installing trrek X.Y.Z…" olur ve seçilemez.

### 10.4 Elle denetim: güncel
- **Nasıl:** `--assume-version` olmadan normal başlat; menüden "Check for Updates…" seç. Ardından ayarlar penceresinde General › Check Now'a bas.
- **Beklenen:** Menüden: trrek öne gelir, "trrek is up to date / trrek X.Y.Z is the latest version." uyarısı OK ile çıkar. Check Now: aynı uyarı ayarlar penceresine sheet olarak gelir; denetim sürerken düğme devre dışıdır ve altında "Checking…" yazar, sonra "Last checked: <tarih saat>" olur. Türkçe arayüzde metinler "trrek güncel", "Güncellemeleri Denetle…", "Şimdi Denetle", "Son denetim: …" olur ve kesilmez.

### 10.5 Elle denetim: yeni sürüm
- **Nasıl:** `--assume-version 0.2.0` ile başlat, otomatik denetimi beklemeden menüden "Check for Updates…" seç.
- **Beklenen:** "trrek X.Y.Z is available" uyarısı "You have trrek 0.2.0." satırı ve en fazla ~600 karakterlik sürüm notlarıyla (madde işaretleri "•", ters tırnaksız) çıkar; Download indirmeyi başlatır (10.2), Later hiçbir şey yapmaz. Bu denetimden sonra aynı sürüm için bildirim gelmez. Sürüm notları CHANGELOG'dan geldiği için Türkçe arayüzde de İngilizcedir. Uyarı açıkken ya da indirme sürerken menüdeki "Check for Updates…" ve General › Check Now devre dışıdır.

### 10.6 Otomatik denetim kapalı
- **Nasıl:** General'da "Check for Updates Automatically"ı kapat; `lastUpdateCheck` anahtarını sil, trrek'i yeniden başlat, menüyü birkaç kez aç, Mac'i uyut ve uyandır.
- **Beklenen:** Günlükte "update check" satırı çıkmaz (istek gönderilmez). "Check for Updates…" ve Check Now yine çalışır. Ayar `.trrek` dosyasına `checkForUpdatesAutomatically` olarak yazılır; Reset to Defaults onu yeniden açar.

### 10.7 Çevrimdışı
- **Nasıl:** Wi-Fi'ı kapat; menüden "Check for Updates…" seç. Sonra 10.1'deki gibi bir indirmeyi başlatıp indirme sırasında ağı kes.
- **Beklenen:** "Couldn’t check for updates" uyarısı sistemin hata açıklamasıyla (ör. "The Internet connection appears to be offline.") çıkar. İndirme kesilince "Couldn’t download trrek X.Y.Z" uyarısı çıkar; "Open Download Page" sürüm sayfasını tarayıcıda açar, Cancel kapatır; Downloads'ta yarım dosya kalmaz. Çevrimdışıyken otomatik denetim başarısız olursa bir saat boyunca menü açılışları yeni istek göndermez.

### 10.8 İndirilenler klasörü izni (bir kez)
- **Nasıl:** Finder'dan ya da `open ~/Applications/trrek.app` ile başlatılmış trrek'te (kabuktan başlatılan süreç izni kabuğa yazar) bir güncellemeyi ilk kez indir (10.2 ya da 10.3). Sistem Ayarları › Gizlilik ve Güvenlik › Dosyalar ve Klasörler'de trrek'in İndirilenler iznini kapatıp tekrar dene; sonra `tccutil reset SystemPolicyDownloadsFolder com.burakseyitkara.trrek` ile istemi sıfırla ve bu kez reddet.
- **Beklenen:** İlk indirmede bir kez "“trrek” İndirilenler klasörünüzdeki dosyalara erişmek istiyor" istemi, açıklama satırıyla çıkar: "trrek, güncelleme disk görüntülerini İndirilenler klasörünüze kaydeder." (İngilizce: "trrek saves update disk images to your Downloads folder."). İzin verilince indirilip açılır, sonraki indirmelerde istem çıkmaz. İzin kapalıyken ya da reddedilince "Couldn’t download trrek X.Y.Z" uyarısı izin hatasıyla çıkar; "Open Download Page" sürüm sayfasını açar; İndirilenler'de dosya oluşmaz.

Aşağıdaki kurulum denemeleri hep bir **kopya** üzerinde yapılır; `~/Applications/trrek.app` değişmez. Kopya: trrek'ten çık (`osascript -e 'quit app "trrek"'`), `rm -rf /tmp/trrek-install-test && mkdir -p /tmp/trrek-install-test && ditto ~/Applications/trrek.app /tmp/trrek-install-test/trrek.app`, `defaults delete com.burakseyitkara.trrek.assumed-version`, sonra `open -a /tmp/trrek-install-test/trrek.app --args --assume-version 0.2.0`. Yayımlanmış sürüm (ör. 0.3.0) kendi başına yerinde kurulumu bilmeyebilir; denenen, kopyadaki sürümün onu kurmasıdır. Bitince kopyadan çık, `rm -rf /tmp/trrek-install-test` ve `open ~/Applications/trrek.app`.

### 10.9 Yerinde kurulum ve yeniden başlatma
- **Nasıl:** Kopyayı yukarıdaki gibi aç; menüden "Check for Updates…" seç, Download'a bas; "trrek X.Y.Z is ready to install" uyarısında Install and Relaunch'a bas.
- **Beklenen:** İndirmeden sonra menüde devre dışı "Verifying trrek X.Y.Z…", uyarı açıkken "trrek X.Y.Z Is Ready to Install", kurulurken "Installing trrek X.Y.Z…" görünür (Türkçe: "trrek X.Y.Z Doğrulanıyor…", "trrek X.Y.Z Yüklenmeye Hazır", "trrek X.Y.Z Yükleniyor…"); Finder penceresi açılmaz, Finder kenar çubuğunda disk görüntüsü görünmez. Uyarı "trrek will quit and open again." satırıyla, Install and Relaunch / Later düğmeleriyle çıkar (Türkçe: "trrek X.Y.Z yüklenmeye hazır", "trrek kapanıp yeniden açılacak.", "Yükle ve Yeniden Başlat" / "Daha Sonra"). Install and Relaunch'tan sonra trrek kapanır ve birkaç saniye içinde aynı klasörden yeniden açılır: `pgrep -lf trrek` kopyanın yolunu (Launch Services çoğunlukla çözülmüş `/private/tmp/trrek-install-test/trrek.app/Contents/MacOS/trrek` biçimini verir) `--assume-version` olmadan gösterir; `defaults read /tmp/trrek-install-test/trrek.app/Contents/Info.plist CFBundleShortVersionString` yeni sürümü verir, About da onu gösterir. Açılışta Gatekeeper onayı sorulmaz; `xattr -r /tmp/trrek-install-test/trrek.app | grep quarantine` boş, `ls -a /tmp/trrek-install-test` yalnızca `trrek.app`'i gösterir (yedek `.trrek-previous` silinmiştir); `hdiutil info` çıktısında `trrek-update-` bağlama noktası yoktur. Accessibility izni yeniden istenmeden jestler çalışır (aynı Developer ID imzası). `~/Downloads/trrek-vX.Y.Z.dmg` yerinde kalır. Günlükte "update X.Y.Z verified" (hazırlıkta), "update X.Y.Z installed", "relaunching for the update" satırları görünür.

### 10.10 Later, sonra menüden kurulum
- **Nasıl:** Yeni bir kopyayla 10.9'u tekrarla, uyarıda Later'a bas. Menüyü aç, "Install trrek X.Y.Z…" öğesini seç; uyarıda Install and Relaunch'a bas. Bir kez de Later'dan sonra `~/Downloads/trrek-vX.Y.Z.dmg`'yi silip menü öğesini seç.
- **Beklenen:** Later'dan sonra hiçbir şey açılmaz, hazırlanan kopya silinir, DMG İndirilenler'de kalır ve menünün en üstünde kalın "Install trrek X.Y.Z…" (Türkçe: "trrek X.Y.Z Sürümünü Yükle…") öğesi vardır. Seçince disk görüntüsü yeniden bağlanıp doğrulanır ("Installing trrek X.Y.Z…"), aynı uyarı çıkar ve kurulum 10.9'daki gibi biter. DMG silinmişse öğe onu yeniden indirir, sonra aynı uyarı gelir. Later durumu yalnızca bellektedir: trrek yeniden başlarsa menü yine "Update Available: trrek X.Y.Z…" gösterir.

### 10.11 Yerinde kurulamayınca disk görüntüsü
- **Nasıl:** Kopyayı oluştur, `chmod a-w /tmp/trrek-install-test` çalıştır, kopyayı aç ve Download'a bas. Sonra `chmod u+w /tmp/trrek-install-test`. Ayrıca disk görüntüsünü Finder'da bağlayıp trrek'i oradan `--assume-version 0.2.0` ile aç (`open -a /Volumes/trrek/trrek.app --args --assume-version 0.2.0`) ve Download'a bas.
- **Beklenen:** "trrek X.Y.Z couldn’t be installed automatically" uyarısı nedeniyle çıkar: yazılamayan klasörde "trrek can’t write to the folder it’s installed in.", disk görüntüsünden çalışırken "trrek runs from a disk image or a read-only volume." ve "Drag trrek to the Applications folder in the disk image’s window." satırı (Türkçe: "trrek X.Y.Z otomatik olarak yüklenemedi", "trrek, yüklü olduğu klasöre yazamıyor."). OK'den sonra disk görüntüsü Finder'da açılır; kopya değişmez.

### 10.12 Değiştirilmiş güncelleme reddedilir
- **Nasıl:** 10.10'daki gibi Later'a bas. Değiştirilmiş bir DMG hazırla: `mkdir -p /tmp/trrek-tamper/src && ditto /Volumes/trrek/trrek.app /tmp/trrek-tamper/src/trrek.app` (DMG'yi Finder'da bağlayarak), `codesign --force --sign - /tmp/trrek-tamper/src/trrek.app`, `diskutil image create from --format UDZO /tmp/trrek-tamper/src /tmp/trrek-tamper/tampered.dmg`, DMG'yi çıkar; `cp /tmp/trrek-tamper/tampered.dmg ~/Downloads/trrek-vX.Y.Z.dmg`. Menüden "Install trrek X.Y.Z…" seç.
- **Beklenen:** Değiştirilmiş DMG imzasız olduğu için bağlanmadan reddedilir. "trrek X.Y.Z couldn’t be verified" uyarısı "The update isn’t signed by trrek’s developer." ve "Nothing was installed. The disk image is kept in Downloads." satırlarıyla çıkar (Türkçe: "trrek X.Y.Z doğrulanamadı", "Güncelleme, trrek’in geliştiricisi tarafından imzalanmamış."). Open Download Page sürüm sayfasını açar, Cancel kapatır; disk görüntüsü açılmaz, kopya değişmez, `hdiutil info`'da bağlı kalan imaj yoktur. Bitince `rm -rf /tmp/trrek-tamper` ve DMG'yi sil.

### 10.13 Gerçek doğrulayıcı ve bağlayıcı (otomatik)
- **Nasıl:** Yayımlanmış DMG'yi geçici bir klasöre indir (`curl -L -o /tmp/trrek-dmg/trrek-v0.3.0.dmg https://github.com/burakseyitkara1/trrek-releases/releases/download/v0.3.0/trrek-v0.3.0.dmg`), `make app` ile Developer ID imzalı ama notarize edilmemiş `dist/trrek.app` üret; `TRREK_UPDATE_DMG=/tmp/trrek-dmg/trrek-v0.3.0.dmg TRREK_UNNOTARIZED_APP=$PWD/dist/trrek.app make test`.
- **Beklenen:** `UpdateInstallReleaseTests` geçer (~15 sn): imaj gizli bağlanıp kopyalanır ve çıkarılır, sürüm doğrulanır; hazırlandıktan sonra yeniden imzalanan kopya kurulumdan hemen önce reddedilir ve kurulu kopya değişmez; imzasız bir DMG bağlanmadan reddedilir; ad-hoc yeniden imzalanmış kopya ve `Info.plist` sürümü değiştirilmiş kopya imza denetiminde, `dist/trrek.app` yalnızca notarizasyon denetiminde reddedilir ("not notarized app: Optional(…notNotarized)"); geçici bir klasördeki sahte kurulu uygulama yeni sürümle değiştirilir, karantina ve yedek kalmaz. Ortam değişkeni yoksa test atlanır. Sonra `hdiutil info`'da `trrek-update-` yoktur; `rm -rf /tmp/trrek-dmg`.

### 10.14 Yarıda kalan kurulumun temizliği
- **Nasıl:** Kopyayı aç, ayarlar penceresinde General › Check Now ile güncellemeyi bul ve Download'a bas; "ready to install" uyarısı ayarlar penceresinde sheet olarak açıkken menüden Quit trrek'i seç. Sonra kopyayı yeniden aç.
- **Beklenen:** Çıkışta hazırlanan kopya silinir; `hdiutil info`'da `trrek-update-` bağlama noktası, `ls $TMPDIR | grep trrek-update` çıktısında klasör yoktur; kopyanın yanında `.trrek-previous` yoktur. Elle bırakılmış bir `$TMPDIR/trrek-update-x` boş klasörü ve `/tmp/trrek-install-test/.trrek-previous` klasörü bir sonraki açılışta silinir.
