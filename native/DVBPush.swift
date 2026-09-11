import Foundation
import UIKit
import UserNotifications

/// DVB-000109 — iOS bildirimi DOĞRUDAN APNs ile (Firebase yok).
///
/// Akış: giriş → izin iste → `registerForRemoteNotifications` → AppDelegate jetonu alır →
/// sunucuya `POST /push/device-token` (platform: ios). Çıkışta `DELETE`. Bildirime
/// dokununca payload'daki `url` açılır (DVBRootView `acilacakURL`'i dinler).
///
/// ⚠ İZİN YALNIZ GİRİŞ SONRASI İSTENİR: giriş yapmamış kullanıcıya bildirim gönderemeyiz;
/// ilk açılışta izin sormak hem anlamsız hem App Review'da kötü görünür.
///
/// ⚠ Sunucu hangi jetonun kime ait olduğunu kullanıcıya göre tutar; başka biri aynı cihazdan
/// giriş yaparsa kayıt ona DEVREDİLİR (DeviceTokenController). Bu yüzden her girişte yeniden
/// yazılır — cihaz aynı, sahip değişmiş olabilir.
enum DVBPush {
    /// Dokunulan bildirimin açılacak adresi (object: URL).
    static let acilacakURL = Notification.Name("dvb.push.acilacakURL")

    /// Son APNs jetonu (hex). Sunucuya yazma giriş sonrasına kalabilir; o yüzden saklanır.
    private static let jetonAnahtari = "dvb.push.apnsJeton"

    /// Girişten sonra çağrılır: izin verilirse Apple'a kaydolur, jeton AppDelegate'e düşer.
    static func kaydol() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { verildi, _ in
            guard verildi else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        // İzin daha önce verildiyse Apple yeni jeton üretmez; eldekini yeniden yaz (sahip değişmiş olabilir).
        sunucuyaYaz()
    }

    /// AppDelegate'ten: jeton geldi → sakla, oturum varsa sunucuya yaz.
    static func jetonGeldi(_ veri: Data) {
        let hex = veri.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: jetonAnahtari)
        sunucuyaYaz(hex)
    }

    /// Oturum açıkken (Keychain'de jeton varsa) sunucuya bildir. Hata YUTULUR: ağ yoksa bir
    /// sonraki girişte/açılışta yeniden denenir; bildirim ikincildir, akışı bozmaz.
    static func sunucuyaYaz(_ hex: String? = nil) {
        guard let hex = hex ?? UserDefaults.standard.string(forKey: jetonAnahtari),
              let oturum = DVBKeychain.read(), !oturum.isEmpty else { return }
        let surum = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let cihaz = UIDevice.current.name
        Task {
            let _: DVBMessage? = try? await DVBAPI.shared.post("push/device-token", body: [
                "token": hex,
                "platform": "ios",
                "app_version": surum,
                "device_name": cihaz,
            ], token: oturum)
        }
    }

    /// Çıkışta sunucudaki cihaz kaydını bırak. ÇIKIŞTAN ÖNCE çağrılmalı: oturum jetonu
    /// düşürülünce bu istek 401 alır. Başarısız olsa da sorun değil — ölü jeton ilk
    /// gönderimde (410/BadDeviceToken) sunucuda zaten silinir.
    static func jetonuBirak(oturum: String) async {
        guard let hex = UserDefaults.standard.string(forKey: jetonAnahtari) else { return }
        let _: DVBMessage? = try? await DVBAPI.shared.delete("push/device-token", body: ["token": hex], token: oturum)
    }

    /// Bildirim payload'ındaki `url` → tam adres (sunucu göreli yol gönderir: "/hesabim/randevular").
    static func adres(_ userInfo: [AnyHashable: Any]) -> URL? {
        guard let ham = userInfo["url"] as? String, !ham.isEmpty else { return nil }
        return URL(string: ham, relativeTo: DVBConfig.webBase)?.absoluteURL
    }
}

/// UNUserNotificationCenter delegesi: uygulama ön plandayken de göster; dokununca adresi yayınla.
final class DVBPushDelegesi: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DVBPushDelegesi()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .badge, .sound])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let url = DVBPush.adres(response.notification.request.content.userInfo) {
            NotificationCenter.default.post(name: DVBPush.acilacakURL, object: url)
        }
        completionHandler()
    }
}
