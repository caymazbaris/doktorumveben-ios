import Foundation
import WebKit

// ═══════════════════════════════════════════════════════════════════════════════
// DVB-000273 — UYGULAMA OTURUMUNU UYGULAMA İÇİ WEB SAYFASINA TAŞIYAN KÖPRÜ (İksHesap IKS-000085 deseni).
//
// Kullanıcı (1 Eki 2026, iPhone'da): "google takvim senkron hatası verdiğinde, bildirime tıklayınca uygulama içinde site
// açılıyor ve giriş yapmam isteniyor bu durum için session taşıyan bir çözüm yapmamışmıydık?"
//
// Uygulama Sanctum jetonuyla çalışır; web sayfaları çerezle. Oturum gerektiren kendi sayfamız açılmadan önce sunucudan
// tek kullanımlık, 60 saniyelik bir giriş adresi alınır (`POST auth/web-session`); web görünümü o adresi yükler, sunucu
// oturumu açıp hedefe yönlendirir. Adres SAKLANMAZ — her açılışta yenisi.
//
// ⛔ ÇIKIŞTA VE GİRİŞTE ÇEREZLER SİLİNİR: web görünümünün deposu kalıcı; silinmeseydi aynı cihazda sonraki kişi
//    öncekinin panelini açardı.
// ⛔ Ödeme sayfaları bu köprüye HİÇ gelmez — DVBOdemeAdresi onları önce Safari'ye devreder (DVB-000271).
// ⚠ Bu dosya widget hedefinde DEĞİL (scripts/add-widget-target.rb SHARED'a eklenmez).
// ═══════════════════════════════════════════════════════════════════════════════

enum DVBWebOturum {
    /// Oturum gerektiren kendi sayfalarımız: hekim paneli, hasta "Hesabım", uygulama açılış kapısı.
    static func kopruGerekirMi(_ url: URL) -> Bool {
        let host = url.host ?? ""
        guard host == "doktorumveben.com" || host.hasSuffix(".doktorumveben.com") else { return false }
        let yol = url.path
        return yol.hasPrefix("/panel") || yol.hasPrefix("/hesabim") || yol == "/uygulama"
    }

    /// Sunucunun giriş sayfası (`route('login')` → /giris): oturum düştüyse web görünümü buraya düşer.
    static func girisSayfasiMi(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.path == "/giris"
    }

    private struct Cevap: Decodable {
        let data: Veri
        struct Veri: Decodable { let url: String }
    }

    /// Hedef için tek kullanımlık giriş adresi. Alınamazsa nil (oturum yok, ağ yok, iki adımlı doğrulama açık — 409):
    /// sayfa eskisi gibi açılır, gerekiyorsa web girişini ister.
    static func kopruAdresi(_ hedef: URL) async -> URL? {
        guard let token = DVBKeychain.read(), !token.isEmpty else { return nil }
        var yol = hedef.path.isEmpty ? "/" : hedef.path
        if let q = hedef.query, !q.isEmpty { yol += "?" + q }
        guard let c: Cevap = try? await DVBAPI.shared.post("auth/web-session", body: ["path": yol], token: token) else {
            return nil
        }
        return URL(string: c.data.url)
    }

    /// Web görünümünün çerez ve depolarını siler (İksHesap WebOturumTemizleyici ile aynı küme).
    static func temizle() {
        let tipler: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
        ]
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().removeData(ofTypes: tipler, modifiedSince: .distantPast) {}
            URLCache.shared.removeAllCachedResponses()
        }
    }
}
