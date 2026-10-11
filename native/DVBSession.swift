import Foundation
import SwiftUI
import Network

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
    /// DVB-000368 — sunucunun SON kararı cihazda saklanır (DVBHekimOnbellegi) ve soğuk açılışta önce o yüklenir: internetsiz
    /// ya da sunucu yavaşken hekim hasta düzenine düşmez. Saklanan bir tahmin değil, sunucunun en son 200/403 yanıtıdır;
    /// ilk başarılı `my/doctor` onu yeniden doğrular (403 → silinir, hasta düzenine geçilir).
    @Published private(set) var hekim: DVBHekimBilgisi?

    var isLoggedIn: Bool { token != nil }

    /// DVB-000368 — `my/doctor` bu oturumda yanıtlandı mı (200 ya da 403). Önbellekten gelen karar doğrulanmamış sayılır;
    /// bağlantı gelince / uygulama öne gelince yeniden sorulur.
    private var hekimDogrulandi = false
    /// DVB-000368 — otomatik geri yükleme (açılış, bağlantı geldi, öne gelindi) aynı anda bir kez koşar. Açık `restore()`
    /// çağrıları (profil kaydı, ikinci adım doğrulaması) bu bayrağa TAKILMAZ.
    private var otomatikYuklemeSuruyor = false
    private var baglantiIzleyici: NWPathMonitor?
    private var baglantiVardi: Bool?

    init() {
        token = DVBKeychain.read()
        // DVB-000368 — jeton varsa sunucunun son hekim kararı. Jeton okunamadıysa önbellek SİLİNMEZ (kilitli cihazda
        // Keychain geçici olarak okunamayabilir); yalnız kullanılmaz.
        if token != nil { hekim = DVBHekimOnbellegi.oku() }
    }

    /// Uygulama açılışında jeton hâlâ geçerli mi? Değilse sessizce düşür.
    func restore() async {
        guard let token else { return }
        do {
            let me: DVBMe = try await DVBAPI.shared.get("auth/me", token: token)
            guard self.token == token else { return }   // bu arada çıkış yapıldı
            user = me.user
            DVBPush.kaydol()   // DVB-000109 — her açılışta yeniden yaz (jeton/sahip değişmiş olabilir)
            await hekimiYukle()
            await ajandayiTazele()
        } catch DVBError.unauthorized {
            signOut()
        } catch {
            // Ağ yoksa oturumu DÜŞÜRME — çevrimdışı açılışta kullanıcı atılmasın. DVB-000368: bağlantı gelince ya da
            // uygulama öne gelince `yenidenDene()` eksik kalanı tamamlar.
        }
    }

    /// DVB-000368 — açılıştaki geri yükleme (kök görünümün `.task`'ı). Bayrak tutulur: bu sürerken bağlantı/öne gelme
    /// tetiklemesi ikinci bir geri yükleme başlatmaz.
    func acilisYuklemesi() async {
        otomatikYuklemeSuruyor = true
        defer { otomatikYuklemeSuruyor = false }
        await restore()
    }

    /// DVB-000368 — açılışta eksik kalanı tamamla: `auth/me` alınamadıysa tüm geri yükleme, alındı ama `my/doctor`
    /// yanıtlanmadıysa yalnız hekim bilgisi. Her şey yerindeyse hiçbir şey yapmaz (öne her gelişte ağa çıkılmaz).
    func yenidenDene() async {
        guard isLoggedIn, !otomatikYuklemeSuruyor else { return }
        if user != nil && hekimDogrulandi { return }
        otomatikYuklemeSuruyor = true
        defer { otomatikYuklemeSuruyor = false }
        if user == nil {
            await restore()
        } else {
            await hekimiYukle()
        }
    }

    /// DVB-000368 — bağlantı izleyici: yalnız "yoktu → geldi" geçişinde `yenidenDene()`. Kök görünümden bir kez başlatılır
    /// (init'te değil: ekran görüntüsü kipindeki ikinci oturum nesnesi izleyici açmasın).
    func baglantiyiIzle() {
        guard baglantiIzleyici == nil else { return }
        let izleyici = NWPathMonitor()
        // Kuyruk ana kuyruk: işleyici hangi yalıtımla çıkarsanırsa çıkarsansın ana iş parçacığında çalışır. Zayıf referans
        // önce sabite alınır (iç içe kapanışta yakalanan `weak var` eşzamanlılık uyarısı/hatası vermesin).
        izleyici.pathUpdateHandler = { [weak self] yol in
            let simdiVar = yol.status == .satisfied
            guard let oturum = self else { return }
            Task { @MainActor in oturum.baglantiDegisti(simdiVar) }
        }
        izleyici.start(queue: .main)
        baglantiIzleyici = izleyici
    }

    private func baglantiDegisti(_ simdiVar: Bool) {
        let onceki = baglantiVardi
        baglantiVardi = simdiVar
        // İlk bildirim anlık durumdur, geçiş değil → tepki yok (açılış yüklemesi zaten koşuyor).
        guard simdiVar, onceki == false else { return }
        Task { await yenidenDene() }
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
            guard self.token == token else { return }   // DVB-000368 — çıkış yapan hesabın ajandası widget'a yazılmasın
            if let ham = try? JSONEncoder().encode(ajanda) {
                DVBOfflineStore.yazAjanda(ham)
                DVBOfflineStore.widgetiYenile()
            }
        } catch DVBError.forbidden {
            // DVB-000368 — hekimliği kaldırılan hesapta widget eski ajandayı göstermeye devam etmesin.
            DVBOfflineStore.temizle()
            DVBOfflineStore.widgetiYenile()
        } catch {
            // sessiz: ağ yoksa eski önbellek geçerli kalır
        }
    }

    /// DVB-000267 — hekim bilgisi + bugünkü sayaçlar. 403 → hekim değil. Ağ hatasında eldeki bilgi KORUNUR
    /// (çevrimdışı açılışta hekim hasta sekmelerine düşmesin). DVB-000368: 200 cihaza yazılır, 403 siler — soğuk açılışta
    /// da "eldeki bilgi" var.
    func hekimiYukle() async {
        guard let token else { hekimiBirak(); return }
        do {
            let bilgi: DVBHekimBilgisi = try await DVBAPI.shared.get("my/doctor", token: token)
            guard self.token == token else { return }   // bu arada çıkış yapıldı: karar yazılmaz
            hekim = bilgi
            hekimDogrulandi = true
            DVBHekimOnbellegi.yaz(bilgi)
        } catch DVBError.forbidden {
            guard self.token == token else { return }
            hekimiBirak()
            hekimDogrulandi = true
        } catch DVBError.unauthorized {
            signOut()
        } catch {
            // sessiz — bellekteki (ya da önbellekten gelen) karar korunur; bağlantı gelince yeniden denenir (DVB-000368)
        }
    }

    /// DVB-000368 — hekim kararını bellekten ve cihazdan kaldır.
    private func hekimiBirak() {
        hekim = nil
        DVBHekimOnbellegi.sil()
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
        yeniOturumOncesiTemizle()   // DVB-000368
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
        yeniOturumOncesiTemizle()   // DVB-000368
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
    @discardableResult
    func signInWithApple(identityToken: String, nonce: String,
                         firstName: String?, lastName: String?) async throws -> DVBGirisSonucu {
        var govde: [String: Any] = [
            "identity_token": identityToken,
            "nonce": nonce,
            "device_name": deviceName(),
        ]
        if let firstName, !firstName.isEmpty { govde["first_name"] = firstName }
        if let lastName, !lastName.isEmpty { govde["last_name"] = lastName }

        let res: DVBAppleAuthResponse = try await DVBAPI.shared.post("auth/apple", body: govde)

        // DVB-000280 — iki adımı açık hesapta Apple girişi de kod ister (şifreli girişle aynı karar ve ekran).
        if res.requiresOtp == true {
            guard res.sent != false, let anahtar = res.twoFactorToken, !anahtar.isEmpty else {
                throw DVBError.server(200, res.message ?? "Doğrulama kodu gönderilemedi. Lütfen tekrar deneyin.")
            }
            return .ikinciAdim(DVBIkinciAdim(anahtar: anahtar, mesaj: res.message ?? "Doğrulama kodu gönderildi.", kanal: res.channel))
        }
        guard let token = res.token else {
            throw DVBError.server(200, res.message ?? "Apple ile giriş yapılamadı.")
        }

        DVBWebOturum.temizle()   // DVB-000273 — aynı cihazda önceki kişinin web oturumu kalmasın
        yeniOturumOncesiTemizle()   // DVB-000368
        DVBKeychain.save(token)
        self.token = token
        self.user = res.user
        DVBPush.kaydol()   // DVB-000109
        await hekimiYukle()
        return .tamam
    }

    /// DVB-000280 — ikinci adım kodunu yeniden gönder (bekleyen anahtarla). Şifre gerekmez: Apple ile girende şifre yok,
    /// şifreli girişte de parolayı ekranda tutmaya gerek kalmaz. Yeni kod + tazelenmiş anahtar döner.
    func ikinciAdimKoduYenidenGonder(_ adim: DVBIkinciAdim) async throws -> DVBIkinciAdim {
        let res: DVBLoginResponse = try await DVBAPI.shared.post("auth/otp/resend", body: ["two_factor_token": adim.anahtar])
        guard res.sent != false, let anahtar = res.twoFactorToken, !anahtar.isEmpty else {
            throw DVBError.server(200, res.message ?? "Doğrulama kodu gönderilemedi. Lütfen tekrar deneyin.")
        }
        return DVBIkinciAdim(anahtar: anahtar, mesaj: res.message ?? "Doğrulama kodu yeniden gönderildi.", kanal: res.channel)
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
        hekimiBirak()   // DVB-000368 — saklanan hekim kararı da silinir (aynı cihaza giren hasta hekim düzenini görmesin)
        hekimDogrulandi = false
        unreadCount = 0
        // DVB-000368 — widget önbelleği de temizlenir: çıkış yapan hekimin (maskeli) ajandası ana ekranda kalmasın.
        DVBOfflineStore.temizle()
        DVBOfflineStore.widgetiYenile()
    }

    /// DVB-000368 — yeni jeton yazılmadan önce önceki oturumdan kalabilecek hekim kararı silinir (ek güvence).
    private func yeniOturumOncesiTemizle() {
        hekimiBirak()
        hekimDogrulandi = false
    }

    private func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "ios"
        #endif
    }
}

