import Foundation

/// Tur 235 — Native istemcinin tek yapılandırma noktası.
///
/// `ios/` her CI derlemesinde Capacitor şablonundan yeniden üretildiği için bu dosya
/// `native/` altında tutulur ve `scripts/prepare-native-ios.mjs` tarafından projeye
/// kopyalanıp Xcode hedefine eklenir. Elle Xcode'da dosya EKLEME — bir sonraki
/// derlemede kaybolur.
enum DVBConfig {

    /// Sunucu. Uygulama YALNIZ kendi alan adımıza konuşur (ATS + veri güvenliği).
    static let apiBase = URL(string: "https://doktorumveben.com/api/v1")!

    /// Web içeriği (yasal metinler, hekim paneli) için taban adres.
    static let webBase = URL(string: "https://doktorumveben.com")!

    /// Sunucu tarafı bu imzayla native trafiği ayırt eder (Tur 201 kanal takibi).
    static let userAgentSuffix = "DoktorumvebenApp/2.0 (ios-native)"

    /// Ağ zaman aşımı — İlkByte upstream'i zaman zaman dalgalandığı için cömert
    /// tutuldu; istemci "takıldı" görüntüsü yerine dürüst hata göstersin.
    static let requestTimeout: TimeInterval = 20
}
