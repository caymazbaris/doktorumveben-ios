import AuthenticationServices
import CryptoKit
import SwiftUI

/// Tur 241 — UYGULAMA İÇİ "Apple ile giriş" (App Store kılavuzu 4.8).
///
/// NEDEN BU DOSYA VAR: 1.0 tam bu maddeden reddedildi. Web tarafı Tur 233'te
/// tamamlanmıştı ama native istemci o işi hiç almamıştı; hesap ekranı
/// "Apple ile giriş bir sonraki sürümde uygulama içinde olacak" yazıyordu ve
/// kullanıcıyı WebView'daki üye-ol sayfasına gönderiyordu. 4.8 uygulama İÇİNDE
/// eşdeğer bir seçenek istiyor, ayrıca Apple gömülü WebView'daki web akışını
/// sıkça engelliyor — yani o yol hem kılavuza aykırıydı hem pratikte kırılgandı.
///
/// AKIŞ: cihaz Apple ile kendi konuşur (ASAuthorization), bize yalnız
/// `identity_token` gelir; onu `POST /api/v1/auth/apple`'a veririz, sunucu imzayı
/// Apple'ın JWKS'ine karşı doğrular (AppleAuthApiController + AppleIdTokenVerifier)
/// ve Sanctum jetonu döner. Tarayıcı yönlendirmesi, state, client_secret YOK.
///
/// NONCE: sunucu `nonce`'u claim ile BİREBİR karşılaştırıyor (hash_equals,
/// AppleIdTokenVerifier:97) — kendisi hash'lemiyor. O yüzden Apple'a verdiğimiz
/// değerin AYNISINI gönderiyoruz. Ham rastgele diziyi SHA256'layıp o özeti hem
/// isteğe hem sunucuya veriyoruz: ham değer cihazdan hiç çıkmaz, karşılaştırma
/// yine tutar. (Apple `nonce`'u olduğu gibi token'a yazar, kendisi hash'lemez.)

/// `POST /auth/apple` yanıtı.
struct DVBAppleAuthResponse: Decodable {
    let token: String?
    let user: DVBUser?
    /// Sunucu telefonu eksik/doğrulanmamış hesaplarda true döner; web'deki
    /// telefon adımının karşılığı. Girişi ENGELLEMEZ, yalnız uyarı gösteririz.
    let needsPhone: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case token, user, message
        case needsPhone = "needs_phone"
    }
}

enum DVBAppleSignIn {

    /// Ham nonce (cihazda kalır) + Apple'a ve sunucuya gidecek SHA256 özeti.
    static func yeniNonce() -> (ham: String, ozet: String) {
        var bayt = [UInt8](repeating: 0, count: 32)
        // Kriptografik rastgelelik: başarısız olursa UUID'ye düş (yine tahmin edilemez).
        if SecRandomCopyBytes(kSecRandomDefault, bayt.count, &bayt) != errSecSuccess {
            let yedek = UUID().uuidString + UUID().uuidString
            bayt = Array(yedek.utf8)
        }
        let ham = bayt.map { String(format: "%02x", $0) }.joined()
        let ozet = SHA256.hash(data: Data(ham.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (ham, ozet)
    }
}

/// Hesap ekranındaki gerçek Apple düğmesi. Apple'ın kendi bileşeni kullanılır —
/// kılavuz düğmenin görünüm/etiket kurallarını şart koşuyor, elle çizmiyoruz.
@MainActor
struct DVBAppleSignInButton: View {

    @EnvironmentObject private var session: DVBSession

    /// Sürerken üst ekran "Giriş yap" düğmesini de kilitleyebilsin.
    @Binding var busy: Bool
    /// Hata metni üst ekranın kendi alanında gösterilir (tek yerden).
    @Binding var error: String?

    @State private var nonce: (ham: String, ozet: String) = DVBAppleSignIn.yeniNonce()

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { istek in
                istek.requestedScopes = [.fullName, .email]
                istek.nonce = nonce.ozet
            },
            onCompletion: { sonuc in
                switch sonuc {
                case let .success(yetki):
                    Task { await girisYap(yetki) }
                case let .failure(hata):
                    // Kullanıcı iptal ettiyse hata GÖSTERMEYİZ; bu bir arıza değil.
                    let kod = (hata as? ASAuthorizationError)?.code
                    if kod != .canceled {
                        // DVB-000119 — App Store 1.0 (13) "An error occurred during Sign in
                        // with Apple login process" dedi ve elimizde HİÇBİR ayrıntı yoktu:
                        // Apple'ın kendi hata kodu hiçbir yere yazılmıyordu. Kodu mesaja
                        // koyuyoruz ki bir ekran görüntüsü bile hangi halkanın koptuğunu
                        // söylesin (1000 = bilinmeyen/yetkilendirme, 1001 = geçersiz yanıt,
                        // 1004 = ağ). Kullanıcı için anlamsız ama zararsız; teşhis için şart.
                        let ek = kod.map { " (kod \($0.rawValue))" } ?? ""
                        error = "Apple ile giriş tamamlanamadı\(ek)."
                    }
                    // Nonce tek kullanımlık: her denemede yenilenmeli.
                    nonce = DVBAppleSignIn.yeniNonce()
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 46)
        .disabled(busy)
    }

    private func girisYap(_ yetki: ASAuthorization) async {
        guard
            let kimlik = yetki.credential as? ASAuthorizationAppleIDCredential,
            let jetonVerisi = kimlik.identityToken,
            let jeton = String(data: jetonVerisi, encoding: .utf8)
        else {
            error = "Apple kimlik bilgisi okunamadı."
            nonce = DVBAppleSignIn.yeniNonce()
            return
        }

        busy = true
        error = nil
        do {
            // Ad YALNIZCA ilk yetkilendirmede gelir; sonraki girişlerde nil olur.
            // Sunucu da bunu biliyor ve mevcut adı korur.
            try await session.signInWithApple(
                identityToken: jeton,
                nonce: nonce.ozet,
                firstName: kimlik.fullName?.givenName,
                lastName: kimlik.fullName?.familyName
            )
        } catch {
            self.error = (error as? DVBError)?.errorDescription ?? "Apple ile giriş yapılamadı."
        }
        nonce = DVBAppleSignIn.yeniNonce()
        busy = false
    }
}
