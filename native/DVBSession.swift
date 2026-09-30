import Foundation
import SwiftUI

/// Tur 235 — Oturum durumu. Tek `@StateObject` olarak kökte tutulur, ekranlara
/// `@EnvironmentObject` ile dağıtılır.
///
/// Jeton Keychain'de; bellekte yalnız uygulama açıkken durur. 401 gelen her istek
/// oturumu düşürür (sunucu jetonu iptal etmiş olabilir — Tur 234'te hesap silmede
/// tüm jetonlar düşürülüyor).
@MainActor
final class DVBSession: ObservableObject {

    @Published private(set) var token: String?
    @Published private(set) var user: DVBUser?
    @Published var unreadCount: Int = 0

    /// DVB-000267 — hesap bir hekim profilini yönetiyorsa dolu; uygulama hekim sekmelerine geçer (DVBRootView).
    /// Karar sunucuda (`GET my/doctor`: hekim → 200, diğer herkes → 403); istemci rol tahmini YAPMAZ.
    @Published private(set) var hekim: DVBHekimBilgisi?

    var isLoggedIn: Bool { token != nil }

    init() {
        token = DVBKeychain.read()
    }

    /// Uygulama açılışında jeton hâlâ geçerli mi? Değilse sessizce düşür.
    func restore() async {
        guard let token else { return }
        do {
            let me: DVBMe = try await DVBAPI.shared.get("auth/me", token: token)
            user = me.user
            DVBPush.kaydol()   // DVB-000109 — her açılışta yeniden yaz (jeton/sahip değişmiş olabilir)
            await hekimiYukle()
            await ajandayiTazele()
        } catch DVBError.unauthorized {
            signOut()
        } catch {
            // Ağ yoksa oturumu DÜŞÜRME — çevrimdışı açılışta kullanıcı atılmasın.
        }
    }

    /// DVB-000111 — Widget'ın göstereceği veriyi tazele.
    ///
    /// ⚠ WIDGET'I BESLEYEN TEK YER BURASI. Widget uzantısı ağa çıkmaz (kendi jetonu
    /// yok, çalışma süresi çok kısa); yalnız App Group'taki önbelleği okur. Uygulama
    /// bu çağrıyı yapmazsa widget SONSUZA KADAR BOŞ kalır — sessiz bir arıza olurdu,
    /// bu yüzden burada duruyor ve her açılışta koşuyor.
    ///
    /// Hata YUTULUR: widget verisi ikincildir, tazelenemedi diye oturum akışı bozulmaz.
    /// Önbellekte eski veri kalır; widget "N saat önce güncellendi" yazar.
    func ajandayiTazele() async {
        guard let token else { return }
        do {
            let ajanda: DVBAgenda = try await DVBAPI.shared.get("my/doctor/agenda", token: token)
            if let ham = try? JSONEncoder().encode(ajanda) {
                DVBOfflineStore.yazAjanda(ham)
                DVBOfflineStore.widgetiYenile()
            }
        } catch {
            // sessiz: ağ yoksa eski önbellek geçerli kalır
        }
    }

    /// DVB-000267 — hekim bilgisi + bugünkü sayaçlar. 403 → hekim değil. Ağ hatasında eldeki bilgi KORUNUR
    /// (çevrimdışı açılışta hekim hasta sekmelerine düşmesin).
    func hekimiYukle() async {
        guard let token else { hekim = nil; return }
        do {
            hekim = try await DVBAPI.shared.get("my/doctor", token: token)
        } catch DVBError.forbidden {
            hekim = nil
        } catch DVBError.unauthorized {
            signOut()
        } catch {
            // sessiz
        }
    }

    /// Şifreyle giriş. İki adım gereken hesapta (web ile aynı karar — DVB-000274) jeton YERİNE bekleyen ikinci adım
    /// döner; ekran kodu sorar ve `ikinciAdimiDogrula` ile tamamlar (DVB-000276).
    @discardableResult
    func signIn(email: String, password: String) async throws -> DVBGirisSonucu {
        let res: DVBLoginResponse = try await DVBAPI.shared.post("auth/login", body: [
            "email": email,
            "password": password,
            "device_name": deviceName(),
        ])

        if res.requiresOtp == true {
            guard res.sent != false, let anahtar = res.twoFactorToken, !anahtar.isEmpty else {
                throw DVBError.server(200, res.message ?? "Doğrulama kodu gönderilemedi. Lütfen tekrar deneyin.")
            }
            return .ikinciAdim(DVBIkinciAdim(anahtar: anahtar, mesaj: res.message ?? "Doğrulama kodu gönderildi.", kanal: res.channel))
        }
        guard let token = res.token else {
            throw DVBError.server(200, res.message ?? "Giriş yapılamadı.")
        }

        DVBWebOturum.temizle()   // DVB-000273 — aynı cihazda önceki kişinin web oturumu kalmasın
        DVBKeychain.save(token)
        self.token = token
        self.user = res.user
        DVBPush.kaydol()   // DVB-000109 — bildirim izni + APNs kaydı YALNIZ giriş sonrası
        await hekimiYukle()
        return .tamam
    }

