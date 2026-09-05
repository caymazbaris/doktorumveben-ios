import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// DVB-000111 — ÇEVRİMDIŞI RANDEVU ÖNBELLEĞİ (+ widget'ın veri kaynağı).
///
/// NEDEN: internet yokken uygulama bugüne kadar markalı bir hata ekranına düşüyordu —
/// yani web sitesinden farkı yoktu. Apple'ın 31.07.2026 reddi tam olarak "tarayıcı
/// deneyiminden yeterince farklı değil" diyor. Bir web sayfasının YAPISAL OLARAK
/// yapamadığı şey, kullanıcının kendi verisini cihazda tutup ağsız göstermektir.
///
/// ⚠ APP GROUP ŞART: widget ayrı bir süreçte çalışır ve uygulamanın sandbox'ını
/// göremez. Ortak kap olmadan widget her açılışta ağa çıkmak zorunda kalır ve
/// uçak modunda boş görünür. Grup kimliği hem uygulamaya hem uzantıya tanımlanmalı
/// (prepare-native-ios.mjs → entitlements).
///
/// ⚠ NE SAKLANIR: yalnız sunucunun ZATEN ekranda gösterdiği alanlar (tarih, saat,
/// durum, karşı tarafın adı). Şikâyet/tanı/not saklanmaz. Widget verisi sunucuda
/// maskelenmiş halde gelir; burada bir daha maskelenmez, olduğu gibi yazılır.
enum DVBOfflineStore {

    /// Uygulama ve widget uzantısının paylaştığı kap.
    static let appGroup = "group.com.doktorumveben.app"

    private enum Anahtar {
        static let ajanda = "dvb.cache.agenda"
        static let ajandaZaman = "dvb.cache.agenda.at"
        static let randevular = "dvb.cache.appointments"
        static let randevularZaman = "dvb.cache.appointments.at"
    }

    /// App Group yoksa (entitlement basılmamışsa) standard'a düşer: uygulama
    /// çalışmaya devam eder, yalnız widget veriyi göremez. Sessiz çökme yerine
    /// bilinçli düşüş.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var appGroupCalisiyor: Bool {
        UserDefaults(suiteName: appGroup) != nil
    }

    // MARK: - Yazma

    static func yazAjanda(_ ham: Data) {
        defaults.set(ham, forKey: Anahtar.ajanda)
        defaults.set(Date(), forKey: Anahtar.ajandaZaman)
    }

    static func yazRandevular(_ ham: Data) {
        defaults.set(ham, forKey: Anahtar.randevular)
        defaults.set(Date(), forKey: Anahtar.randevularZaman)
    }

    // MARK: - Okuma

    static func okuAjanda() -> (veri: DVBAgenda, zaman: Date)? {
        guard let ham = defaults.data(forKey: Anahtar.ajanda),
              let cozulen = try? JSONDecoder().decode(DVBAgenda.self, from: ham)
        else { return nil }

        return (cozulen, defaults.object(forKey: Anahtar.ajandaZaman) as? Date ?? .distantPast)
    }

    static func okuRandevular() -> (veri: [DVBAppointment], zaman: Date)? {
        guard let ham = defaults.data(forKey: Anahtar.randevular) else { return nil }

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let liste = try? d.decode(DVBList<DVBAppointment>.self, from: ham) else { return nil }

        return (liste.data, defaults.object(forKey: Anahtar.randevularZaman) as? Date ?? .distantPast)
    }

    /// Çıkışta önbellek TEMİZLENİR — başka bir kullanıcı aynı cihazda giriş yaparsa
    /// öncekinin randevuları widget'ta durmasın. Bu bir gizlilik gereği, konfor değil.
    static func temizle() {
        let d = defaults
        [Anahtar.ajanda, Anahtar.ajandaZaman, Anahtar.randevular, Anahtar.randevularZaman]
            .forEach { d.removeObject(forKey: $0) }
    }

    /// Widget'a "veri değişti, zaman çizelgeni yenile" de.
    ///
    /// ⚠ WidgetKit `canImport` ile korunuyor: widget hedefi projeye HENÜZ EKLENMEDİ
    /// (ayrı Xcode target'ı gerektiriyor, bkz. DVB-000111). Çerçeve yoksa bu çağrı
    /// derlemeyi kırmamalı — uygulama widget olmadan da tam çalışır.
    static func widgetiYenile() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "DVBAgendaWidget")
        }
        #endif
    }

    /// Önbellek ne kadar bayat? Arayüzde "son güncelleme" bandı için.
    static func bayatlikMetni(_ zaman: Date) -> String {
        let fark = Int(Date().timeIntervalSince(zaman))
        switch fark {
        case ..<120: return "az önce güncellendi"
        case ..<3600: return "\(fark / 60) dakika önce güncellendi"
        case ..<86_400: return "\(fark / 3600) saat önce güncellendi"
        default: return "\(fark / 86_400) gün önce güncellendi"
        }
    }
}
