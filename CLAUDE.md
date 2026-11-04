# trrek — proje kuralları

trrek, macOS'ta trackpad kenarlarını tek parmaklı kontrollere (ses, parlaklık, klavye ışığı, uygulama değiştirme, medya) çeviren, menü çubuğunda yaşayan bağımsız bir uygulamadır. Tasarım: `docs/superpowers/specs/`. Plan: `docs/superpowers/plans/`.

## Dil ve adlandırma
- Belgeler ve PR gövdeleri Türkçe; kod, yorumlar, commit mesajları ve kullanıcı arayüzü İngilizce.
- Arayüz İngilizce yazılır, Türkçe çevirisi `tr.lproj` ile gelir: `Sources/Trrek/Resources/{en,tr}.lproj/Localizable.strings`, anahtar İngilizce kaynak metindir. Yeni bir arayüz metni iki dosyaya da eklenir; `LocalizationTests` eksik anahtarı, fazla anahtarı ve farklı biçim belirtecini yakalar.
- Uygulama adı her yerde küçük harf: `trrek`. Bundle ID `com.burakseyitkara.trrek`.
- Projede başka bir uygulamanın, kütüphanenin ya da projenin adı geçmez: ne kodda, ne yorumda, ne belgede, ne commit ya da PR metninde. "Referans", "esinlenildi", "uyarlandı" gibi atıflar yazılmaz. Tüm kod bu depoda sıfırdan yazılır; dış koddan kopyalama yapılmaz.

## Teknik sınırlar
- Swift Package Manager ile derlenir; Xcode projesi yoktur. `swift-tools-version: 6.0`, Swift 6 dil modu, hedef macOS 26.0+, yalnızca arm64.
- CI runner'ı Xcode 26.6 kullanır: Swift 6.3+ dil özellikleri ve macOS 27 API'leri kullanılmaz.
- Private framework sembolleri yalnızca `Sources/TrrekPlatform/PrivateSymbols.swift` içinde, `dlopen`/`dlsym` ile çözülür; eksik sembol özelliği kapatır, asla çökertmez.
- Performans bütçesi: boşta %0 CPU ve 15 MB altı bellek; kare başına heap ayırma yok; periyodik zamanlayıcı yok.
- UI: SwiftUI, macOS 26 Liquid Glass; pencereler ihtiyaç anında oluşturulur ve kapanınca serbest bırakılır.

## Git ve CI
- `main`'e doğrudan commit yok. Dal önekleri: `feat/`, `fix/`, `docs/`, `ci/`, `chore/`, `test/`. İngilizce conventional commits.
- Her değişiklik PR ile gelir; CI yeşil ve inceleme tamam olmadan merge edilmez. Squash merge, dal silinir.
- Push'tan önce `make check` (build, test, format, lint) yerelde geçmelidir.
- CHANGELOG.md "Unreleased" altına her PR bir satır ekler.

## Test
- `TrrekEngine` için Swift Testing; her jest kuralı için sentetik kare testi. Donanım gerektiren davranışlar `docs/testing.md` elle kontrol listesinde.
- `TrrekProbe` geliştirme aracıdır, uygulama paketine girmez.