    /// DVB-000276 — ikinci adım: bekleyen giriş anahtarı + kod (6 haneli ya da kurtarma kodu). Kod web'in
    /// doğrulayıcısından geçer; hatalı kod sunucuda erişim kaydına ve alarma düşer. Başarıda oturum kurulur ve kullanıcı
    /// bilgisi `auth/me`den alınır (doğrulama yanıtı yalnız jeton taşır).
    func ikinciAdimiDogrula(_ adim: DVBIkinciAdim, kod: String) async throws {
        let res: DVBIkinciAdimCevabi = try await DVBAPI.shared.post("auth/otp/verify", body: [
            "two_factor_token": adim.anahtar,
            "code": kod,
            "device_name": deviceName(),
        ])

        DVBWebOturum.temizle()   // DVB-000273 — aynı cihazda önceki kişinin web oturumu kalmasın
        DVBKeychain.save(res.token)
        self.token = res.token
        await restore()          // auth/me + push kaydı + hekim modu + widget verisi
    }

    /// Tur 241 — App Store 4.8: uygulama içi Apple ile giriş.
    ///
    /// Cihaz Apple ile kendi konuştu; burada yalnız jetonu sunucuya taşıyoruz.
    /// `needs_phone` girişi ENGELLEMEZ — hesap açılır, telefon sonra tamamlanır;
    /// aksi hâlde Apple ile giren kullanıcı kapıda kalırdı (kılavuz 4.8 buna izin
    /// vermez: Apple ile giriş diğer yöntemlerle eşdeğer olmalı).
    func signInWithApple(identityToken: String, nonce: String,
                         firstName: String?, lastName: String?) async throws {
        var govde: [String: Any] = [
            "identity_token": identityToken,
            "nonce": nonce,
            "device_name": deviceName(),
        ]
        if let firstName, !firstName.isEmpty { govde["first_name"] = firstName }
        if let lastName, !lastName.isEmpty { govde["last_name"] = lastName }

        let res: DVBAppleAuthResponse = try await DVBAPI.shared.post("auth/apple", body: govde)
        guard let token = res.token else {
            throw DVBError.server(200, res.message ?? "Apple ile giriş yapılamadı.")
        }

        DVBWebOturum.temizle()   // DVB-000273 — aynı cihazda önceki kişinin web oturumu kalmasın
        DVBKeychain.save(token)
        self.token = token
        self.user = res.user
        DVBPush.kaydol()   // DVB-000109
        await hekimiYukle()
    }

    func signOut() {
        if let token {
            // Sunucudaki jetonu da düşür; başarısız olsa bile yerelde siliyoruz.
            // Tip AÇIKÇA yazılır: `post` genelidir, `try?` ile `as` birlikte çıkarım yapamaz.
            // DVB-000109 — SIRA ÖNEMLİ: önce cihaz kaydı bırakılır, sonra oturum düşürülür;
            // tersi olsaydı DELETE 401 alır ve bildirimler çıkış yapan kişiye gitmeye devam ederdi.
            Task {
                await DVBPush.jetonuBirak(oturum: token)
                let _: DVBMessage? = try? await DVBAPI.shared.post("auth/logout", token: token)
            }
        }
        DVBKeychain.delete()
        // DVB-000273 — uygulama içi web sayfalarının oturumu da kapanır; kalsaydı sonraki kişi öncekinin panelini açardı.
        DVBWebOturum.temizle()
        token = nil
        user = nil
        hekim = nil
        unreadCount = 0
    }

    private func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "ios"
        #endif
    }
}

/// DVB-000276 — şifre doğru, ikinci adım bekleniyor: sunucunun "bekleyen giriş" anahtarı ve kullanıcıya gösterilecek
/// "kod şuraya gönderildi" metni. Anahtar yalnız bellekte durur (10 dk geçerli); saklanmaz.
struct DVBIkinciAdim: Equatable {
    let anahtar: String
    let mesaj: String
    let kanal: String?
}

enum DVBGirisSonucu {
    case tamam
    case ikinciAdim(DVBIkinciAdim)
}