/// DVB-000368 — SUNUCUNUN SON HEKİM KARARI cihazda: `UserDefaults.standard` (App Group DEĞİL — widget bu bilgiyi
/// kullanmaz; bu yüzden DVBOfflineStore'a da konmaz, o dosya widget hedefine de derleniyor).
/// Saklanan yalnız `my/doctor` yanıtı: hekimin kendi adı/branşı/avatarı, özellik bayrakları, sayaçlar. Hasta verisi YOK.
/// Yazılır: `my/doctor` 200. Silinir: 403, çıkış, yeni giriş. Çözülemeyen kayıt silinir.
enum DVBHekimOnbellegi {
    private static let anahtar = "dvb.hekim.bilgisi"

    static func oku() -> DVBHekimBilgisi? {
        guard let ham = UserDefaults.standard.data(forKey: anahtar) else { return nil }
        guard let bilgi = try? JSONDecoder().decode(DVBHekimBilgisi.self, from: ham) else {
            sil()
            return nil
        }
        return bilgi
    }

    static func yaz(_ bilgi: DVBHekimBilgisi) {
        guard let ham = try? JSONEncoder().encode(bilgi) else { return }
        UserDefaults.standard.set(ham, forKey: anahtar)
    }

    static func sil() {
        UserDefaults.standard.removeObject(forKey: anahtar)
    }

    /// Açılışta ilk sekme seçimi için (kök görünümün durumu oturum nesnesinden önce kurulur): jeton + kayıtlı hekim kararı
    /// var mı. DVBSession.init ile aynı koşul.
    static var acilistaHekimVar: Bool {
        DVBKeychain.read() != nil && oku() != nil
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
