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
        } catch DVBError.unauthorized {
            signOut()
        } catch {
            // Ağ yoksa oturumu DÜŞÜRME — çevrimdışı açılışta kullanıcı atılmasın.
        }
    }

    func signIn(email: String, password: String) async throws {
        let res: DVBLoginResponse = try await DVBAPI.shared.post("auth/login", body: [
            "email": email,
            "password": password,
            "device_name": deviceName(),
        ])

        // 2FA açık hesap: jeton yerine OTP isteniyor. Native OTP ekranı Faz 4'te;
        // şimdilik dürüst hata verip web girişine yönlendiriyoruz.
        if res.requiresOtp == true {
            throw DVBError.server(200, "Hesabınızda iki adımlı doğrulama açık. Şimdilik web üzerinden giriş yapın.")
        }
        guard let token = res.token else {
            throw DVBError.server(200, res.message ?? "Giriş yapılamadı.")
        }

        DVBKeychain.save(token)
        self.token = token
        self.user = res.user
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

        DVBKeychain.save(token)
        self.token = token
        self.user = res.user
    }

    func signOut() {
        if let token {
            // Sunucudaki jetonu da düşür; başarısız olsa bile yerelde siliyoruz.
            // Tip AÇIKÇA yazılır: `post` genelidir, `try?` ile `as` birlikte çıkarım yapamaz.
            Task {
                let _: DVBMessage? = try? await DVBAPI.shared.post("auth/logout", token: token)
            }
        }
        DVBKeychain.delete()
        token = nil
        user = nil
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
